import Foundation

enum GlucoseAlarmKind: String, Codable, CaseIterable, Identifiable {
    case high, low, sustainedHigh, sustainedLow, missing
    var id: String { rawValue }
    var title: String {
        switch self {
        case .high: return "High glucose"
        case .low: return "Low glucose"
        case .sustainedHigh: return "High for a while"
        case .sustainedLow: return "Low for a while"
        case .missing: return "No new readings"
        }
    }
    var explanation: String {
        switch self {
        case .high: return "Notify when a current reading crosses above your threshold."
        case .low: return "Notify when a current reading crosses below your threshold."
        case .sustainedHigh: return "Notify after glucose stays high for your chosen duration."
        case .sustainedLow: return "Notify after glucose stays low for your chosen duration."
        case .missing: return "Notify when no fresh sensor reading arrives for your chosen duration."
        }
    }
    var isHigh: Bool { self == .high || self == .sustainedHigh }
    var isSustained: Bool { self == .sustainedHigh || self == .sustainedLow }
}

enum GlucoseAlarmSound: String, Codable, CaseIterable, Identifiable {
    case system, gentle, urgent, silent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "System sound"
        case .gentle: return "Gentle chime"
        case .urgent: return "Urgent pulse"
        case .silent: return "Silent"
        }
    }
    var filename: String? {
        switch self {
        case .gentle: return "glucoscope-gentle.wav"
        case .urgent: return "glucoscope-urgent.wav"
        default: return nil
        }
    }
}

struct AlarmGeneralSettings: Codable, Equatable {
    var sound: GlucoseAlarmSound = .system
    var overrideDoNotDisturb = false
    var snoozeMinutes = 5
    var stopRepeatingOnRecovery = true
}

struct AlarmTimeWindow: Codable, Equatable, Identifiable {
    var id = UUID()
    var startMinute = 9 * 60
    var endMinute = 17 * 60
    /// Calendar weekday numbers: Sunday = 1. Overnight windows belong to their start day.
    var weekdays: Set<Int> = Set(1...7)
    var everyDay = true

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let day = calendar.component(.weekday, from: date)
        let allowed = everyDay ? Set(1...7) : weekdays
        if startMinute == endMinute { return allowed.contains(day) }
        if startMinute < endMinute {
            return allowed.contains(day) && minute >= startMinute && minute < endMinute
        }
        if minute >= startMinute { return allowed.contains(day) }
        let previousDay = day == 1 ? 7 : day - 1
        return minute < endMinute && allowed.contains(previousDay)
    }
}

struct GlucoseAlarmRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var kind: GlucoseAlarmKind
    var enabled = true
    var thresholdMMOL: Double
    var durationMinutes = 20
    var missingMinutes = 10
    var recoveryMarginMMOL = 0.3
    var windows: [AlarmTimeWindow] = []
    var soundOverride: GlucoseAlarmSound?
    var dndOverride: Bool?
    var snoozeOverride: Int?
    var stopOnRecoveryOverride: Bool?
    var repeats = true
    /// Nil follows the resolved snooze interval, including later general-setting changes.
    var repeatMinutes: Int?

    init(kind: GlucoseAlarmKind, thresholdMMOL: Double) {
        self.name = kind.title
        self.kind = kind
        self.thresholdMMOL = thresholdMMOL
    }
    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        enabled && (windows.isEmpty || windows.contains { $0.contains(date, calendar: calendar) })
    }
    func snooze(_ general: AlarmGeneralSettings) -> Int { max(1, snoozeOverride ?? general.snoozeMinutes) }
    func interval(_ general: AlarmGeneralSettings) -> Int { max(1, repeatMinutes ?? snooze(general)) }
    func stopOnRecovery(_ general: AlarmGeneralSettings) -> Bool { stopOnRecoveryOverride ?? general.stopRepeatingOnRecovery }
}

struct AlarmConfiguration: Codable {
    var general = AlarmGeneralSettings()
    var rules: [GlucoseAlarmRule]
}

struct AlarmReading: Codable, Equatable {
    let sampleDate: Date
    let receivedAt: Date
    let mmol: Double
    let isCurrent: Bool
}

struct AlarmEpisode: Codable, Equatable {
    var qualifyingSince: Date?
    var conditionLatched = false
    var active = false
    var dismissed = false
    var nextNotification: Date?
    var manualSnooze = false
}

struct AlarmEmission: Equatable {
    let ruleID: UUID
    let date: Date
    let mmol: Double?
}

/// Pure temporal state machine. Only observed current samples establish glucose conditions.
/// Call evaluate on fresh commits and clock ticks; backfills never enter this engine.
struct StandaloneAlarmEngine: Codable {
    private(set) var episodes: [UUID: AlarmEpisode] = [:]
    private(set) var latestReading: AlarmReading?
    private(set) var startedAt: Date?
    private(set) var standalone = false

    mutating func setStandalone(_ active: Bool, now: Date) {
        standalone = active
        episodes.removeAll()
        latestReading = nil
        startedAt = active ? now : nil
    }

    mutating func ingest(_ reading: AlarmReading, rules: [GlucoseAlarmRule], general: AlarmGeneralSettings,
                         staleAfter: TimeInterval, now: Date) {
        guard standalone, reading.isCurrent, reading.mmol.isFinite,
              reading.sampleDate <= now.addingTimeInterval(30),
              now.timeIntervalSince(reading.sampleDate) < staleAfter,
              now.timeIntervalSince(reading.receivedAt) < staleAfter,
              latestReading == nil || reading.sampleDate > latestReading!.sampleDate else { return }
        let gap = latestReading.map { reading.sampleDate.timeIntervalSince($0.sampleDate) >= staleAfter } ?? false
        latestReading = reading
        for rule in rules {
            var episode = episodes[rule.id] ?? AlarmEpisode()
            if gap { episode.qualifyingSince = nil; episode.conditionLatched = false }
            let recovered = rule.kind == .missing || (rule.kind.isHigh
                ? reading.mmol <= rule.thresholdMMOL - rule.recoveryMarginMMOL
                : reading.mmol >= rule.thresholdMMOL + rule.recoveryMarginMMOL)
            if recovered {
                episode.qualifyingSince = nil
                episode.conditionLatched = false
                episode.dismissed = false
                if rule.stopOnRecovery(general) {
                    episode.active = false
                    episode.nextNotification = nil
                    episode.manualSnooze = false
                }
            } else if rule.kind != .missing {
                let crosses = rule.kind.isHigh ? reading.mmol > rule.thresholdMMOL : reading.mmol < rule.thresholdMMOL
                if crosses || episode.conditionLatched {
                    episode.conditionLatched = true
                    if episode.qualifyingSince == nil { episode.qualifyingSince = reading.sampleDate }
                }
            }
            episodes[rule.id] = episode
        }
    }

    mutating func evaluate(rules: [GlucoseAlarmRule], general: AlarmGeneralSettings,
                           staleAfter: TimeInterval, now: Date, calendar: Calendar = .current) -> [AlarmEmission] {
        guard standalone else { return [] }
        episodes = episodes.filter { id, _ in rules.contains { $0.id == id && $0.enabled } }
        let fresh = latestReading.map { now.timeIntervalSince($0.sampleDate) < staleAfter } ?? false
        var emissions: [AlarmEmission] = []
        for rule in rules where rule.enabled {
            var episode = episodes[rule.id] ?? AlarmEpisode()
            if !fresh && rule.kind != .missing {
                episode.qualifyingSince = nil
                episode.conditionLatched = false
            }
            let condition: Bool
            if rule.kind == .missing {
                let reference = latestReading?.sampleDate ?? startedAt ?? now
                condition = now.timeIntervalSince(reference) >= Double(rule.missingMinutes * 60)
                episode.conditionLatched = condition
            } else {
                let duration = rule.kind.isSustained ? Double(rule.durationMinutes * 60) : 0
                condition = fresh && episode.conditionLatched && episode.qualifyingSince.map { now.timeIntervalSince($0) >= duration } == true
            }
            guard rule.isActive(at: now, calendar: calendar) else {
                episode.active = false
                episode.nextNotification = nil
                episode.manualSnooze = false
                episodes[rule.id] = episode
                continue
            }
            if episode.dismissed { episodes[rule.id] = episode; continue }
            var notify = false
            if !episode.active && condition {
                episode.active = true
                notify = true
            } else if episode.active, let due = episode.nextNotification, now >= due {
                // Manual snooze ALWAYS requires a continuing condition, even when automatic
                // repeats have explicitly been configured to continue after recovery.
                let mayRepeat = condition || (!episode.manualSnooze && !rule.stopOnRecovery(general) && (fresh || rule.kind == .missing))
                notify = mayRepeat
                episode.nextNotification = nil
                episode.manualSnooze = false
                if !mayRepeat && !condition { episode.active = false }
            }
            if notify {
                emissions.append(AlarmEmission(ruleID: rule.id, date: now, mmol: rule.kind == .missing ? nil : latestReading?.mmol))
                episode.nextNotification = rule.repeats ? now.addingTimeInterval(Double(rule.interval(general) * 60)) : nil
            }
            episodes[rule.id] = episode
        }
        return emissions
    }

    mutating func dismiss(_ id: UUID) {
        guard var episode = episodes[id] else { return }
        episode.dismissed = true
        episode.active = false
        episode.nextNotification = nil
        episode.manualSnooze = false
        episodes[id] = episode
    }

    mutating func snooze(_ rule: GlucoseAlarmRule, general: AlarmGeneralSettings, now: Date) {
        guard var episode = episodes[rule.id], episode.active else { return }
        episode.nextNotification = now.addingTimeInterval(Double(rule.snooze(general) * 60))
        episode.manualSnooze = true
        episodes[rule.id] = episode
    }

    mutating func resetRule(_ id: UUID) { episodes.removeValue(forKey: id) }
    mutating func replaceEpisode(_ id: UUID, with episode: AlarmEpisode?) { episodes[id] = episode }

    /// A bounded forecast with no invented sensor samples. Glucose alarms can only be
    /// forecast while the already observed sample remains fresh. Missing-reading alarms
    /// remain valid until a fresh sample cancels their pending requests.
    func projectedNotifications(rules: [GlucoseAlarmRule], general: AlarmGeneralSettings,
                                staleAfter: TimeInterval, now: Date, calendar: Calendar = .current,
                                limit: Int = 48) -> [AlarmEmission] {
        guard standalone else { return [] }
        var result: [AlarmEmission] = []
        for rule in rules where rule.enabled {
            var projection = self
            var cursor = now
            for _ in 0..<4 {
                let episode = projection.episodes[rule.id] ?? AlarmEpisode()
                if episode.dismissed { break }
                let ready: Date?
                if episode.active { ready = episode.nextNotification }
                else if rule.kind == .missing {
                    ready = (projection.latestReading?.sampleDate ?? projection.startedAt ?? now)
                        .addingTimeInterval(Double(rule.missingMinutes * 60))
                } else {
                    ready = episode.conditionLatched ? episode.qualifyingSince?.addingTimeInterval(
                        Double(rule.kind.isSustained ? rule.durationMinutes * 60 : 0)) : nil
                }
                guard let ready else { break }
                var due = max(ready, cursor.addingTimeInterval(1))
                if !rule.isActive(at: due, calendar: calendar) {
                    // Schedules use wall-clock minutes, including DST transitions. Look far
                    // enough ahead to include the next occurrence of any selected weekday.
                    due = Date(timeIntervalSince1970: ceil(due.timeIntervalSince1970 / 60) * 60)
                    let deadline = due.addingTimeInterval(8 * 86400)
                    while due < deadline && !rule.isActive(at: due, calendar: calendar) {
                        due = due.addingTimeInterval(60)
                    }
                    if due >= deadline { break }
                }
                // The real engine is the single source of truth for margin, snooze,
                // recovery opt-outs, freshness, and sustained qualification.
                let emissions = projection.evaluate(rules: [rule], general: general, staleAfter: staleAfter,
                                                     now: due, calendar: calendar)
                guard let emission = emissions.first else { break }
                result.append(emission)
                cursor = due
            }
        }
        return Array(result.sorted { $0.date == $1.date ? $0.ruleID.uuidString < $1.ruleID.uuidString : $0.date < $1.date }.prefix(max(0, limit)))
    }
}
