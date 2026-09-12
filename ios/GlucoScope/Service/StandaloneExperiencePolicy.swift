import Foundation

struct StandaloneObservedSample: Equatable {
    let id: UUID
    let sessionID: UUID
    let sampleDate: Date
    let receivedAt: Date
    let createdAt: Date
    let mmol: Double
    let live: Bool
    let history: Bool
}

enum StandaloneSetupPolicy {
    static let timeout: TimeInterval = 300

    static func qualifies(_ sample: StandaloneObservedSample, sessionID: UUID, startedAt: Date,
                          now: Date, staleAfter: TimeInterval, standalone: Bool) -> Bool {
        standalone && sample.sessionID == sessionID && sample.live && !sample.history
            && sample.createdAt >= startedAt && sample.receivedAt >= startedAt
            && sample.sampleDate >= startedAt.addingTimeInterval(-90)
            && sample.sampleDate <= now.addingTimeInterval(30)
            && now.timeIntervalSince(sample.sampleDate) < staleAfter
    }

    static func hasTimedOut(startedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(startedAt) >= timeout
    }

    static func allowsRetry(outcome: String?, startedAt: Date?, keepTrying: Bool, now: Date) -> Bool {
        let timedOut = outcome == "timedOut" || (outcome == "waiting" && startedAt.map { hasTimedOut(startedAt: $0, now: now) } == true)
        return !timedOut || keepTrying
    }
}

struct StandaloneStatisticResult {
    let sampleCount: Int
    let daysWithData: Int
    let coveredSeconds: TimeInterval
    let belowSeconds: TimeInterval
    let inRangeSeconds: TimeInterval
    let aboveSeconds: TimeInterval
    let veryHighSeconds: TimeInterval
    let average: Double?
    let coefficientOfVariation: Double?

    func percentage(_ duration: TimeInterval) -> Double? {
        coveredSeconds > 0 ? duration / coveredSeconds * 100 : nil
    }
}

enum StandaloneStatistics {
    static let defaultWindowDays = 14

    static func windowStart(days: Int? = defaultWindowDays, now: Date, calendar: Calendar = .current) -> Date {
        guard let days else { return calendar.startOfDay(for: now) }
        return calendar.date(byAdding: .day, value: -days, to: now) ?? now
    }

    static func canonical(_ readings: [StandaloneObservedSample]) -> [StandaloneObservedSample] {
        let valid = readings.filter { $0.mmol.isFinite && $0.mmol > 0 }
        let grouped = Dictionary(grouping: valid) { Int64(floor($0.sampleDate.timeIntervalSince1970 / 60)) }
        return grouped.values.compactMap { bucket in
            bucket.sorted {
                if $0.history != $1.history { return !$0.history }
                if $0.receivedAt != $1.receivedAt { return $0.receivedAt > $1.receivedAt }
                return $0.id.uuidString < $1.id.uuidString
            }.first
        }.sorted { $0.sampleDate < $1.sampleDate }
    }

    /// Each observation represents up to its preceding native sample interval: one
    /// minute for trend, fifteen for history. Clip at the previous observed sample
    /// and selected window; never count an unobserved gap or overlap twice.
    static func calculate(samples: [StandaloneObservedSample], start: Date, end: Date,
                          low: Double, high: Double, veryHigh: Double,
                          calendar: Calendar = .current) -> StandaloneStatisticResult {
        let source = canonical(samples).filter { $0.sampleDate >= start && $0.sampleDate <= end }
        var weighted: [(value: Double, seconds: Double)] = []
        var below = 0.0, inRange = 0.0, above = 0.0, upper = 0.0
        var previous: Date?
        for sample in source {
            let expected: TimeInterval = sample.history ? 900 : 60
            let intervalStart = max(start, previous ?? .distantPast, sample.sampleDate.addingTimeInterval(-expected))
            let duration = max(0, min(end, sample.sampleDate).timeIntervalSince(intervalStart))
            previous = sample.sampleDate
            guard duration > 0 else { continue }
            weighted.append((sample.mmol, duration))
            if sample.mmol < low { below += duration }
            else if sample.mmol <= high { inRange += duration }
            else if sample.mmol < veryHigh { above += duration }
            else { upper += duration }
        }
        let total = weighted.reduce(0) { $0 + $1.seconds }
        let mean = total > 0 ? weighted.reduce(0) { $0 + $1.value * $1.seconds } / total : nil
        let cv: Double?
        if let mean, mean > 0, weighted.count >= 2 {
            let variance = weighted.reduce(0) { $0 + pow($1.value - mean, 2) * $1.seconds } / total
            cv = sqrt(variance) / mean * 100
        } else { cv = nil }
        return .init(sampleCount: source.count,
                     daysWithData: Set(source.map { calendar.startOfDay(for: $0.sampleDate) }).count,
                     coveredSeconds: total, belowSeconds: below, inRangeSeconds: inRange,
                     aboveSeconds: above, veryHighSeconds: upper, average: mean, coefficientOfVariation: cv)
    }
}

#if !STANDALONE_POLICY_TESTS
extension StandaloneObservedSample {
    init(_ reading: StoredReadingSnapshot) {
        self.init(id: reading.id, sessionID: reading.sessionID, sampleDate: reading.sampleDate,
                  receivedAt: reading.receivedAt, createdAt: reading.createdAt,
                  mmol: Double(reading.glucoseMGDL) / 18.0182,
                  live: reading.primaryOrigin == .bleLive, history: reading.kind == .history15Minute)
    }
}

extension StandaloneSetupPolicy {
    static func qualifies(reading: StoredReadingSnapshot, sessionID: UUID, startedAt: Date,
                          now: Date, staleAfter: TimeInterval, standalone: Bool) -> Bool {
        qualifies(StandaloneObservedSample(reading), sessionID: sessionID, startedAt: startedAt,
                  now: now, staleAfter: staleAfter, standalone: standalone)
    }
}

extension StandaloneStatistics {
    static func calculate(readings: [StoredReadingSnapshot], start: Date, end: Date,
                          low: Double, high: Double, veryHigh: Double) -> StandaloneStatisticResult {
        calculate(samples: readings.map(StandaloneObservedSample.init), start: start, end: end,
                  low: low, high: high, veryHigh: veryHigh)
    }
}
#endif
