import Combine
import Foundation
import UserNotifications

struct AlarmHistoryEntry: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let ruleName: String
    let detail: String
}

private struct ScheduledAlarmNotification: Codable {
    let identifier: String
    let ruleID: UUID
    let date: Date
    let mmol: Double?
}

@MainActor
final class StandaloneAlarmService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var configuration: AlarmConfiguration
    @Published private(set) var history: [AlarmHistoryEntry]
    @Published private(set) var activeRuleIDs: Set<UUID> = []
    @Published private(set) var permissionDescription = "Checking notification permission…"
    @Published private(set) var criticalAlertsAvailable = false
    @Published private(set) var schedulingDescription = "Background reminders are prepared as current readings allow."
    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter
    private let prefersStandalone: () -> Bool
    private var engine: StandaloneAlarmEngine
    private var timer: Timer?
    private var staleAfter: TimeInterval = 300
    private var active = false
    private var generation = 0
    private var ruleRevisions: [UUID: Int] = [:]
    private var notificationIDs: [UUID: [String]]
    private var scheduled: [ScheduledAlarmNotification]
    private var lastProjectionEngine: StandaloneAlarmEngine?
    private var lastProjectionConfiguration: AlarmConfiguration?
    private var lastProjectionStaleAfter: TimeInterval?
    private var lastProjectionTimeZone: TimeZone?
    private static let prefix = "standalone.alarm."

    init(preferences: PreferenceService, defaults: UserDefaults = .standard,
         center: UNUserNotificationCenter = .current()) {
        self.defaults = defaults
        self.center = center
        prefersStandalone = { preferences.appMode == .standalone }
        notificationIDs = defaults.data(forKey: "standalone.alarm.notificationIDs")
            .flatMap { try? JSONDecoder().decode([UUID: [String]].self, from: $0) } ?? [:]
        scheduled = defaults.data(forKey: "standalone.alarm.scheduled")
            .flatMap { try? JSONDecoder().decode([ScheduledAlarmNotification].self, from: $0) } ?? []
        configuration = defaults.data(forKey: "standalone.alarm.configuration")
            .flatMap { try? JSONDecoder().decode(AlarmConfiguration.self, from: $0) }
            ?? AlarmConfiguration(rules: [GlucoseAlarmRule(kind: .low, thresholdMMOL: preferences.bgLow),
                                          GlucoseAlarmRule(kind: .high, thresholdMMOL: preferences.bgHigh)])
        history = defaults.data(forKey: "standalone.alarm.history")
            .flatMap { try? JSONDecoder().decode([AlarmHistoryEntry].self, from: $0) } ?? []
        engine = defaults.data(forKey: "standalone.alarm.episodes")
            .flatMap { try? JSONDecoder().decode(StandaloneAlarmEngine.self, from: $0) } ?? StandaloneAlarmEngine()
        super.init()
        center.delegate = self
        Task {
            var categories = await center.notificationCategories()
            let actions = [UNNotificationAction(identifier: "alarm.snooze", title: "Snooze"),
                           UNNotificationAction(identifier: "alarm.dismiss", title: "Dismiss", options: .destructive)]
            let category = UNNotificationCategory(identifier: "standalone.glucose.alarm", actions: actions,
                                                   intentIdentifiers: [], options: .customDismissAction)
            categories.insert(category)
            center.setNotificationCategories(categories)
        }
        persist()
        Task { await refreshPermission() }
    }

    func setStandaloneActive(_ isActive: Bool) {
        guard active != isActive else {
            if !isActive {
                engine.setStandalone(false, now: Date())
                removeAllAlarmNotifications()
                persist()
            }
            return
        }
        active = isActive
        generation += 1
        if !isActive || !engine.standalone { engine.setStandalone(isActive, now: Date()) }
        timer?.invalidate()
        timer = nil
        if isActive {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            Task { await refreshPermission() }
        } else {
            activeRuleIDs = []
            removeAllAlarmNotifications()
        }
        persist()
    }

    func update(readings: [StoredReadingSnapshot], staleAfter: TimeInterval) {
        self.staleAfter = max(60, staleAfter)
        guard active else { return }
        let now = Date()
        // BLE history and NFC observations remain graph/statistics data only. Even a live
        // observation is excluded when its sample is old or older than the current sample.
        let recent = readings.filter {
            $0.primaryOrigin == .bleLive && $0.kind == .trend && now.timeIntervalSince($0.sampleDate) < self.staleAfter
        }.sorted { $0.sampleDate < $1.sampleDate }
        let previous = engine.latestReading?.sampleDate
        // On first launch do not replay a batch of earlier samples as new alarm events.
        let candidates = previous == nil ? Array(recent.suffix(1)) : recent.filter { $0.sampleDate > previous! }
        for reading in candidates {
            engine.ingest(AlarmReading(sampleDate: reading.sampleDate, receivedAt: reading.receivedAt,
                                       mmol: Double(reading.glucoseMGDL) / 18.0182, isCurrent: true),
                          rules: configuration.rules, general: configuration.general, staleAfter: self.staleAfter, now: now)
        }
        refresh()
    }

    func refresh() {
        guard active else { return }
        let previous = engine.episodes
        let previouslyActive = activeRuleIDs
        let now = Date()
        let alreadyScheduled = scheduled.filter { $0.date <= now }
        let emissions = engine.evaluate(rules: configuration.rules, general: configuration.general,
                                         staleAfter: staleAfter, now: now)
        let activeIDs = Set(engine.episodes.filter { $0.value.active && !$0.value.dismissed }.map(\.key))
        if activeRuleIDs != activeIDs { activeRuleIDs = activeIDs }
        for id in previouslyActive.subtracting(activeRuleIDs) { removeNotifications(for: id) }
        if previous != engine.episodes { persist() }
        for emission in emissions {
            if alreadyScheduled.contains(where: { $0.ruleID == emission.ruleID }) {
                record(emission.ruleID, detail: "Scheduled notification deadline reached")
            } else { notify(emission) }
        }
        reconcileScheduledNotifications(now: now)
    }

    func updateGeneral(_ general: AlarmGeneralSettings) {
        for rule in configuration.rules { removeNotifications(for: rule.id) }
        configuration.general = general
        persist()
        refresh()
    }

    func save(_ rule: GlucoseAlarmRule) {
        if let index = configuration.rules.firstIndex(where: { $0.id == rule.id }) {
            configuration.rules[index] = rule
        } else { configuration.rules.append(rule) }
        engine.resetRule(rule.id)
        removeNotifications(for: rule.id)
        // Re-evaluate the latest valid sample against the edited rule without replaying history.
        if let latest = engine.latestReading {
            var evaluator = StandaloneAlarmEngine()
            evaluator.setStandalone(true, now: Date())
            evaluator.ingest(latest, rules: [rule], general: configuration.general, staleAfter: staleAfter, now: Date())
            engine.replaceEpisode(rule.id, with: evaluator.episodes[rule.id])
        }
        persist()
        refresh()
    }

    func delete(_ id: UUID) {
        configuration.rules.removeAll { $0.id == id }
        engine.resetRule(id)
        removeNotifications(for: id)
        persist()
        refresh()
    }

    func dismiss(_ id: UUID) {
        engine.dismiss(id)
        removeNotifications(for: id)
        record(id, detail: "Dismissed this episode")
        persist()
        refresh()
    }

    func snooze(_ id: UUID) {
        guard let rule = configuration.rules.first(where: { $0.id == id }) else { return }
        engine.snooze(rule, general: configuration.general, now: Date())
        removeNotifications(for: id)
        record(id, detail: "Snoozed for \(rule.snooze(configuration.general)) min")
        persist()
        refresh()
    }

    func requestNotificationPermission() async {
        do { _ = try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
        catch { permissionDescription = "Notification permission could not be requested. Check iOS Settings." }
        await refreshPermission()
    }

    func refreshPermission() async {
        let settings = await center.notificationSettings()
        criticalAlertsAvailable = settings.criticalAlertSetting == .enabled
        switch settings.authorizationStatus {
        case .authorized: permissionDescription = settings.soundSetting == .enabled ? "Notifications and sounds allowed" : "Notifications allowed; sounds are off in iOS Settings"
        case .provisional: permissionDescription = "Notifications are delivered quietly"
        case .denied: permissionDescription = "Notifications are off. Enable them in iOS Settings."
        case .notDetermined: permissionDescription = "Notification permission has not been requested"
        default: permissionDescription = "Notification availability is controlled by iOS"
        }
    }

    private func notify(_ emission: AlarmEmission) {
        guard let rule = configuration.rules.first(where: { $0.id == emission.ruleID }) else { return }
        let content = notificationContent(rule: rule, mmol: emission.mmol)
        // Unique request identities prevent an old, cancelled add completion from removing
        // a newer notification for this same rule after Snooze, an edit, or a mode change.
        removeNotifications(for: rule.id)
        let id = Self.prefix + rule.id.uuidString + "." + UUID().uuidString
        notificationIDs[rule.id, default: []].append(id)
        persist()
        let expectedGeneration = generation
        let expectedRevision = ruleRevisions[rule.id, default: 0]
        Task {
            guard active, generation == expectedGeneration, ruleRevisions[rule.id, default: 0] == expectedRevision else { return }
            do {
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
                guard active, generation == expectedGeneration, ruleRevisions[rule.id, default: 0] == expectedRevision,
                      activeRuleIDs.contains(rule.id) else {
                    center.removePendingNotificationRequests(withIdentifiers: [id])
                    center.removeDeliveredNotifications(withIdentifiers: [id])
                    return
                }
                record(rule.id, detail: "Notification requested" + (content.interruptionLevel == .critical ? " · Critical Alert" : ""))
            } catch {
                record(rule.id, detail: "Notification request failed. Check notification settings.")
            }
        }
    }

    private func notificationContent(rule: GlucoseAlarmRule, mmol: Double?) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = rule.name
        content.body = mmol.map { String(format: "Glucose %.1f mmol/L. Open GlucoScope to see your reading.", $0) }
            ?? "No fresh sensor reading for \(rule.missingMinutes) minutes. Check your sensor connection."
        content.categoryIdentifier = "standalone.glucose.alarm"
        content.userInfo = ["alarmID": rule.id.uuidString]
        content.threadIdentifier = Self.prefix + rule.id.uuidString
        let sound = rule.soundOverride ?? configuration.general.sound
        let critical = (rule.dndOverride ?? configuration.general.overrideDoNotDisturb) && criticalAlertsAvailable
        if critical {
            content.interruptionLevel = .critical
            content.sound = sound == .silent ? nil : sound.filename.map { .criticalSoundNamed(UNNotificationSoundName(rawValue: $0)) } ?? .defaultCritical
        } else {
            content.interruptionLevel = .active
            content.sound = sound == .silent ? nil : sound.filename.map { UNNotificationSound(named: UNNotificationSoundName(rawValue: $0)) } ?? .default
        }
        return content
    }

    private func reconcileScheduledNotifications(now: Date) {
        guard lastProjectionEngine != engine || lastProjectionConfiguration != configuration
                || lastProjectionStaleAfter != staleAfter || lastProjectionTimeZone != .current
                || scheduled.contains(where: { $0.date <= now }) else { return }
        lastProjectionEngine = engine
        lastProjectionConfiguration = configuration
        lastProjectionStaleAfter = staleAfter
        lastProjectionTimeZone = .current
        let projected = engine.projectedNotifications(rules: configuration.rules, general: configuration.general,
                                                       staleAfter: staleAfter, now: now, limit: 48)
        let removed = scheduled.filter { pending in
            pending.date > now && !projected.contains { $0.ruleID == pending.ruleID && $0.date == pending.date && $0.mmol == pending.mmol }
        }
        let expired = scheduled.filter { $0.date <= now }
        var added = false
        if !removed.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: removed.map(\.identifier))
            center.removeDeliveredNotifications(withIdentifiers: removed.map(\.identifier))
            for request in removed { notificationIDs[request.ruleID]?.removeAll { $0 == request.identifier } }
        }
        scheduled.removeAll { item in item.date <= now || removed.contains { $0.identifier == item.identifier } }
        for emission in projected {
            guard !scheduled.contains(where: { $0.ruleID == emission.ruleID && $0.date == emission.date && $0.mmol == emission.mmol }),
                  let rule = configuration.rules.first(where: { $0.id == emission.ruleID }) else { continue }
            let identifier = Self.prefix + rule.id.uuidString + "." + UUID().uuidString
            added = true
            scheduled.append(ScheduledAlarmNotification(identifier: identifier, ruleID: rule.id, date: emission.date, mmol: emission.mmol))
            notificationIDs[rule.id, default: []].append(identifier)
            let content = notificationContent(rule: rule, mmol: emission.mmol)
            let expectedGeneration = generation
            Task {
                guard active, generation == expectedGeneration,
                      scheduled.contains(where: { $0.identifier == identifier }) else { return }
                do {
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, emission.date.timeIntervalSinceNow), repeats: false)
                    try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                    guard active, generation == expectedGeneration,
                          scheduled.contains(where: { $0.identifier == identifier }) else {
                        center.removePendingNotificationRequests(withIdentifiers: [identifier])
                        center.removeDeliveredNotifications(withIdentifiers: [identifier])
                        return
                    }
                } catch {
                    scheduled.removeAll { $0.identifier == identifier }
                    notificationIDs[rule.id]?.removeAll { $0 == identifier }
                    lastProjectionEngine = nil
                    schedulingDescription = "A background reminder could not be scheduled. Check iOS notification settings."
                }
            }
        }
        // Keep only the newest delivered reminder for each rule, retaining future requests.
        for ruleID in Set(expired.map(\.ruleID)) {
            let newest = expired.filter { $0.ruleID == ruleID }.max { $0.date < $1.date }?.identifier
            let keep = Set(scheduled.filter { $0.ruleID == ruleID }.map(\.identifier) + [newest].compactMap { $0 })
            let old = (notificationIDs[ruleID] ?? []).filter { !keep.contains($0) }
            center.removeDeliveredNotifications(withIdentifiers: old)
            notificationIDs[ruleID] = (notificationIDs[ruleID] ?? []).filter { keep.contains($0) }
        }
        let description = scheduled.count == 48
            ? "Background reminder capacity reached. Open the app regularly so later reminders can be prepared."
            : "Upcoming reminders are prepared as current readings allow. Open the app regularly to keep them refreshed."
        if schedulingDescription != description { schedulingDescription = description }
        if !removed.isEmpty || !expired.isEmpty || added { persist() }
    }

    private func removeNotifications(for id: UUID) {
        lastProjectionEngine = nil
        ruleRevisions[id, default: 0] += 1
        let identifiers = (notificationIDs.removeValue(forKey: id) ?? []) + [Self.prefix + id.uuidString]
        scheduled.removeAll { $0.ruleID == id }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    private func removeAllAlarmNotifications() {
        lastProjectionEngine = nil
        let ids = notificationIDs.values.flatMap { $0 } + configuration.rules.map { Self.prefix + $0.id.uuidString }
        notificationIDs.removeAll()
        scheduled.removeAll()
        center.removePendingNotificationRequests(withIdentifiers: ids)
        center.removeDeliveredNotifications(withIdentifiers: ids)
    }

    private func record(_ id: UUID, detail: String) {
        guard let rule = configuration.rules.first(where: { $0.id == id }) else { return }
        history.insert(AlarmHistoryEntry(date: Date(), ruleName: rule.name, detail: detail), at: 0)
        history = Array(history.filter { $0.date > Date().addingTimeInterval(-30 * 86400) }.prefix(1000))
        persist()
    }

    private func persist() {
        defaults.set(try? JSONEncoder().encode(configuration), forKey: "standalone.alarm.configuration")
        defaults.set(try? JSONEncoder().encode(engine), forKey: "standalone.alarm.episodes")
        defaults.set(try? JSONEncoder().encode(history), forKey: "standalone.alarm.history")
        defaults.set(try? JSONEncoder().encode(notificationIDs), forKey: "standalone.alarm.notificationIDs")
        defaults.set(try? JSONEncoder().encode(scheduled), forKey: "standalone.alarm.scheduled")
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in
            let alarm = notification.request.identifier.hasPrefix(Self.prefix)
            completionHandler(alarm && !active ? [] : [.banner, .sound, .list])
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            defer { completionHandler() }
            if !active && prefersStandalone() { setStandaloneActive(true) }
            guard active, let raw = response.notification.request.content.userInfo["alarmID"] as? String,
                  let id = UUID(uuidString: raw) else { return }
            // A native deadline can arrive while this process is suspended. Reconcile the
            // persisted episode before applying its individual notification action.
            refresh()
            if response.actionIdentifier == "alarm.snooze" { snooze(id) }
            if response.actionIdentifier == "alarm.dismiss" || response.actionIdentifier == UNNotificationDismissActionIdentifier { dismiss(id) }
        }
    }
}
