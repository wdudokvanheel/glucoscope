import SwiftUI

enum StandaloneTab: Hashable {
    case graph
    case stats
    case sensor
    case settings
}

struct ModeChoiceView: View {
    @EnvironmentObject private var prefs: PreferenceService
    let choose: (AppMode) -> Void

    var body: some View {
        ThemedScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ThemedLogoGraphic()
                        .frame(height: 150)
                        .padding(.horizontal, 32)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("How will you use GlucoScope?")
                            .font(.largeTitle.bold())
                        Text("Choose where your glucose readings come from. You can change this later in Settings.")
                            .foregroundStyle(prefs.theme.textColor.opacity(0.72))
                    }

                    modeCard(
                        title: "Viewer",
                        subtitle: "View readings from Nightscout or your GlucoScope server.",
                        icon: "eye.fill",
                        action: { choose(.viewer) }
                    )
                    modeCard(
                        title: "Bluetooth sensor",
                        subtitle: "Collect readings directly from a Libre 2 sensor and keep a local history on this iPhone.",
                        icon: "antenna.radiowaves.left.and.right",
                        action: { choose(.standalone) }
                    )
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(prefs.theme.textColor)
    }

    private func modeCard(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(prefs.theme.accentColor)
                    .frame(width: 48, height: 48)
                    .background(prefs.theme.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.title3.bold())
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(prefs.theme.textColor.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(prefs.theme.accentColor)
            }
            .padding(18)
            .background(prefs.theme.surfaceColor, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

struct StandaloneOnboardingView: View {
    @EnvironmentObject private var prefs: PreferenceService
    @ObservedObject var glucose: StandaloneGlucoseService
    @State private var page = 0

    var body: some View {
        NavigationStack {
            ThemedScreen {
                VStack(spacing: 22) {
                    Spacer(minLength: 8)
                    Image(systemName: page == 0 ? "iphone.and.arrow.forward" : "wave.3.right.circle.fill")
                        .font(.system(size: 76, weight: .light))
                        .foregroundStyle(prefs.theme.accentColor)

                    VStack(spacing: 10) {
                        Text(page == 0 ? "Read directly from your sensor" : "Connect your first sensor")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text(page == 0
                             ? "GlucoScope stores standalone readings on this iPhone. Your Viewer history stays separate."
                             : setupExplanation)
                            .foregroundStyle(prefs.theme.textColor.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if page == 0 {
                        VStack(alignment: .leading, spacing: 15) {
                            onboardingFeature("wave.3.right", "Scan once with NFC to securely prepare Bluetooth")
                            onboardingFeature("chart.xyaxis.line", "See committed local readings in Graph and Stats")
                            onboardingFeature("bell", "Choose uploads, alarms and Live Activity separately")
                        }
                        .padding(18)
                        .background(prefs.theme.surfaceColor, in: RoundedRectangle(cornerRadius: 16))
                    } else {
                        setupPanel
                    }

                    Spacer()
                    if page == 0 {
                        Button("Continue") { withAnimation { page = 1 } }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("Continue to app") { finish() }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(prefs.theme.textColor)
            .tint(prefs.theme.accentColor)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { finish() }
                }
            }
        }
    }

    private var setupExplanation: String {
        "Hold the top of your iPhone near the sensor when asked. Setup is verified only after a fresh Bluetooth reading arrives."
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if glucose.coordinator.isScanningNFC {
                Label("Scanning with NFC…", systemImage: "wave.3.right")
            } else {
                setupStateLabel
            }
            Button {
                glucose.startSensorSetup()
            } label: {
                Label(glucose.coordinator.sensorName == nil ? "Scan sensor" : "Scan again", systemImage: "wave.3.right.circle")
            }
            .buttonStyle(.bordered)
            .disabled(glucose.coordinator.isScanningNFC || !glucose.coordinator.isNFCAvailable)

            DisclosureGroup("Having trouble?") {
                Text("Keep the phone still, remove a thick case, and try the upper edge of the iPhone. Bluetooth must remain on. You can continue now and retry from the Sensor tab.")
                    .font(.footnote)
                    .foregroundStyle(prefs.theme.textColor.opacity(0.72))
                    .padding(.top, 6)
            }
        }
        .padding(18)
        .background(prefs.theme.surfaceColor, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private var setupStateLabel: some View {
        switch glucose.setupState {
        case .idle:
            Label("Ready to scan", systemImage: "sensor")
        case .waiting:
            Label("Sensor prepared. Waiting for the first fresh reading…", systemImage: "clock")
        case .verified(let readingAt):
            Label("Connected · reading received \(readingAt.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(prefs.theme.inRangeColor)
        case .timedOut(_, let stillTrying):
            Label(stillTrying ? "No reading yet. GlucoScope is still trying." : "No reading arrived. Scan again to retry.", systemImage: "exclamationmark.triangle")
        case .failed(let message):
            Label("Scan failed: \(message)", systemImage: "xmark.circle")
        }
    }

    private func onboardingFeature(_ icon: String, _ text: String) -> some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: icon).foregroundStyle(prefs.theme.accentColor)
        }
    }

    private func finish() {
        prefs.standaloneOnboardingCompleted = true
    }
}

struct StandaloneRootView<SettingsContent: View>: View {
    @EnvironmentObject private var prefs: PreferenceService
    @ObservedObject var glucose: StandaloneGlucoseService
    @Binding var selectedTab: StandaloneTab
    let settingsContent: SettingsContent

    init(
        glucose: StandaloneGlucoseService,
        selectedTab: Binding<StandaloneTab>,
        @ViewBuilder settings: () -> SettingsContent
    ) {
        self.glucose = glucose
        _selectedTab = selectedTab
        self.settingsContent = settings()
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { StandaloneGraphView(glucose: glucose) }
                .tabItem { Label("Graph", systemImage: "chart.xyaxis.line") }
                .tag(StandaloneTab.graph)
            NavigationStack { StandaloneStatsView(glucose: glucose) }
                .tabItem { Label("Stats", systemImage: "chart.pie.fill") }
                .tag(StandaloneTab.stats)
            NavigationStack { SensorView(glucose: glucose) }
                .tabItem { Label("Sensor", systemImage: "sensor") }
                .tag(StandaloneTab.sensor)
            NavigationStack { settingsContent }
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(StandaloneTab.settings)
        }
        .tint(prefs.theme.accentColor)
        .preferredColorScheme(prefs.theme.isLight ? .light : .dark)
    }
}

struct StandaloneGraphView: View {
    @EnvironmentObject private var prefs: PreferenceService
    @ObservedObject var glucose: StandaloneGlucoseService
    @State private var range = GraphRange(hours: 12, window: 5)
    @State private var showRange = false

    private var measurements: [GlucoseMeasurement] {
        glucose.graphMeasurements(hours: range.hours, windowMinutes: range.window)
    }

    var body: some View {
        ZStack {
            prefs.theme.backgroundColor.ignoresSafeArea()
            VStack(spacing: 14) {
                if let attention = attentionMessage {
                    Label(attention, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(prefs.theme.textColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(prefs.theme.surfaceColor, in: RoundedRectangle(cornerRadius: 10))
                }
                currentCard
                    .frame(height: 155)

                ZStack {
                    if measurements.isEmpty {
                        StandaloneEmptyState(
                            title: "No local readings yet",
                            message: "Set up a sensor or wait for the next reading.",
                            icon: "chart.xyaxis.line"
                        )
                    } else {
                        ColoredLineGraph(data: measurements)
                            .padding(.horizontal, 6)
                    }
                    if showRange {
                        GraphOverlayMenu(range: range) { selected in
                            range = selected
                            withAnimation { showRange = false }
                        }
                        .transition(.opacity)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { withAnimation { showRange.toggle() } }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .navigationTitle("Glucose")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showRange.toggle() } label: {
                    Text("\(range.hours)h").font(.subheadline.weight(.semibold))
                }
            }
        }
        .task { await glucose.refresh() }
    }

    private var currentCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14).fill(currentColor)
            if let value = glucose.latestValueMMOL {
                HStack(alignment: .center, spacing: 14) {
                    Text(value, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 70, weight: .semibold, design: .rounded))
                    Image(systemName: glucose.trendSymbol)
                        .font(.system(size: 32, weight: .bold))
                }
                .foregroundStyle(prefs.theme.indicatorLabelColor)
                VStack {
                    Spacer()
                    HStack {
                        Text("mmol/L")
                        Spacer()
                        Text(ageText)
                    }
                    .font(.caption)
                    .foregroundStyle(prefs.theme.indicatorLabelColor.opacity(0.76))
                    .padding(12)
                }
            } else {
                VStack(spacing: 8) {
                    Text("—").font(.system(size: 64, weight: .semibold))
                    Text("Waiting for a sensor reading").font(.caption)
                }
                .foregroundStyle(prefs.theme.indicatorLabelColor)
            }
        }
        .opacity(glucose.isLatestReadingStale && glucose.latestReading != nil ? 0.72 : 1)
    }

    private var currentColor: Color {
        guard let value = glucose.latestValueMMOL else { return .gray }
        if value < prefs.bgLow { return prefs.theme.lowColor }
        if value < prefs.bgHigh { return prefs.theme.inRangeColor }
        if value >= prefs.bgUpper { return prefs.theme.upperColor }
        return prefs.theme.highColor
    }

    private var ageText: String {
        guard let age = glucose.latestReadingAge else { return "No reading" }
        if age < 60 { return "Now" }
        let minutes = Int(age / 60)
        return glucose.isLatestReadingStale ? "Outdated · \(minutes) min ago" : "\(minutes) min ago"
    }

    private var attentionMessage: String? {
        let coordinator = glucose.coordinator
        if coordinator.sensorName == nil { return "No sensor configured. Open Sensor to get started." }
        if coordinator.isScanningNFC { return "Finish the NFC scan to continue setup." }
        switch glucose.setupState {
        case .waiting: return "Waiting for the first fresh reading to verify setup."
        case .timedOut(_, let trying): return trying ? "Setup timed out; connection attempts are continuing." : "Setup timed out. Open Sensor to retry."
        case .failed: return "Sensor setup needs attention. Open Sensor for details."
        default: break
        }
        if !coordinator.isRunning { return "Sensor collection is stopped. Open Sensor to reconnect." }
        if glucose.isLatestReadingStale { return "The latest reading is outdated. Connection and glucose freshness are shown separately." }
        return nil
    }
}

private enum StatsWindow: String, CaseIterable, Identifiable {
    case today = "Today"
    case seven = "7 days"
    case fourteen = "14 days"
    case thirty = "30 days"
    case ninety = "90 days"
    var id: String { rawValue }
    var dayCount: Int? {
        switch self {
        case .today: return nil
        case .seven: return 7
        case .fourteen: return 14
        case .thirty: return 30
        case .ninety: return 90
        }
    }
}

private struct GlucoseMetric: Identifiable {
    let id: String
    let title: String
    let value: String
    let icon: String
    let color: Color
    let explanation: String
}

struct StandaloneStatsView: View {
    @EnvironmentObject private var prefs: PreferenceService
    @ObservedObject var glucose: StandaloneGlucoseService
    @State private var window: StatsWindow = .fourteen
    @State private var detail: GlucoseMetric?

    private var cutoff: Date {
        if let days = window.dayCount {
            return Calendar.current.date(byAdding: .day, value: -days, to: glucose.now) ?? .distantPast
        }
        return Calendar.current.startOfDay(for: glucose.now)
    }
    private var selected: [StoredReadingSnapshot] { glucose.readings(since: cutoff) }

    var body: some View {
        ZStack {
            prefs.theme.backgroundColor.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Period", selection: $window) {
                        ForEach(StatsWindow.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if selected.isEmpty {
                        StandaloneEmptyState(
                            title: "No readings in this period",
                            message: "Statistics appear after standalone readings are saved on this iPhone.",
                            icon: "chart.pie"
                        )
                        .frame(minHeight: 350)
                    } else {
                        coverageView
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(metrics) { metric in metricCard(metric) }
                        }
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { metric in
            NavigationStack {
                VStack(alignment: .leading, spacing: 18) {
                    Label(metric.value, systemImage: metric.icon)
                        .font(.largeTitle.bold())
                        .foregroundStyle(metric.color)
                    Text(metric.explanation)
                    Text(coverageText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(24)
                .navigationTitle(metric.title)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { detail = nil } } }
            }
            .presentationDetents([.medium])
        }
        .task { await glucose.refresh() }
    }

    private var coverageView: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "calendar.badge.clock").foregroundStyle(prefs.theme.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(coverageText).font(.subheadline.weight(.semibold))
                Text("Calculated from \(selected.count) locally saved samples. Gaps are not counted as recorded time.")
                    .font(.caption)
                    .foregroundStyle(prefs.theme.textColor.opacity(0.65))
            }
            Spacer()
        }
        .padding(14)
        .background(prefs.theme.surfaceColor, in: RoundedRectangle(cornerRadius: 14))
    }

    private func metricCard(_ metric: GlucoseMetric) -> some View {
        Button { detail = metric } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: metric.icon).font(.title2).foregroundStyle(metric.color)
                Text(metric.value).font(.title2.bold()).foregroundStyle(prefs.theme.textColor)
                Text(metric.title).font(.caption).foregroundStyle(prefs.theme.textColor.opacity(0.68))
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .padding(14)
            .background(prefs.theme.surfaceColor, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var coverageText: String {
        let days = Set(selected.map { Calendar.current.startOfDay(for: $0.sampleDate) }).count
        if window == .today { return days == 1 ? "Today’s available data" : "Partial data for today" }
        return "\(days) \(days == 1 ? "day" : "days") of data available for the selected \(window.rawValue)"
    }

    private var metrics: [GlucoseMetric] {
        let values = selected.map { Double($0.glucoseMGDL) / 18.0182 }
        let count = Double(values.count)
        let low = values.filter { $0 < prefs.bgLow }.count
        let inRange = values.filter { $0 >= prefs.bgLow && $0 <= prefs.bgHigh }.count
        let high = values.filter { $0 > prefs.bgHigh && $0 < prefs.bgUpper }.count
        let veryHigh = values.filter { $0 >= prefs.bgUpper }.count
        let average = values.reduce(0, +) / count
        let variance = values.count > 1
            ? values.map { pow($0 - average, 2) }.reduce(0, +) / Double(values.count - 1)
            : 0
        let cv = average > 0 && values.count > 1 ? sqrt(variance) / average * 100 : nil
        func percent(_ value: Int) -> String { String(format: "%.0f%%", Double(value) / count * 100) }
        return [
            GlucoseMetric(id: "range", title: "Time in range", value: percent(inRange), icon: "checkmark.circle.fill", color: prefs.theme.inRangeColor, explanation: String(format: "The share of recorded samples between your Low and High display thresholds (%.1f–%.1f mmol/L).", prefs.bgLow, prefs.bgHigh)),
            GlucoseMetric(id: "average", title: "Average glucose", value: String(format: "%.1f mmol/L", average), icon: "sum", color: prefs.theme.accentColor, explanation: "The arithmetic mean of the available glucose samples in this period."),
            GlucoseMetric(id: "below", title: "Below range", value: percent(low), icon: "arrow.down.circle.fill", color: prefs.theme.lowColor, explanation: "The share of recorded samples below your Low display threshold."),
            GlucoseMetric(id: "above", title: "Above range", value: percent(high), icon: "arrow.up.circle", color: prefs.theme.highColor, explanation: "The share above High and below Very high. Very-high samples are shown separately."),
            GlucoseMetric(id: "veryHigh", title: "Very high", value: percent(veryHigh), icon: "exclamationmark.triangle.fill", color: prefs.theme.upperColor, explanation: "The share of recorded samples at or above your Very high display threshold."),
            GlucoseMetric(id: "variability", title: "Variability (CV)", value: cv.map { String(format: "%.0f%%", $0) } ?? "Needs 2 samples", icon: "waveform.path.ecg", color: prefs.theme.accentColor, explanation: "Coefficient of variation: sample standard deviation divided by average glucose. It describes how spread out the available readings are; at least two samples are required.")
        ]
    }
}

struct SensorView: View {
    @EnvironmentObject private var prefs: PreferenceService
    @ObservedObject var glucose: StandaloneGlucoseService
    @State private var confirmReplacement = false
    @State private var confirmForget = false

    private var coordinator: LibreDiagnosticsCoordinator { glucose.coordinator }

    var body: some View {
        List {
            Section("Sensor") {
                LabeledContent("State", value: coordinator.sensorName == nil ? "Not configured" : "Configured")
                if let name = coordinator.sensorName { LabeledContent("Sensor", value: name) }
                if let date = coordinator.sensorPairedAt {
                    LabeledContent("Set up", value: date.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Collection", value: coordinator.isRunning ? "Running" : "Stopped")
                LabeledContent("Bluetooth", value: coordinator.bluetoothState)
                LabeledContent("Last successful reading", value: lastReadingText)
            }

            Section {
                setupStatus
                if coordinator.sensorName == nil {
                    Button { glucose.startSensorSetup() } label: {
                        Label("Set up sensor with NFC", systemImage: "wave.3.right.circle")
                    }
                } else {
                    Button { glucose.reconnectSensorWithNFC() } label: {
                        Label("Reconnect sensor", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button { confirmReplacement = true } label: {
                        Label("Set up replacement sensor", systemImage: "wave.3.right.circle")
                    }
                    Button { coordinator.startNFCHistory() } label: {
                        Label("Import sensor history", systemImage: "clock.arrow.circlepath")
                    }
                    Button { coordinator.startNFCCalibration() } label: {
                        Label("Refresh sensor calibration", systemImage: "scope")
                    }
                }
            } header: {
                Text("Setup")
            } footer: {
                Text("Reconnect sensor deliberately scans the existing sensor again with NFC. It does not restart sensor wear or clear local history. If another app is collecting from the sensor, close it first; reconnection depends on sensor and iOS behavior.")
            }

            Section("Connection actions") {
                if !coordinator.isRunning, coordinator.sensorName != nil {
                    Button { coordinator.reconnect() } label: {
                        Label("Retry Bluetooth connection", systemImage: "antenna.radiowaves.left.and.right")
                    }
                }
                NavigationLink { SensorSettingsView() } label: {
                    Label("Sensor settings", systemImage: "slider.horizontal.3")
                }
                NavigationLink { SensorLogView(coordinator: coordinator) } label: {
                    Label("Redacted log", systemImage: "doc.text.magnifyingglass")
                }
                if coordinator.sensorName != nil {
                    Button(role: .destructive) { confirmForget = true } label: {
                        Label("Forget sensor", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Sensor")
        .tint(prefs.theme.accentColor)
        .disabled(coordinator.isScanningNFC)
        .overlay {
            if coordinator.isScanningNFC {
                ProgressView("Follow the NFC prompt…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .confirmationDialog("Set up a replacement sensor?", isPresented: $confirmReplacement) {
            Button("Scan replacement") { glucose.startSensorSetup() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The new scan replaces the saved pairing. Existing local history remains available.")
        }
        .confirmationDialog("Forget this sensor?", isPresented: $confirmForget) {
            Button("Forget sensor", role: .destructive) { coordinator.forgetSensor() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Collection stops and the pairing is removed. Local glucose history remains on this iPhone.")
        }
        .task { await glucose.refresh() }
    }

    @ViewBuilder private var setupStatus: some View {
        switch glucose.setupState {
        case .idle: Label("No setup attempt in progress", systemImage: "circle.dashed")
        case .waiting: Label("Waiting for a fresh reading", systemImage: "clock")
        case .verified(let date): Label("Verified with a fresh reading at \(date.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle.fill")
        case .timedOut(_, let trying): Label(trying ? "Timed out; still trying" : "Timed out; retry stopped", systemImage: "exclamationmark.triangle")
        case .failed(let reason): Label("Setup failed: \(reason)", systemImage: "xmark.circle")
        }
    }

    private var lastReadingText: String {
        guard let reading = glucose.latestReading else { return "None" }
        let prefix = glucose.isLatestReadingStale ? "Outdated · " : ""
        return prefix + reading.sampleDate.formatted(date: .abbreviated, time: .shortened)
    }
}

struct SensorSettingsView: View {
    @EnvironmentObject private var prefs: PreferenceService

    var body: some View {
        Form {
            Section {
                Stepper(value: $prefs.staleReadingMinutes, in: 2...30) {
                    LabeledContent("Mark readings outdated after", value: "\(prefs.staleReadingMinutes) min")
                }
            } header: {
                Text("Reading freshness")
            } footer: {
                Text("Freshness uses the sensor sample time. This setting is shared by Graph, Live Activity and sustained-alarm gap handling.")
            }
            Section {
                Toggle("Notify after five-minute timeout", isOn: $prefs.setupTimeoutNotifications)
                Toggle("Keep trying after setup timeout", isOn: $prefs.keepTryingAfterSetupTimeout)
            } header: {
                Text("First-reading verification")
            } footer: {
                Text("These options are independent. You can leave setup while GlucoScope waits; progress remains in the Sensor tab.")
            }
        }
        .navigationTitle("Sensor settings")
        .tint(prefs.theme.accentColor)
    }
}

struct SensorLogView: View {
    @EnvironmentObject private var prefs: PreferenceService
    @ObservedObject var coordinator: LibreDiagnosticsCoordinator

    var body: some View {
        List {
            Section {
                ForEach(coordinator.logs.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(redact(entry.message)).font(.caption.monospaced())
                        Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Sensor identifiers, packet contents and long hexadecimal values are hidden in this view.")
            }
        }
        .navigationTitle("Sensor log")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Clear") { coordinator.clearLog() } } }
        .tint(prefs.theme.accentColor)
    }

    private func redact(_ message: String) -> String {
        message.replacingOccurrences(
            of: "(?i)\\b[0-9a-f]{8,}\\b",
            with: "<redacted>",
            options: .regularExpression
        )
    }
}

struct StandaloneUISettingsView: View {
    @EnvironmentObject private var prefs: PreferenceService

    var body: some View {
        Form {
            Section {
                valueField("Low", value: $prefs.bgLow)
                valueField("High", value: $prefs.bgHigh)
                valueField("Very high", value: $prefs.bgUpper)
            } header: {
                Text("Target range")
            } footer: {
                Text("Graph and Stats share these display thresholds. Existing alarm rules remain independently editable.")
            }
            Section("Graph scale") {
                LabeledContent("Lower bound", value: prefs.graph.boundsLower.formatted(.number.precision(.fractionLength(1))))
                LabeledContent("Upper bound", value: prefs.graph.boundsHigher.formatted(.number.precision(.fractionLength(1))))
            }
        }
        .navigationTitle("UI")
        .tint(prefs.theme.accentColor)
    }

    private func valueField(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number.precision(.fractionLength(1)))
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
            Text("mmol/L").foregroundStyle(.secondary)
        }
    }
}

struct ViewerModeSettingsView: View {
    @EnvironmentObject private var prefs: PreferenceService
    let switchToStandalone: () -> Void

    var body: some View {
        ThemedScreen {
            VStack(spacing: 18) {
                Image(systemName: "eye.fill").font(.system(size: 54)).foregroundStyle(prefs.theme.accentColor)
                Text("Viewer mode").font(.title.bold())
                Text("Readings come from your configured server. Standalone sensor history stays separate.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(prefs.theme.textColor.opacity(0.72))
                Button("Switch to Bluetooth sensor") { switchToStandalone() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
        .foregroundStyle(prefs.theme.textColor)
    }
}

private struct StandaloneEmptyState: View {
    let title: String
    let message: String
    let icon: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(title).font(.title3.bold())
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
