import XCTest
@testable import BreakScrollCore

final class InterventionEngineTests: XCTestCase {
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }()

    /// 2026-10-05 (Monday) at the given time.
    private func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0, day: Int = 5) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    private let fixedChallenge = MathChallenge(difficulty: .easy, prompt: "14 + 9", answer: 23)

    private func makeEngine(_ rule: InterventionRule) -> InterventionEngine {
        let challenge = fixedChallenge
        return InterventionEngine(rule: rule, calendar: calendar) { difficulty in
            difficulty == .none ? nil
                : MathChallenge(difficulty: difficulty, prompt: challenge.prompt, answer: challenge.answer)
        }
    }

    private func rule(
        interval: TimeInterval = 120,
        pause: TimeInterval = 10,
        difficulty: ChallengeDifficulty = .easy,
        escalation: EscalationPolicy = .none,
        schedule: WeeklySchedule = .daytime,
        max: Int? = nil,
        dailyLimit: TimeInterval? = nil
    ) -> InterventionRule {
        InterventionRule(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Social", usageInterval: interval, pauseDuration: pause, challengeDifficulty: difficulty,
            escalationPolicy: escalation, activeSchedule: schedule, maxContinuations: max, dailyLimit: dailyLimit
        )
    }

    private func kinds(_ effects: [InterventionEffect]) -> [InterventionRecord.Kind] {
        effects.compactMap { if case .record(let r) = $0 { return r.kind } else { return nil } }
    }

    /// Starts monitoring and confirms the arm, returning a session in `.monitoring`.
    private func started(_ engine: InterventionEngine, now: Date) -> InterventionSession {
        var session = InterventionSession(ruleID: engine.rule.id)
        let effects = engine.handle(.start, session: &session, now: now)
        XCTAssertEqual(effects, [.arm(generation: 1, threshold: engine.rule.usageInterval)])
        engine.handle(.armSucceeded(generation: 1), session: &session, now: now)
        XCTAssertEqual(session.phase, .monitoring)
        return session
    }

    // MARK: The MVP loop

    func testRepeatedIntervalLoop() {
        let engine = makeEngine(rule())
        var session = started(engine, now: at(9))

        for cycle in 1...3 {
            let generation = session.armedGeneration
            var effects = engine.handle(.thresholdReached(generation: generation), session: &session, now: at(9, cycle * 5))
            XCTAssertEqual(session.phase, .shielded(since: at(9, cycle * 5)))
            XCTAssertTrue(effects.contains(.applyShield))
            XCTAssertEqual(kinds(effects), [.intervention])

            effects = engine.handle(.chooseContinue, session: &session, now: at(9, cycle * 5, 5))
            XCTAssertEqual(kinds(effects), [.continued])
            XCTAssertEqual(session.phase, .pausing(until: at(9, cycle * 5, 15), difficulty: .easy))

            // Too early: nothing happens.
            XCTAssertEqual(engine.handle(.pauseElapsed, session: &session, now: at(9, cycle * 5, 14)), [])
            engine.handle(.pauseElapsed, session: &session, now: at(9, cycle * 5, 15))
            guard case .challenge = session.phase else { return XCTFail("expected challenge, got \(session.phase)") }

            effects = engine.handle(.submitAnswer("23"), session: &session, now: at(9, cycle * 5, 20))
            XCTAssertEqual(kinds(effects), [.challengeSolved])
            XCTAssertTrue(effects.contains(.arm(generation: generation + 1, threshold: 120)))
            XCTAssertFalse(effects.contains(.removeShield), "shield must stay up until re-arm succeeds")
            XCTAssertEqual(session.phase, .arming(.continuation))
            XCTAssertTrue(session.phase.isShielded)

            effects = engine.handle(.armSucceeded(generation: generation + 1), session: &session, now: at(9, cycle * 5, 21))
            XCTAssertEqual(effects.first, .removeShield)
            XCTAssertEqual(kinds(effects), [.unlocked])
            XCTAssertEqual(session.phase, .monitoring)
            XCTAssertEqual(session.continuationsToday, cycle)
        }
    }

    func testWrongAnswersKeepTheShieldAndCountAttempts() {
        let engine = makeEngine(rule(pause: 0))
        var session = started(engine, now: at(9))
        engine.handle(.thresholdReached(generation: 1), session: &session, now: at(9, 2))
        engine.handle(.chooseContinue, session: &session, now: at(9, 3))

        engine.handle(.submitAnswer("22"), session: &session, now: at(9, 3, 5))
        engine.handle(.submitAnswer(""), session: &session, now: at(9, 3, 6))
        guard case .challenge(_, let failed) = session.phase else { return XCTFail() }
        XCTAssertEqual(failed, 2)
        XCTAssertTrue(session.phase.isShielded)

        let effects = engine.handle(.submitAnswer("23"), session: &session, now: at(9, 3, 9))
        guard case .record(let record) = effects.first else { return XCTFail() }
        XCTAssertEqual(record.attempts, 3)
    }

    func testProblemIsReplacedAfterRepeatedFailures() {
        var count = 0
        let engine = InterventionEngine(rule: rule(pause: 0), calendar: calendar) { difficulty in
            count += 1
            return MathChallenge(difficulty: difficulty, prompt: "p\(count)", answer: 1000 + count)
        }
        var session = started(engine, now: at(9))
        engine.handle(.thresholdReached(generation: 1), session: &session, now: at(9, 2))
        engine.handle(.chooseContinue, session: &session, now: at(9, 3))
        guard case .challenge(let first, _) = session.phase else { return XCTFail() }
        for _ in 0..<InterventionEngine.attemptsBeforeNewProblem {
            engine.handle(.submitAnswer("0"), session: &session, now: at(9, 4))
        }
        guard case .challenge(let second, let failed) = session.phase else { return XCTFail() }
        XCTAssertNotEqual(first.prompt, second.prompt)
        XCTAssertEqual(failed, 3)
    }

    func testNoChallengeMeansPauseAloneUnlocks() {
        let engine = makeEngine(rule(pause: 30, difficulty: .none))
        var session = started(engine, now: at(9))
        engine.handle(.thresholdReached(generation: 1), session: &session, now: at(9, 2))
        engine.handle(.chooseContinue, session: &session, now: at(9, 3))
        let effects = engine.handle(.pauseElapsed, session: &session, now: at(9, 3, 30))
        XCTAssertEqual(effects, [.arm(generation: 2, threshold: 120)])
    }

    // MARK: Stop vs continue

    func testImDoneKeepsShieldAndCanContinueLater() {
        let engine = makeEngine(rule())
        var session = started(engine, now: at(9))
        engine.handle(.thresholdReached(generation: 1), session: &session, now: at(9, 2))
        let effects = engine.handle(.chooseDone, session: &session, now: at(9, 3))
        XCTAssertEqual(kinds(effects), [.stopped])
        XCTAssertFalse(effects.contains(.removeShield))
        XCTAssertEqual(session.phase, .stopped(at: at(9, 3)))

        // A second "I'm Done" isn't double-counted.
        XCTAssertEqual(engine.handle(.chooseDone, session: &session, now: at(9, 4)), [])

        engine.handle(.chooseContinue, session: &session, now: at(10))
        guard case .pausing = session.phase else { return XCTFail() }
    }

    func testGivingUpDuringChallengeCountsAsStopped() {
        let engine = makeEngine(rule(pause: 0))
        var session = started(engine, now: at(9))
        engine.handle(.thresholdReached(generation: 1), session: &session, now: at(9, 2))
        engine.handle(.chooseContinue, session: &session, now: at(9, 3))
        XCTAssertEqual(kinds(engine.handle(.chooseDone, session: &session, now: at(9, 4))), [.stopped])
    }

    // MARK: Stale and duplicate callbacks

    func testStaleAndDuplicateThresholdsAreIgnored() {
        let engine = makeEngine(rule(pause: 0))
        var session = started(engine, now: at(9))
        engine.handle(.thresholdReached(generation: 1), session: &session, now: at(9, 2))
        // Duplicate while shielded.
        XCTAssertEqual(engine.handle(.thresholdReached(generation: 1), session: &session, now: at(9, 2, 1)), [])

        engine.handle(.chooseContinue, session: &session, now: at(9, 3))
        engine.handle(.submitAnswer("23"), session: &session, now: at(9, 4))
        engine.handle(.armSucceeded(generation: 2), session: &session, now: at(9, 4))

        // Late callback from the previous generation.
        XCTAssertEqual(engine.handle(.thresholdReached(generation: 1), session: &session, now: at(9, 5)), [])
        XCTAssertEqual(session.phase, .monitoring)
        // Late arm confirmation from an old generation.
        XCTAssertEqual(engine.handle(.armSucceeded(generation: 1), session: &session, now: at(9, 5)), [])
    }

    func testThresholdOnInactiveDayIsIgnored() {
        let weekdaysOnly = WeeklySchedule(activeDays: Weekday.weekdays, start: .startOfDay, end: .endOfDay)
        let engine = makeEngine(rule(schedule: weekdaysOnly))
        var session = started(engine, now: at(9, day: 10)) // Saturday
        XCTAssertEqual(engine.handle(.thresholdReached(generation: 1), session: &session, now: at(9, 5, day: 10)), [])
        XCTAssertEqual(session.phase, .monitoring)
    }

    // MARK: Re-arm failures (never fail open)

    func testRearmFailureKeepsShieldAndRetries() {
        let engine = makeEngine(rule(pause: 0))
        var session = started(engine, now: at(9))
        engine.handle(.thresholdReached(generation: 1), session: &session, now: at(9, 2))
        engine.handle(.chooseContinue, session: &session, now: at(9, 3))
        engine.handle(.submitAnswer("23"), session: &session, now: at(9, 4))

        let failed = engine.handle(.armFailed(generation: 2), session: &session, now: at(9, 4))
        XCTAssertEqual(kinds(failed), [.rearmFailed])
        XCTAssertFalse(failed.contains(.removeShield))
        XCTAssertEqual(session.phase, .rearmFailed(.continuation))
        XCTAssertTrue(session.phase.isShielded)

        XCTAssertEqual(engine.handle(.retryArm, session: &session, now: at(9, 5)), [.arm(generation: 3, threshold: 120)])
        let ok = engine.handle(.armSucceeded(generation: 3), session: &session, now: at(9, 5))
        XCTAssertTrue(ok.contains(.removeShield))
        XCTAssertEqual(session.continuationsToday, 1)
    }

    func testInitialArmFailureReturnsToInactive() {
        let engine = makeEngine(rule())
        var session = InterventionSession(ruleID: engine.rule.id)
        engine.handle(.start, session: &session, now: at(9))
        XCTAssertEqual(engine.handle(.armFailed(generation: 1), session: &session, now: at(9)), [])
        XCTAssertEqual(session.phase, .inactive)
    }

    // MARK: Active hours and our own re-arm side effects

    func testIntervalEndedDuringRearmIsIgnoredInsideActiveHours() {
        let engine = makeEngine(rule(pause: 0))
        var session = started(engine, now: at(9))
        engine.handle(.thresholdReached(generation: 1), session: &session, now: at(9, 2))
        engine.handle(.chooseContinue, session: &session, now: at(9, 3))
        engine.handle(.submitAnswer("23"), session: &session, now: at(9, 4))
        // startMonitoring overwrites the activity, which can fire intervalDidEnd/Start.
        XCTAssertEqual(engine.handle(.intervalEnded, session: &session, now: at(9, 4)), [])
        XCTAssertEqual(engine.handle(.intervalStarted, session: &session, now: at(9, 4)), [])
        XCTAssertEqual(session.phase, .arming(.continuation))
        XCTAssertEqual(session.continuationsToday, 0, "re-arm must not reset the day's count")
    }

    func testLeavingActiveHoursLiftsShieldAndResumesNextMorning() {
        let engine = makeEngine(rule())
        var session = started(engine, now: at(21))
        engine.handle(.thresholdReached(generation: 1), session: &session, now: at(22))
        XCTAssertEqual(engine.handle(.intervalEnded, session: &session, now: at(22, 30)), [.removeShield])
        XCTAssertEqual(session.phase, .outsideActiveHours)

        engine.handle(.intervalStarted, session: &session, now: at(7, day: 6))
        XCTAssertEqual(session.phase, .monitoring)
        // Same generation is still registered with the system for the new interval.
        let effects = engine.handle(.thresholdReached(generation: 1), session: &session, now: at(8, day: 6))
        XCTAssertTrue(effects.contains(.applyShield))
    }

    // MARK: Day rollover, limits, escalation

    func testMidnightRolloverResetsContinuationCount() {
        let engine = makeEngine(rule(pause: 0, schedule: .always, max: 1))
        var session = started(engine, now: at(23))
        engine.handle(.thresholdReached(generation: 1), session: &session, now: at(23, 10))
        engine.handle(.chooseContinue, session: &session, now: at(23, 11))
        engine.handle(.submitAnswer("23"), session: &session, now: at(23, 12))
        engine.handle(.armSucceeded(generation: 2), session: &session, now: at(23, 12))
        XCTAssertEqual(session.continuationsToday, 1)

        engine.handle(.thresholdReached(generation: 2), session: &session, now: at(23, 50))
        engine.handle(.chooseContinue, session: &session, now: at(23, 51))
        XCTAssertEqual(session.phase, .awaitingParent(reason: .maxContinuationsReached, since: at(23, 51)))

        // After midnight the count resets and local challenges apply again.
        engine.handle(.intervalStarted, session: &session, now: at(0, 1, day: 6))
        XCTAssertEqual(session.dayKey, "2026-10-06")
        XCTAssertEqual(session.continuationsToday, 0)
        XCTAssertEqual(session.phase, .shielded(since: at(0, 1, day: 6)))
        engine.handle(.chooseContinue, session: &session, now: at(0, 2, day: 6))
        guard case .challenge = session.phase else { return XCTFail("\(session.phase)") }
    }

    func testEscalationAcrossContinuations() {
        let engine = makeEngine(rule(escalation: .standard))
        var session = started(engine, now: at(9))
        var pauses: [TimeInterval] = []
        for n in 0..<5 {
            let base = at(10 + n)
            engine.handle(.thresholdReached(generation: session.armedGeneration), session: &session, now: base)
            engine.handle(.chooseContinue, session: &session, now: base)
            guard case .pausing(let until, _) = session.phase else {
                XCTAssertEqual(session.phase, .awaitingParent(reason: .escalationStage, since: base))
                XCTAssertEqual(n, 4)
                break
            }
            pauses.append(until.timeIntervalSince(base))
            engine.handle(.pauseElapsed, session: &session, now: until)
            engine.handle(.submitAnswer("23"), session: &session, now: until)
            engine.handle(.armSucceeded(generation: session.armedGeneration), session: &session, now: until)
        }
        XCTAssertEqual(pauses, [20, 30, 60, 120])
    }

    func testDailyLimitCannotBeSolvedAwayAndLiftsTomorrow() {
        let engine = makeEngine(rule(dailyLimit: 600))
        var session = InterventionSession(ruleID: engine.rule.id)
        XCTAssertEqual(engine.handle(.start, session: &session, now: at(9)), [
            .arm(generation: 1, threshold: 120), .armDailyLimit(600),
        ])
        engine.handle(.armSucceeded(generation: 1), session: &session, now: at(9))

        let effects = engine.handle(.dailyLimitReached, session: &session, now: at(12))
        XCTAssertEqual(kinds(effects), [.dailyLimitReached])
        XCTAssertEqual(engine.handle(.chooseContinue, session: &session, now: at(12, 1)), [])
        XCTAssertEqual(engine.handle(.intervalEnded, session: &session, now: at(23)), [], "cap outlasts active hours")

        let morning = engine.handle(.intervalStarted, session: &session, now: at(7, day: 6))
        XCTAssertEqual(morning, [.arm(generation: 2, threshold: 120)])
        let lifted = engine.handle(.armSucceeded(generation: 2), session: &session, now: at(7, day: 6))
        XCTAssertEqual(lifted, [.removeShield])
        XCTAssertEqual(session.phase, .monitoring)
        XCTAssertEqual(session.continuationsToday, 0, "lifting the cap isn't a continuation")
    }

    func testStopAlwaysClearsEverything() {
        let engine = makeEngine(rule())
        var session = started(engine, now: at(9))
        engine.handle(.thresholdReached(generation: 1), session: &session, now: at(9, 2))
        XCTAssertEqual(engine.handle(.stop, session: &session, now: at(9, 3)), [.stopMonitoring, .removeShield])
        XCTAssertEqual(session.phase, .inactive)
    }

    func testDisabledRuleDoesNotStart() {
        var disabled = rule()
        disabled.enabled = false
        var session = InterventionSession(ruleID: disabled.id)
        XCTAssertEqual(makeEngine(disabled).handle(.start, session: &session, now: at(9)), [])
    }

    // MARK: Persistence across process death

    func testAppKilledDuringPauseResumesFromPersistedState() throws {
        let engine = makeEngine(rule(pause: 60))
        var session = started(engine, now: at(9))
        engine.handle(.thresholdReached(generation: 1), session: &session, now: at(9, 2))
        engine.handle(.chooseContinue, session: &session, now: at(9, 3))

        // Simulate the process being killed: persist, relaunch, restore.
        let data = try JSONEncoder().encode(session)
        var restored = try JSONDecoder().decode(InterventionSession.self, from: data)
        XCTAssertEqual(restored, session)

        // The pause is wall-clock based, so it's honored across the relaunch.
        XCTAssertEqual(engine.handle(.pauseElapsed, session: &restored, now: at(9, 3, 59)), [])
        engine.handle(.pauseElapsed, session: &restored, now: at(9, 4))
        guard case .challenge = restored.phase else { return XCTFail() }
    }

    func testChallengeStateRoundTrips() throws {
        let engine = makeEngine(rule(pause: 0))
        var session = started(engine, now: at(9))
        engine.handle(.thresholdReached(generation: 1), session: &session, now: at(9, 2))
        engine.handle(.chooseContinue, session: &session, now: at(9, 3))
        engine.handle(.submitAnswer("1"), session: &session, now: at(9, 3))
        let restored = try JSONDecoder().decode(InterventionSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored, session)
    }

    // MARK: Names and summaries

    func testMonitoringNamesRoundTrip() {
        let id = UUID()
        XCTAssertEqual(
            MonitoringNames.parse(event: MonitoringNames.event(ruleID: id, generation: 17)),
            .threshold(ruleID: id, generation: 17)
        )
        XCTAssertEqual(MonitoringNames.parse(event: MonitoringNames.dailyLimitEvent(ruleID: id)), .dailyLimit(ruleID: id))
        XCTAssertNil(MonitoringNames.parse(event: "com.scrollbrake.sessionLimitReached"))
        XCTAssertNil(MonitoringNames.parse(event: "rule.\(id.uuidString).gX"))
    }

    func testDailySummaryCountsOnlyWhatBreakScrollGenerated() {
        let id = UUID()
        func r(_ kind: InterventionRecord.Kind, _ day: String) -> InterventionRecord {
            InterventionRecord(kind: kind, ruleID: id, dayKey: day, occurredAt: Date())
        }
        let summaries = DailySummary.summarize(
            [r(.intervention, "2026-10-05"), r(.stopped, "2026-10-05"), r(.intervention, "2026-10-05"),
             r(.continued, "2026-10-05"), r(.challengeSolved, "2026-10-05"), r(.unlocked, "2026-10-05"),
             r(.intervention, "2026-10-06")],
            usageInterval: { $0 == id ? 900 : nil }
        )
        XCTAssertEqual(summaries, [
            DailySummary(dayKey: "2026-10-05", interventions: 2, stopped: 1, continued: 1, allowanceGranted: 900),
            DailySummary(dayKey: "2026-10-06", interventions: 1),
        ])
    }
}
