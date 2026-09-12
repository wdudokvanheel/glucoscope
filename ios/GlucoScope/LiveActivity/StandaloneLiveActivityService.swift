import ActivityKit
import Combine
import Foundation
import SwiftUI
import UIKit

struct StandaloneLiveActivitySettings: Codable, Equatable {
    var enabled = false
    var hideWhenLocked = false
    var graphHours = 3
    /// Nil follows the existing application theme, including later theme edits.
    var separateTheme: Theme?
}

@MainActor
final class StandaloneLiveActivityService: ObservableObject {
    @Published private(set) var settings: StandaloneLiveActivitySettings
    @Published private(set) var status = "Off"
    private let preferences: PreferenceService
    private let defaults: UserDefaults
    private var standalone = false
    private var readings: [StoredReadingSnapshot] = []
    private var staleAfter: TimeInterval = 300
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var generation = 0
    private var processing = false
    private var lastContent: GlucoseActivityAttributes.ContentState?
    private var lastStaleDate: Date?

    init(preferences: PreferenceService, defaults: UserDefaults = .standard) {
        self.preferences = preferences
        self.defaults = defaults
        settings = defaults.data(forKey: "standalone.liveActivity.settings")
            .flatMap { try? JSONDecoder().decode(StandaloneLiveActivitySettings.self, from: $0) } ?? StandaloneLiveActivitySettings()
        preferences.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }.store(in: &subscriptions)
    }

    func configure(_ newSettings: StandaloneLiveActivitySettings) {
        settings = newSettings
        settings.graphHours = min(12, max(1, settings.graphHours))
        defaults.set(try? JSONEncoder().encode(settings), forKey: "standalone.liveActivity.settings")
        refresh()
    }

    func setStandaloneActive(_ active: Bool) {
        standalone = active
        timer?.invalidate()
        timer = nil
        if active {
            timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        }
        refresh()
    }

    func update(readings: [StoredReadingSnapshot], staleAfter: TimeInterval) {
        self.readings = readings
        self.staleAfter = max(60, staleAfter)
        refresh()
    }

    func refresh() {
        generation += 1
        guard !processing else { return }
        processing = true
        Task {
            var handled = -1
            while handled != generation {
                handled = generation
                await reconcile()
            }
            processing = false
        }
    }

    private func reconcile() async {
        let activities = Activity<GlucoseActivityAttributes>.activities
        guard standalone && settings.enabled else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            lastContent = nil
            status = settings.enabled ? "Paused in Viewer" : "Off"
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            status = "Live Activities are disabled in iOS Settings"
            return
        }
        let now = Date()
        let content = makeContent(now: now)
        let staleDate = content.sampleDate?.addingTimeInterval(staleAfter)
        let activeActivities = activities.filter { $0.activityState == .active || $0.activityState == .stale }
        if let activity = activeActivities.first {
            for duplicate in activeActivities.dropFirst() { await duplicate.end(nil, dismissalPolicy: .immediate) }
            if lastContent != content || lastStaleDate != staleDate {
                await activity.update(ActivityContent(state: content, staleDate: staleDate))
                lastContent = content
                lastStaleDate = staleDate
            }
            status = content.sampleDate == nil ? "Waiting for your first reading" : (staleDate.map { $0 <= now } == true ? "Showing an outdated reading" : "Showing on your device")
        } else {
            guard UIApplication.shared.applicationState == .active else {
                status = "Open GlucoScope to resume the Live Activity"
                return
            }
            do {
                _ = try Activity<GlucoseActivityAttributes>.request(attributes: GlucoseActivityAttributes(),
                    content: ActivityContent(state: content, staleDate: staleDate), pushType: nil)
                lastContent = content
                lastStaleDate = staleDate
                status = content.sampleDate == nil ? "Waiting for your first reading" : "Showing on your device"
            } catch {
                status = "iOS could not start the Live Activity. Open the app to try again."
            }
        }
    }

    private func makeContent(now: Date) -> GlucoseActivityAttributes.ContentState {
        let theme = settings.separateTheme ?? preferences.theme
        let sorted = readings.filter { $0.sampleDate <= now.addingTimeInterval(30) }.sorted { $0.sampleDate < $1.sampleDate }
        let latest = sorted.last
        // Anchor to the last reading so an outage retains the previous graph instead of
        // gradually emptying it. Staleness is represented separately by ActivityKit.
        let end = latest?.sampleDate ?? now
        let start = end.addingTimeInterval(-Double(settings.graphHours * 3600))
        let graphReadings = sorted.filter { $0.sampleDate >= start }
        // Min/max pairs preserve excursions within 18 time buckets; at most 36 points.
        let bucketWidth = Double(settings.graphHours * 3600) / 18
        let buckets = Dictionary(grouping: graphReadings) { min(17, max(0, Int($0.sampleDate.timeIntervalSince(start) / bucketWidth))) }
        let points = buckets.keys.sorted().flatMap { key -> [GlucoseActivityAttributes.Point] in
            guard let bucket = buckets[key], let low = bucket.min(by: { $0.glucoseMGDL < $1.glucoseMGDL }),
                  let high = bucket.max(by: { $0.glucoseMGDL < $1.glucoseMGDL }) else { return [] }
            let selected = low.id == high.id ? [low] : [low, high].sorted { $0.sampleDate < $1.sampleDate }
            return selected.map { .init(offset: Int($0.sampleDate.timeIntervalSince(start)), value: $0.glucoseMGDL) }
        }
        var trend = "—"
        if let latest, let prior = sorted.last(where: { latest.sampleDate.timeIntervalSince($0.sampleDate) >= 120 && latest.sampleDate.timeIntervalSince($0.sampleDate) <= 600 }) {
            let speed = Double(latest.glucoseMGDL - prior.glucoseMGDL) / (latest.sampleDate.timeIntervalSince(prior.sampleDate) / 60)
            trend = speed > 3 ? "↑↑" : speed > 2 ? "↑" : speed > 1 ? "↗" : speed < -3 ? "↓↓" : speed < -2 ? "↓" : speed < -1 ? "↘" : "→"
        }
        return .init(glucoseMGDL: latest?.glucoseMGDL, sampleDate: latest?.sampleDate, trend: trend,
                     points: points, graphStart: start, graphHours: settings.graphHours, hideWhenLocked: settings.hideWhenLocked,
                     background: theme.background, foreground: theme.text, accent: theme.inRange, lowColor: theme.low,
                     highColor: theme.high, lowMGDL: Int(preferences.bgLow * 18.0182), highMGDL: Int(preferences.bgHigh * 18.0182))
    }
}

struct LiveActivitySettingsView: View {
    @ObservedObject var service: StandaloneLiveActivityService
    @EnvironmentObject private var prefs: PreferenceService
    @State private var themes: [Theme] = []
    private func binding<T>(_ path: WritableKeyPath<StandaloneLiveActivitySettings, T>) -> Binding<T> {
        Binding(get: { service.settings[keyPath: path] }, set: {
            var settings = service.settings; settings[keyPath: path] = $0; service.configure(settings)
        })
    }
    var body: some View {
        Form {
            Section {
                Toggle("Show Live Activity", isOn: binding(\.enabled))
                Label(service.status, systemImage: "waveform.path.ecg").font(.footnote)
            } footer: { Text("Current glucose, trend, reading age and a mini graph while using Bluetooth mode. A waiting message appears before your first reading. Outdated readings keep their value and graph with a clear warning.") }
            Section("Display") {
                Picker("Graph window", selection: binding(\.graphHours)) {
                    ForEach([1, 2, 3, 6, 12], id: \.self) { Text("\($0) hours").tag($0) }
                }
                Toggle("Hide glucose until unlocked", isOn: binding(\.hideWhenLocked))
            }
            Section {
                Toggle("Follow app theme", isOn: Binding(get: { service.settings.separateTheme == nil }, set: {
                    var settings = service.settings; settings.separateTheme = $0 ? nil : prefs.theme; service.configure(settings)
                }))
                if service.settings.separateTheme != nil {
                    ForEach(themes) { theme in
                        Button {
                            var settings = service.settings; settings.separateTheme = theme; service.configure(settings)
                        } label: {
                            HStack {
                                Text(theme.name + (theme.variant.isEmpty ? "" : " · \(theme.variant)"))
                                Spacer()
                                ThemeSwatch(theme)
                                if service.settings.separateTheme == theme { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
            } header: { Text("Theme") } footer: { Text("Uses the same theme collection as the app. Lock-screen privacy applies to the value, trend and entire mini graph. iOS controls redaction and lock-screen access; verify your device’s privacy settings.") }
            Section("How iOS handles Live Activities") {
                Text("Updates arrive when GlucoScope receives readings and can run. iOS limits an activity to eight hours and may end it earlier. Open GlucoScope to restore it. Switching to Viewer ends it while keeping your preference for next time.")
                Text("A Live Activity does not keep Bluetooth collection running and cannot guarantee continuous updates. The stale-reading threshold follows Sensor settings.")
                Button("Open iOS settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }.font(.footnote)
        }
        .navigationTitle("Live Activity")
        .tint(prefs.theme.accentColor)
        .onAppear {
            if let url = Bundle.main.url(forResource: "themes", withExtension: "json"), let data = try? Data(contentsOf: url) {
                themes = (try? JSONDecoder().decode([Theme].self, from: data)) ?? []
            }
            service.refresh()
        }
    }
}
