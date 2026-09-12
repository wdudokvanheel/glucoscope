import Combine
import Foundation
import UIKit

@MainActor
final class AppRuntime: ObservableObject {
    let preferences: PreferenceService
    let viewerDataSource: DataSourceService
    let viewerRealtime: RealtimeDataService
    let glucose: StandaloneGlucoseService
    let uploads: ServerUploadCoordinator
    let alarms: StandaloneAlarmService
    let liveActivity: StandaloneLiveActivityService

    @Published var standaloneTab: StandaloneTab
    @Published var showPendingUploadWarning = false
    @Published private(set) var started = false

    private var cancellables = Set<AnyCancellable>()
    private var transitionGeneration = 0

    init() {
        standaloneTab = .graph
        #if DEBUG
        if let argumentIndex = ProcessInfo.processInfo.arguments.firstIndex(of: "-standaloneScreenshotTab"),
           ProcessInfo.processInfo.arguments.indices.contains(argumentIndex + 1),
           let tab = StandaloneTab(rawValue: ProcessInfo.processInfo.arguments[argumentIndex + 1]) {
            standaloneTab = tab
        }
        #endif
        let preferences = PreferenceService()
        let viewerDataSource = DataSourceService(prefences: preferences)
        let coordinator = LibreDiagnosticsCoordinator.shared
        let glucose = StandaloneGlucoseService(
            coordinator: coordinator,
            preferences: preferences
        )
        let uploadURL = LibreDiagnosticsCoordinator.readingsStorageURL
            .deletingLastPathComponent()
            .appendingPathComponent("ServerUploads", isDirectory: true)
            .appendingPathComponent("state.json")

        self.preferences = preferences
        self.viewerDataSource = viewerDataSource
        self.viewerRealtime = RealtimeDataService(dataSourceService: viewerDataSource)
        self.glucose = glucose
        self.uploads = ServerUploadCoordinator(
            readingStore: coordinator.readingStore,
            storageURL: uploadURL
        )
        self.alarms = StandaloneAlarmService(preferences: preferences)
        self.liveActivity = StandaloneLiveActivityService(preferences: preferences)

        glucose.$readings
            .sink { [weak self] readings in self?.updateConsumers(readings: readings) }
            .store(in: &cancellables)
        glucose.$now
            .dropFirst()
            .sink { [weak self] _ in self?.refreshTimeSensitiveServices() }
            .store(in: &cancellables)
        preferences.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.objectWillChange.send()
                    self?.synchronizeAlarmActivation()
                    self?.updateConsumers(readings: self?.glucose.readings ?? [])
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refreshAfterForeground() }
            }
            .store(in: &cancellables)
    }

    var mode: AppMode? { preferences.appMode }

    func start() async {
        guard !started else { return }
        started = true
        await glucose.refresh()
        await uploads.load()
        await applyMode(preferences.appMode)
    }

    func choose(_ mode: AppMode) {
        Task { await applyMode(mode) }
    }

    func requestViewerMode() {
        if uploads.hasPendingUploads {
            showPendingUploadWarning = true
        } else {
            Task { await switchToViewer() }
        }
    }

    func confirmViewerMode() {
        showPendingUploadWarning = false
        Task { await switchToViewer() }
    }

    func switchToStandalone() {
        Task { await applyMode(.standalone) }
    }

    private func applyMode(_ mode: AppMode?) async {
        transitionGeneration += 1
        let generation = transitionGeneration
        guard let mode else {
            glucose.coordinator.stop()
            glucose.setStandaloneActive(false)
            alarms.setStandaloneActive(false)
            liveActivity.setStandaloneActive(false)
            await uploads.setStandaloneActive(false)
            return
        }

        preferences.appMode = mode
        switch mode {
        case .viewer:
            await switchToViewer(generation: generation)
        case .standalone:
            glucose.setStandaloneActive(true)
            alarms.setStandaloneActive(preferences.standaloneOnboardingCompleted)
            liveActivity.setStandaloneActive(true)
            await uploads.setStandaloneActive(true)
            guard generation == transitionGeneration, preferences.appMode == .standalone else {
                await uploads.setStandaloneActive(false)
                return
            }
            updateConsumers(readings: glucose.readings)
            if glucose.allowsAutomaticSetupRetry,
               glucose.coordinator.sensorName != nil,
               !glucose.coordinator.isRunning {
                glucose.coordinator.reconnect()
            }
        }
    }

    private func switchToViewer() async {
        transitionGeneration += 1
        await switchToViewer(generation: transitionGeneration)
    }

    private func switchToViewer(generation: Int) async {
        // Stop all producers and user-visible standalone work at the mode boundary.
        // Uploads alone may finish a request already in flight before going idle.
        glucose.coordinator.stop()
        glucose.setStandaloneActive(false)
        alarms.setStandaloneActive(false)
        liveActivity.setStandaloneActive(false)
        preferences.appMode = .viewer
        await uploads.setStandaloneActive(false)
        guard generation == transitionGeneration else { return }
    }

    private func updateConsumers(readings: [StoredReadingSnapshot]) {
        let threshold = glucose.staleAfter
        alarms.update(readings: readings, staleAfter: threshold)
        liveActivity.update(readings: readings, staleAfter: threshold)
    }

    private func refreshTimeSensitiveServices() {
        alarms.refresh()
        liveActivity.refresh()
    }

    private func synchronizeAlarmActivation() {
        alarms.setStandaloneActive(
            preferences.appMode == .standalone && preferences.standaloneOnboardingCompleted
        )
    }

    private func refreshAfterForeground() async {
        await glucose.refresh()
        await uploads.refresh()
        alarms.refresh()
        liveActivity.refresh()
    }
}
