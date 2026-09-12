import Foundation

@main
struct AlarmEngineSmoke {
    static var checks = 0
    static let origin = Date(timeIntervalSince1970: 1_783_329_600)
    static let general = AlarmGeneralSettings()

    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fatalError("Alarm check failed: \(message)") }
    }
    static func date(_ minutes: Double) -> Date { origin.addingTimeInterval(minutes * 60) }
    static func sample(_ minute: Double, _ value: Double, live: Bool = true, received: Double? = nil) -> AlarmReading {
        AlarmReading(sampleDate: date(minute), receivedAt: date(received ?? minute), mmol: value, isCurrent: live)
    }
    static func ingest(_ engine: inout StandaloneAlarmEngine, _ rule: GlucoseAlarmRule, _ minute: Double, _ value: Double,
                       settings: AlarmGeneralSettings = general, stale: Double = 300) {
        engine.ingest(sample(minute, value), rules: [rule], general: settings, staleAfter: stale, now: date(minute))
    }
    static func tick(_ engine: inout StandaloneAlarmEngine, _ rule: GlucoseAlarmRule, _ minute: Double,
                     settings: AlarmGeneralSettings = general, stale: Double = 300, calendar: Calendar = .current) -> [AlarmEmission] {
        engine.evaluate(rules: [rule], general: settings, staleAfter: stale, now: date(minute), calendar: calendar)
    }
    static func started() -> StandaloneAlarmEngine {
        var engine = StandaloneAlarmEngine(); engine.setStandalone(true, now: origin); return engine
    }
    static func main() throws {
        immediateAndEpisodes()
        sustainedAndStaleness()
        schedules()
        missingAndMode()
        historiesAndOverrides()
        try persistence()
        print("Alarm engine: \(checks) temporal checks passed")
    }

    static func immediateAndEpisodes() {
        let high = GlucoseAlarmRule(kind: .high, thresholdMMOL: 10)
        var e = started()
        ingest(&e, high, 0, 11)
        require(tick(&e, high, 0).count == 1, "starter high fires immediately")
        for minute in 1...4 { ingest(&e, high, Double(minute), 11); require(tick(&e, high, Double(minute)).isEmpty, "automatic snooze is quiet") }
        ingest(&e, high, 5, 11)
        require(tick(&e, high, 5).count == 1, "default repeat at five minutes")
        e.dismiss(high.id)
        ingest(&e, high, 6, 9.9)
        require(tick(&e, high, 6).isEmpty, "dismissed stays quiet inside hysteresis margin")
        ingest(&e, high, 7, 11)
        require(tick(&e, high, 7).isEmpty, "crossing without recovery does not rearm")
        ingest(&e, high, 8, 9.6)
        require(tick(&e, high, 8).isEmpty, "recovery does not fire")
        ingest(&e, high, 9, 11)
        require(tick(&e, high, 9).count == 1, "recovery followed by crossing rearms")
        e.snooze(high, general: general, now: date(9))
        for minute in 10...13 { ingest(&e, high, Double(minute), 11); _ = tick(&e, high, Double(minute)) }
        ingest(&e, high, 14, 9.8)
        require(tick(&e, high, 14).count == 1, "manual snooze expires with margin condition still active")
        ingest(&e, high, 15, 9.6)
        require(tick(&e, high, 15).isEmpty && e.episodes[high.id]?.active == false, "recovery stops episode by default")

        var optOut = general; optOut.stopRepeatingOnRecovery = false
        e = started(); ingest(&e, high, 0, 11, settings: optOut); _ = tick(&e, high, 0, settings: optOut)
        for minute in 1...5 { ingest(&e, high, Double(minute), 8, settings: optOut) }
        require(tick(&e, high, 5, settings: optOut).count == 1, "automatic opt-out repeats after recovery")
        e.snooze(high, general: optOut, now: date(5))
        for minute in 6...10 { ingest(&e, high, Double(minute), 8, settings: optOut) }
        require(tick(&e, high, 10, settings: optOut).isEmpty, "manual snooze checks condition despite recovery opt-out")

        var single = high; single.repeats = false
        e = started(); ingest(&e, single, 0, 11); _ = tick(&e, single, 0)
        for minute in 1...8 { ingest(&e, single, Double(minute), 11); require(tick(&e, single, Double(minute)).isEmpty, "single-fire never repeats automatically") }
        e.snooze(single, general: general, now: date(8))
        for minute in 9...13 { ingest(&e, single, Double(minute), 11) }
        require(tick(&e, single, 13).count == 1, "manual snooze can remind a single-fire episode")
    }

    static func sustainedAndStaleness() {
        var rule = GlucoseAlarmRule(kind: .sustainedHigh, thresholdMMOL: 10); rule.durationMinutes = 3
        var e = started()
        ingest(&e, rule, 0, 11); require(tick(&e, rule, 0).isEmpty, "sustained does not fire immediately")
        ingest(&e, rule, 1, 9.9); require(tick(&e, rule, 1).isEmpty, "margin keeps counting")
        ingest(&e, rule, 2, 10.1); require(tick(&e, rule, 2).isEmpty, "duration not yet met")
        ingest(&e, rule, 3, 9.8); require(tick(&e, rule, 3).count == 1, "sustained duration counts through margin")
        e = started(); ingest(&e, rule, 0, 11); _ = tick(&e, rule, 0)
        ingest(&e, rule, 1, 9.6); _ = tick(&e, rule, 1)
        ingest(&e, rule, 2, 11); _ = tick(&e, rule, 2)
        ingest(&e, rule, 3, 11); require(tick(&e, rule, 3).isEmpty, "recovery resets duration")
        ingest(&e, rule, 4, 11); _ = tick(&e, rule, 4)
        ingest(&e, rule, 5, 11); require(tick(&e, rule, 5).count == 1, "fresh duration after recovery")
        e = started(); ingest(&e, rule, 0, 11)
        require(tick(&e, rule, 5).isEmpty && e.episodes[rule.id]?.qualifyingSince == nil, "stale boundary resets sustained timer")
        ingest(&e, rule, 6, 11); require(tick(&e, rule, 6).isEmpty, "new sample after stale starts new duration")
        ingest(&e, rule, 7, 11); _ = tick(&e, rule, 7)
        ingest(&e, rule, 8, 11); _ = tick(&e, rule, 8)
        ingest(&e, rule, 9, 11); require(tick(&e, rule, 9).count == 1, "post-stale sustained qualifies")
        e = started(); ingest(&e, rule, 0, 11)
        ingest(&e, rule, 6, 11); require(tick(&e, rule, 6).isEmpty, "stale gap detected even with no clock tick during suspension")
        var low = GlucoseAlarmRule(kind: .sustainedLow, thresholdMMOL: 4); low.durationMinutes = 2
        e = started(); ingest(&e, low, 0, 3.5); _ = tick(&e, low, 0)
        ingest(&e, low, 1, 4.2); _ = tick(&e, low, 1)
        ingest(&e, low, 2, 3.9); require(tick(&e, low, 2).count == 1, "low hysteresis is symmetric")
        ingest(&e, low, 3, 4.4); require(tick(&e, low, 3).isEmpty && e.episodes[low.id]?.active == false, "low recovery boundary")
    }

    static func schedules() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = calendar.startOfDay(for: origin)
        func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
            calendar.date(byAdding: .day, value: dayOffset, to: day)!.addingTimeInterval(Double((hour * 60 + minute) * 60))
        }
        let weekday = calendar.component(.weekday, from: day)
        var overnight = AlarmTimeWindow(); overnight.startMinute = 22 * 60; overnight.endMinute = 6 * 60
        overnight.everyDay = false; overnight.weekdays = [weekday]
        require(overnight.contains(at(23), calendar: calendar), "overnight starts on selected day")
        require(overnight.contains(at(5, dayOffset: 1), calendar: calendar), "overnight continues into following day")
        require(!overnight.contains(at(6, dayOffset: 1), calendar: calendar), "end time is exclusive")
        require(!overnight.contains(at(23, dayOffset: 1), calendar: calendar), "unselected start day remains off")
        overnight.weekdays = []; require(!overnight.contains(at(23), calendar: calendar), "no selected weekdays never activates")
        var work = AlarmTimeWindow(); work.startMinute = 9 * 60; work.endMinute = 17 * 60
        var rule = GlucoseAlarmRule(kind: .sustainedHigh, thresholdMMOL: 10); rule.durationMinutes = 20; rule.windows = [work]
        var e = StandaloneAlarmEngine(); e.setStandalone(true, now: at(8))
        for minute in 40...59 {
            let date = at(8, minute)
            e.ingest(AlarmReading(sampleDate: date, receivedAt: date, mmol: 11, isCurrent: true), rules: [rule], general: general, staleAfter: 300, now: date)
            require(e.evaluate(rules: [rule], general: general, staleAfter: 300, now: date, calendar: calendar).isEmpty, "no alarm before active window")
        }
        require(e.evaluate(rules: [rule], general: general, staleAfter: 300, now: at(9), calendar: calendar).count == 1, "window opening credits current pre-window sustained samples")
        var optOut = general; optOut.stopRepeatingOnRecovery = false
        _ = e.evaluate(rules: [rule], general: optOut, staleAfter: 300, now: at(17), calendar: calendar)
        require(e.episodes[rule.id]?.active == false && e.episodes[rule.id]?.nextNotification == nil, "window close stops all repeat modes")
        rule.windows.append(AlarmTimeWindow(startMinute: 19 * 60, endMinute: 21 * 60))
        require(rule.isActive(at: at(20), calendar: calendar) && !rule.isActive(at: at(18), calendar: calendar), "multiple windows combine with OR")
        var allDay = work; allDay.startMinute = 0; allDay.endMinute = 0
        require(allDay.contains(at(3), calendar: calendar), "equal endpoints are full day")
    }

    static func missingAndMode() {
        var missing = GlucoseAlarmRule(kind: .missing, thresholdMMOL: 0); missing.missingMinutes = 10
        var e = started()
        require(tick(&e, missing, 9).isEmpty, "missing has own delay")
        require(tick(&e, missing, 10).count == 1, "missing works before any reading")
        e.dismiss(missing.id)
        require(tick(&e, missing, 20).isEmpty, "dismissed missing episode remains quiet")
        ingest(&e, missing, 21, 6); _ = tick(&e, missing, 21)
        require(tick(&e, missing, 30).isEmpty, "fresh live reading rearms and restarts missing delay")
        require(tick(&e, missing, 31).count == 1, "next missing episode fires")
        e.setStandalone(false, now: date(32))
        require(tick(&e, missing, 40).isEmpty && e.episodes.isEmpty, "Viewer clears all episodes and timers")
        ingest(&e, missing, 41, 6)
        require(e.latestReading == nil, "Viewer cannot ingest alarm data")
        e.setStandalone(true, now: date(50))
        require(tick(&e, missing, 59).isEmpty, "return to standalone starts a new no-reading observation window")
    }

    static func historiesAndOverrides() {
        var rule = GlucoseAlarmRule(kind: .high, thresholdMMOL: 10)
        var e = started()
        e.ingest(sample(0, 20, live: false), rules: [rule], general: general, staleAfter: 300, now: date(0))
        require(tick(&e, rule, 0).isEmpty, "historical observation never triggers")
        e.ingest(sample(0, 20, received: 10), rules: [rule], general: general, staleAfter: 300, now: date(10))
        require(tick(&e, rule, 10).isEmpty, "late sample cannot appear fresh due to recent receipt")
        ingest(&e, rule, 10, 6)
        e.ingest(sample(9, 20, received: 10), rules: [rule], general: general, staleAfter: 300, now: date(10))
        require(tick(&e, rule, 10).isEmpty && e.latestReading?.mmol == 6, "out-of-order live data cannot replace latest")
        e.ingest(sample(12, 20), rules: [rule], general: general, staleAfter: 300, now: date(10))
        require(tick(&e, rule, 10).isEmpty, "future timestamps excluded")
        var settings = general; settings.snoozeMinutes = 8
        require(rule.snooze(settings) == 8 && rule.interval(settings) == 8, "starter repeats inherit general snooze")
        rule.snoozeOverride = 3
        require(rule.snooze(settings) == 3 && rule.interval(settings) == 3, "rule snooze override controls automatic repeat")
        rule.repeatMinutes = 7
        require(rule.interval(settings) == 7, "explicit repeat override")
        rule.stopOnRecoveryOverride = false
        require(!rule.stopOnRecovery(settings), "recovery override resolves")
        let low = GlucoseAlarmRule(kind: .low, thresholdMMOL: 12)
        e = started()
        e.ingest(sample(0, 11), rules: [rule, low], general: general, staleAfter: 300, now: date(0))
        require(e.evaluate(rules: [rule, low], general: general, staleAfter: 300, now: date(0)).count == 2, "independent simultaneous rules")
        e.dismiss(rule.id)
        require(e.episodes[low.id]?.active == true, "dismiss leaves other alarms active")
        var disabled = low; disabled.enabled = false
        _ = e.evaluate(rules: [rule, disabled], general: general, staleAfter: 300, now: date(1))
        require(e.episodes[low.id] == nil, "disable removes pending episode")
    }

    static func persistence() throws {
        let rule = GlucoseAlarmRule(kind: .high, thresholdMMOL: 10)
        var e = started(); ingest(&e, rule, 0, 11); _ = tick(&e, rule, 0); e.dismiss(rule.id)
        var restored = try JSONDecoder().decode(StandaloneAlarmEngine.self, from: JSONEncoder().encode(e))
        ingest(&restored, rule, 1, 11)
        require(tick(&restored, rule, 1).isEmpty && restored.episodes[rule.id]?.dismissed == true, "relaunch retains dismissed episode")
    }
}
