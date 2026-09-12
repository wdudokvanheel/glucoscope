import Foundation

@main
struct ExperiencePolicySmoke {
    static let now = Date(timeIntervalSince1970: 1_789_200_000)
    static let session = UUID()
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1
        precondition(condition(), message)
    }
    static func sample(minutes: Double, mmol: Double = 6, live: Bool = true, history: Bool = false,
                       sessionID: UUID = session, received: Double? = nil, created: Double? = nil) -> StandaloneObservedSample {
        .init(id: UUID(), sessionID: sessionID, sampleDate: now.addingTimeInterval(minutes * 60),
              receivedAt: now.addingTimeInterval((received ?? minutes) * 60),
              createdAt: now.addingTimeInterval((created ?? received ?? minutes) * 60),
              mmol: mmol, live: live, history: history)
    }
    static func main() {
        let attempt = now.addingTimeInterval(-60)
        func qualifies(_ sample: StandaloneObservedSample, active: Bool = true) -> Bool {
            StandaloneSetupPolicy.qualifies(sample, sessionID: session, startedAt: attempt,
                                            now: now, staleAfter: 300, standalone: active)
        }
        check(qualifies(sample(minutes: 0)), "fresh committed live reading verifies")
        check(!qualifies(sample(minutes: 0), active: false), "Viewer cannot verify")
        check(!qualifies(sample(minutes: 0, sessionID: UUID())), "other sensor cannot verify")
        check(!qualifies(sample(minutes: 0, live: false)), "NFC/backfill cannot verify")
        check(!qualifies(sample(minutes: 0, history: true)), "history kind cannot verify")
        check(!qualifies(sample(minutes: 0, created: -2)), "previously saved record cannot verify new attempt")
        check(!qualifies(sample(minutes: 0, received: -2)), "previously received sample cannot verify")
        check(qualifies(sample(minutes: -2, received: 0)), "one-minute sensor clock margin allowed")
        check(!qualifies(sample(minutes: -3, received: 0)), "sample before attempt tolerance excluded")
        check(!qualifies(sample(minutes: 1)), "future sample excluded")
        check(!StandaloneSetupPolicy.qualifies(sample(minutes: -5, received: 0), sessionID: session,
            startedAt: now.addingTimeInterval(-600), now: now, staleAfter: 300, standalone: true), "stale edge excluded")
        check(!StandaloneSetupPolicy.hasTimedOut(startedAt: now, now: now.addingTimeInterval(299)), "timeout not early")
        check(StandaloneSetupPolicy.hasTimedOut(startedAt: now, now: now.addingTimeInterval(300)), "timeout exact five minutes")
        check(StandaloneSetupPolicy.allowsRetry(outcome: "timedOut", startedAt: now, keepTrying: true, now: now), "timeout retry opt-in")
        check(!StandaloneSetupPolicy.allowsRetry(outcome: "timedOut", startedAt: now, keepTrying: false, now: now), "timeout retry opt-out")
        check(!StandaloneSetupPolicy.allowsRetry(outcome: "waiting", startedAt: now.addingTimeInterval(-301), keepTrying: false, now: now), "past-deadline restore cannot resume opt-out")
        check(StandaloneSetupPolicy.allowsRetry(outcome: "verified", startedAt: now.addingTimeInterval(-301), keepTrying: false, now: now), "established reconnection unaffected by setup-only opt-out")
        check(StandaloneSetupPolicy.allowsRetry(outcome: nil, startedAt: nil, keepTrying: false, now: now), "existing paired sensor without setup episode may reconnect")

        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        check(StandaloneStatistics.defaultWindowDays == 14, "initial statistics period")
        check(StandaloneStatistics.windowStart(now: now, calendar: calendar) == now.addingTimeInterval(-14 * 86400), "default 14-day boundary")
        check(StandaloneStatistics.windowStart(days: nil, now: now, calendar: calendar) == calendar.startOfDay(for: now), "Today uses calendar midnight")
        let trend = sample(minutes: -1, mmol: 6)
        let duplicate = sample(minutes: -1, mmol: 20, live: false, history: true, received: 0)
        check(StandaloneStatistics.canonical([duplicate, trend]).map(\.id) == [trend.id], "trend preferred to overlapping historical sample")
        let inputs = [sample(minutes: -4, mmol: 3), sample(minutes: -3, mmol: 6), sample(minutes: -2, mmol: 9), sample(minutes: -1, mmol: 12)]
        let result = StandaloneStatistics.calculate(samples: inputs, start: now.addingTimeInterval(-14 * 86400), end: now, low: 4, high: 7, veryHigh: 10, calendar: calendar)
        check(result.sampleCount == 4 && result.daysWithData == 1, "incomplete window reports one available day")
        check(result.coveredSeconds == 240, "four one-minute samples represent four observed minutes")
        check(result.percentage(result.inRangeSeconds) == 25 && result.percentage(result.belowSeconds) == 25, "TIR and below fractions")
        check(result.percentage(result.aboveSeconds) == 25 && result.percentage(result.veryHighSeconds) == 25, "above and very-high independent fractions")
        check(result.average == 7.5, "time-weighted average")
        check(abs((result.coefficientOfVariation ?? 0) - 44.72135955) < 0.00001, "time-weighted CV")
        let mixed = StandaloneStatistics.calculate(samples: [sample(minutes: -15, mmol: 12, history: true), sample(minutes: -1, mmol: 6)],
            start: now.addingTimeInterval(-3600), end: now, low: 4, high: 7, veryHigh: 10)
        check(mixed.coveredSeconds == 960, "mixed cadence receives 15 plus one minutes, not gap duration")
        check(mixed.percentage(mixed.inRangeSeconds) == 6.25, "mixed trend/history TIR is time-weighted, not 50 percent sample share")
        let empty = StandaloneStatistics.calculate(samples: [], start: now.addingTimeInterval(-3600), end: now, low: 4, high: 7, veryHigh: 10)
        check(empty.average == nil && empty.coefficientOfVariation == nil && empty.percentage(0) == nil, "empty metrics unavailable")
        let single = StandaloneStatistics.calculate(samples: [trend], start: now.addingTimeInterval(-3600), end: now, low: 4, high: 7, veryHigh: 10)
        check(single.average == 6 && single.coefficientOfVariation == nil, "one sample does not imply variability")
        let clipped = StandaloneStatistics.calculate(samples: [sample(minutes: 0, mmol: 6, history: true)],
            start: now.addingTimeInterval(-30), end: now, low: 4, high: 7, veryHigh: 10)
        check(clipped.coveredSeconds == 30, "coverage clipped to selected start")
        let future = StandaloneStatistics.calculate(samples: [sample(minutes: 1)], start: now.addingTimeInterval(-3600), end: now, low: 4, high: 7, veryHigh: 10)
        check(future.sampleCount == 0, "future observations excluded")
        print("Standalone setup/statistics: \(count) policy checks passed")
    }
}
