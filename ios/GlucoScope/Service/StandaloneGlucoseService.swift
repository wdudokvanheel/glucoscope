import Combine
import Foundation
@preconcurrency import UserNotifications

enum StandaloneSetupOutcome: String, Codable {
    case waiting
    case verified
    case timedOut
}

struct StandaloneSetupRecord: Codable, Equatable {
    let attemptID: UUID
    let sessionID: UUID
    let sensorFingerprint: Data
    let startedAt: Date
    var outcome: StandaloneSetupOutcome
    var qualifyingReadingID: UUID?
    var completedAt: Date?
}

@MainActor
final class StandaloneGlucoseService: ObservableObject {
    enum SetupState: Equatable {
        case idle
        case waiting(startedAt: Date)
        case verified(readingAt: Date)
        case timedOut(startedAt: Date, stillTrying: Bool)
        case failed(String)
    }

    @Published private(set) var readings: [StoredReadingSnapshot] = []
    @Published private(set) var storeError: String?
    @Published private(set) var setupState: SetupState = .idle
    @Published private(set) var now = Date()

    let coordinator: LibreDiagnosticsCoordinator
    private let store: ReadingStore
    private let preferences: PreferenceService
    private var cancellables = Set<AnyCancellable>()
    private var commitTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var scheduledTimeoutNotificationIdentifier: String?
    private var isStandaloneActive = false

    init(
        coordinator: LibreDiagnosticsCoordinator,
        preferences: PreferenceService
    ) {
        self.coordinator = coordinator
        self.store = coordinator.readingStore
        self.preferences = preferences
        restoreSetupState()

        coordinator.$latestSetupAttempt
            .compactMap { $0 }
            .removeDuplicates()
            .sink { [weak self] attempt in self?.beginVerification(for: attempt) }
            .store(in: &cancellables)

        coordinator.$latestSetupFailure
            .compactMap { $0 }
            .sink { [weak self] message in self?.setupState = .failed(message) }
            .store(in: &cancellables)

        preferences.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.scheduleTimeoutIfNeeded() }
            }
            .store(in: &cancellables)

        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.now = date }
            .store(in: &cancellables)

        commitTask = Task { [weak self, store] in
            let commits = await store.commitStream()
            await self?.refresh()
            for await _ in commits {
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    deinit {
        commitTask?.cancel()
        timeoutTask?.cancel()
    }

    var latestReading: StoredReadingSnapshot? {
        readings.max { $0.sampleDate < $1.sampleDate }
    }

    var staleAfter: TimeInterval {
        TimeInterval(max(1, preferences.staleReadingMinutes) * 60)
    }

    var isLatestReadingStale: Bool {
        guard let latestReading else { return true }
        return now.timeIntervalSince(latestReading.sampleDate) >= staleAfter
    }

    var latestReadingAge: TimeInterval? {
        latestReading.map { max(0, now.timeIntervalSince($0.sampleDate)) }
    }

    var latestValueMMOL: Double? {
        latestReading.map { Double($0.glucoseMGDL) / 18.0182 }
    }

    var trendSymbol: String {
        let recent = canonicalReadings(readings).suffix(2)
        guard recent.count == 2 else { return "arrow.right" }
        let values = Array(recent)
        let minutes = max(1, values[1].sampleDate.timeIntervalSince(values[0].sampleDate) / 60)
        let deltaPerMinute = Double(values[1].glucoseMGDL - values[0].glucoseMGDL) / minutes
        switch deltaPerMinute {
        case 2.0...: return "arrow.up"
        case 1.0..<2.0: return "arrow.up.right"
        case ..<(-2.0): return "arrow.down"
        case -2.0..<(-1.0): return "arrow.down.right"
        default: return "arrow.right"
        }
    }

    var allowsAutomaticSetupRetry: Bool {
        let record = preferences.standaloneSetupRecord
        return StandaloneSetupPolicy.allowsRetry(
            outcome: record?.outcome.rawValue,
            startedAt: record?.startedAt,
            keepTrying: preferences.keepTryingAfterSetupTimeout,
            now: Date()
        )
    }

    func setStandaloneActive(_ active: Bool) {
        isStandaloneActive = active
        if active {
            if let record = preferences.standaloneSetupRecord,
               record.outcome == .waiting,
               StandaloneSetupPolicy.hasTimedOut(startedAt: record.startedAt, now: Date()) {
                setupTimedOut(attemptID: record.attemptID)
            } else {
                scheduleTimeoutIfNeeded()
            }
            Task { await refresh() }
        } else {
            timeoutTask?.cancel()
            timeoutTask = nil
            if let attemptID = preferences.standaloneSetupRecord?.attemptID {
                cancelSetupNotifications(attemptID: attemptID)
            } else {
                cancelScheduledTimeoutNotification()
            }
        }
    }

    func startSensorSetup() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        coordinator.startNFCSetup()
    }

    func reconnectSensorWithNFC() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        coordinator.startNFCReconnection()
    }

    func refresh() async {
        do {
            now = Date()
            if case .notLoaded = await store.currentHealth() {
                try await store.load()
            }
            let snapshot = try await store.snapshot()
            readings = snapshot.readings.sorted { $0.sampleDate < $1.sampleDate }
            storeError = nil
            qualifyCurrentSetupIfPossible()
        } catch {
            storeError = error.localizedDescription
        }
    }

    func graphMeasurements(hours: Int, windowMinutes: Int) -> [GlucoseMeasurement] {
        let cutoff = now.addingTimeInterval(-TimeInterval(hours * 3_600))
        let source = canonicalReadings(readings).filter { $0.sampleDate >= cutoff }
        guard windowMinutes > 1 else { return source.map(Self.measurement) }

        let seconds = TimeInterval(windowMinutes * 60)
        let grouped = Dictionary(grouping: source) {
            Int($0.sampleDate.timeIntervalSince1970 / seconds)
        }
        return grouped.values.compactMap { bucket in
            guard let date = bucket.max(by: { $0.sampleDate < $1.sampleDate })?.sampleDate else { return nil }
            let mean = bucket.map { Double($0.glucoseMGDL) }.reduce(0, +) / Double(bucket.count)
            return GlucoseMeasurement(time: date.timeIntervalSince1970, value: mean / 18.0182)
        }
        .sorted { $0.date < $1.date }
    }

    func readings(since cutoff: Date) -> [StoredReadingSnapshot] {
        canonicalReadings(readings).filter { $0.sampleDate >= cutoff }
    }

    private func canonicalReadings(_ values: [StoredReadingSnapshot]) -> [StoredReadingSnapshot] {
        struct Key: Hashable {
            let sessionID: UUID
            let minute: Int64
        }
        let grouped = Dictionary(grouping: values) {
            Key(sessionID: $0.sessionID, minute: Int64($0.sampleDate.timeIntervalSince1970 / 60))
        }
        return grouped.values.compactMap { bucket in
            bucket.first(where: { $0.kind == .trend })
                ?? bucket.max(by: { $0.receivedAt < $1.receivedAt })
        }
        .sorted { $0.sampleDate < $1.sampleDate }
    }

    private static func measurement(_ reading: StoredReadingSnapshot) -> GlucoseMeasurement {
        GlucoseMeasurement(
            time: reading.sampleDate.timeIntervalSince1970,
            value: Double(reading.glucoseMGDL) / 18.0182
        )
    }

    private func restoreSetupState() {
        guard let record = preferences.standaloneSetupRecord else { return }
        switch record.outcome {
        case .waiting:
            setupState = .waiting(startedAt: record.startedAt)
        case .verified:
            setupState = .verified(readingAt: record.completedAt ?? record.startedAt)
        case .timedOut:
            setupState = .timedOut(
                startedAt: record.startedAt,
                stillTrying: preferences.keepTryingAfterSetupTimeout
            )
        }
    }

    private func beginVerification(for attempt: LibreSetupAttempt) {
        if let previous = preferences.standaloneSetupRecord {
            cancelSetupNotifications(attemptID: previous.attemptID)
        }
        let record = StandaloneSetupRecord(
            attemptID: attempt.id,
            sessionID: attempt.sessionID,
            sensorFingerprint: attempt.sensorFingerprint,
            startedAt: attempt.startedAt,
            outcome: .waiting,
            qualifyingReadingID: nil,
            completedAt: nil
        )
        preferences.standaloneSetupRecord = record
        setupState = .waiting(startedAt: attempt.startedAt)
        scheduleTimeoutIfNeeded()
        Task { await refresh() }
    }

    private func qualifyCurrentSetupIfPossible() {
        guard isStandaloneActive,
              var record = preferences.standaloneSetupRecord,
              record.outcome != .verified else { return }
        let qualifyingReadings = readings.filter { reading in
            StandaloneSetupPolicy.qualifies(
                reading: reading,
                sessionID: record.sessionID,
                startedAt: record.startedAt,
                now: now,
                staleAfter: staleAfter,
                standalone: isStandaloneActive
            )
        }
        guard let reading = qualifyingReadings.max(by: { $0.receivedAt < $1.receivedAt }) else { return }

        record.outcome = .verified
        record.qualifyingReadingID = reading.id
        record.completedAt = Date()
        preferences.standaloneSetupRecord = record
        setupState = .verified(readingAt: reading.sampleDate)
        timeoutTask?.cancel()
        timeoutTask = nil
        cancelTimeoutNotification(attemptID: record.attemptID)
        notifySetupSuccess(for: record)
    }

    private func scheduleTimeoutIfNeeded() {
        timeoutTask?.cancel()
        guard isStandaloneActive,
              let record = preferences.standaloneSetupRecord,
              record.outcome == .waiting else { return }
        let deadline = record.startedAt.addingTimeInterval(StandaloneSetupPolicy.timeout)
        let delay = max(0, deadline.timeIntervalSinceNow)
        scheduleNativeTimeoutNotification(for: record, after: delay)
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.setupTimedOut(attemptID: record.attemptID)
        }
    }

    private func setupTimedOut(attemptID: UUID) {
        guard isStandaloneActive,
              !Task.isCancelled,
              var record = preferences.standaloneSetupRecord,
              record.attemptID == attemptID,
              record.outcome == .waiting else { return }
        record.outcome = .timedOut
        record.completedAt = Date()
        preferences.standaloneSetupRecord = record
        let keepTrying = preferences.keepTryingAfterSetupTimeout
        setupState = .timedOut(startedAt: record.startedAt, stillTrying: keepTrying)
        if !keepTrying { coordinator.stop() }
    }

    private func notifySetupSuccess(for record: StandaloneSetupRecord) {
        let identifier = "sensor-setup-success-\(record.attemptID.uuidString)"
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Sensor connected"
        content.body = "GlucoScope received a fresh reading from your sensor."
        content.sound = .default
        center.add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let remainsCurrent = self.isStandaloneActive
                    && self.preferences.standaloneSetupRecord?.attemptID == record.attemptID
                    && self.preferences.standaloneSetupRecord?.outcome == .verified
                guard !remainsCurrent else { return }
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
                center.removeDeliveredNotifications(withIdentifiers: [identifier])
            }
        }
    }

    private func cancelTimeoutNotification(attemptID: UUID) {
        let identifiers = timeoutNotificationIdentifiers(attemptID: attemptID)
        if let scheduledIdentifier = scheduledTimeoutNotificationIdentifier,
           identifiers.contains(scheduledIdentifier) {
            self.scheduledTimeoutNotificationIdentifier = nil
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func cancelSetupNotifications(attemptID: UUID) {
        cancelTimeoutNotification(attemptID: attemptID)
        let successIdentifier = "sensor-setup-success-\(attemptID.uuidString)"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [successIdentifier])
        center.removeDeliveredNotifications(withIdentifiers: [successIdentifier])
    }

    private func cancelScheduledTimeoutNotification() {
        guard let identifier = scheduledTimeoutNotificationIdentifier else { return }
        scheduledTimeoutNotificationIdentifier = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private func scheduleNativeTimeoutNotification(for record: StandaloneSetupRecord, after delay: TimeInterval) {
        let keepTrying = preferences.keepTryingAfterSetupTimeout
        let identifier = "sensor-setup-timeout-\(record.attemptID.uuidString)-\(keepTrying ? "keep" : "stop")"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(
            withIdentifiers: timeoutNotificationIdentifiers(attemptID: record.attemptID)
        )
        guard preferences.setupTimeoutNotifications else {
            scheduledTimeoutNotificationIdentifier = nil
            return
        }
        scheduledTimeoutNotificationIdentifier = identifier
        let content = UNMutableNotificationContent()
        content.title = "Sensor connection needs attention"
        content.body = keepTrying
            ? "No fresh reading arrived in five minutes. GlucoScope will keep trying."
            : "No fresh reading arrived in five minutes. Open the Sensor tab to retry."
        content.sound = .default
        center.add(UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        )) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let outcome = self.preferences.standaloneSetupRecord?.outcome
                let remainsCurrent = self.isStandaloneActive
                    && self.preferences.setupTimeoutNotifications
                    && self.preferences.standaloneSetupRecord?.attemptID == record.attemptID
                    && self.scheduledTimeoutNotificationIdentifier == identifier
                    && (outcome == .waiting || outcome == .timedOut)
                guard !remainsCurrent else { return }
                if self.scheduledTimeoutNotificationIdentifier == identifier {
                    self.scheduledTimeoutNotificationIdentifier = nil
                }
                center.removePendingNotificationRequests(withIdentifiers: [identifier])
            }
        }
    }

    private func timeoutNotificationIdentifiers(attemptID: UUID) -> [String] {
        let prefix = "sensor-setup-timeout-\(attemptID.uuidString)"
        return ["\(prefix)-keep", "\(prefix)-stop"]
    }
}
