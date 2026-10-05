import XCTest
@testable import BreakScrollCore

final class RuleAndScheduleTests: XCTestCase {
    // MARK: Escalation

    func testWithoutEscalationTheBaseStepAlwaysApplies() {
        let rule = InterventionRule(name: "Social", pauseDuration: 30, challengeDifficulty: .medium)
        for n in 1...10 {
            XCTAssertEqual(rule.step(forContinuation: n), .pauseAndChallenge(pause: 30, difficulty: .medium))
        }
    }

    func testStandardEscalationLadder() {
        let rule = InterventionRule(name: "Social", escalationPolicy: .standard)
        XCTAssertEqual(rule.step(forContinuation: 1), .pauseAndChallenge(pause: 20, difficulty: .easy))
        XCTAssertEqual(rule.step(forContinuation: 2), .pauseAndChallenge(pause: 30, difficulty: .medium))
        XCTAssertEqual(rule.step(forContinuation: 3), .pauseAndChallenge(pause: 60, difficulty: .medium))
        XCTAssertEqual(rule.step(forContinuation: 4), .pauseAndChallenge(pause: 120, difficulty: .hard))
        XCTAssertEqual(rule.step(forContinuation: 5), .parentRequired(.escalationStage))
        XCTAssertEqual(rule.step(forContinuation: 9), .parentRequired(.escalationStage))
    }

    func testStagesAreSortedAndFillGaps() {
        let policy = EscalationPolicy(stages: [
            EscalationStage(continuationNumber: 3, pauseDuration: 60, challengeDifficulty: .hard),
            EscalationStage(continuationNumber: 1, pauseDuration: 10, challengeDifficulty: .easy),
        ])
        XCTAssertEqual(policy.stage(forContinuation: 2)?.pauseDuration, 10)
        XCTAssertEqual(policy.stage(forContinuation: 4)?.challengeDifficulty, .hard)
        XCTAssertNil(EscalationPolicy(stages: [
            EscalationStage(continuationNumber: 2, pauseDuration: 1, challengeDifficulty: .easy),
        ]).stage(forContinuation: 1))
    }

    func testMaxContinuationsTakesPrecedence() {
        let rule = InterventionRule(name: "Social", escalationPolicy: .standard, maxContinuations: 2)
        XCTAssertEqual(rule.step(forContinuation: 2), .pauseAndChallenge(pause: 30, difficulty: .medium))
        XCTAssertEqual(rule.step(forContinuation: 3), .parentRequired(.maxContinuationsReached))
    }

    func testRuleValidation() {
        XCTAssertEqual(InterventionRule(name: "Social").validate(), [])
        let bad = InterventionRule(
            name: " ", usageInterval: 10, pauseDuration: -1,
            activeSchedule: WeeklySchedule(activeDays: [], start: TimeOfDay(hour: 9), end: TimeOfDay(hour: 9, minute: 10)),
            maxContinuations: -1, dailyLimit: 5
        )
        XCTAssertEqual(bad.validate(), [
            .emptyName, .usageIntervalOutOfRange, .negativePause, .invalidMaxContinuations,
            .dailyLimitShorterThanInterval, .schedule(.noActiveDays), .schedule(.intervalTooShort),
        ])
    }

    func testRuleRoundTripsThroughJSON() throws {
        let rule = InterventionRule(
            name: "Social", selectionData: Data([1, 2, 3]), escalationPolicy: .standard,
            maxContinuations: 4, dailyLimit: 5400, version: 42, updatedAt: Date(timeIntervalSince1970: 1_000), updatedBy: "parent"
        )
        let decoded = try JSONDecoder().decode(InterventionRule.self, from: JSONEncoder().encode(rule))
        XCTAssertEqual(decoded, rule)
    }

    // MARK: Schedule

    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }()

    /// 2026-10-05 is a Monday.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testDaytimeWindowBoundaries() {
        let schedule = WeeklySchedule.daytime
        XCTAssertFalse(schedule.isActive(at: date(5, 6, 59), calendar: calendar))
        XCTAssertTrue(schedule.isActive(at: date(5, 7, 0), calendar: calendar))
        XCTAssertTrue(schedule.isActive(at: date(5, 22, 29), calendar: calendar))
        XCTAssertFalse(schedule.isActive(at: date(5, 22, 30), calendar: calendar))
    }

    func testInactiveWeekday() {
        let schedule = WeeklySchedule(activeDays: Weekday.weekdays, start: TimeOfDay(hour: 7), end: TimeOfDay(hour: 22))
        XCTAssertTrue(schedule.isActive(at: date(9, 12), calendar: calendar))   // Friday
        XCTAssertFalse(schedule.isActive(at: date(10, 12), calendar: calendar)) // Saturday
    }

    func testOvernightWindowBelongsToItsStartDay() {
        let schedule = WeeklySchedule(activeDays: [.friday], start: TimeOfDay(hour: 20), end: TimeOfDay(hour: 2))
        XCTAssertTrue(schedule.crossesMidnight)
        XCTAssertEqual(schedule.durationMinutes, 360)
        XCTAssertTrue(schedule.isActive(at: date(9, 23), calendar: calendar))   // Friday night
        XCTAssertTrue(schedule.isActive(at: date(10, 1), calendar: calendar))   // Saturday 1 AM
        XCTAssertFalse(schedule.isActive(at: date(10, 2), calendar: calendar))
        XCTAssertFalse(schedule.isActive(at: date(10, 23), calendar: calendar)) // Saturday night
    }

    func testAlwaysScheduleCoversWholeDay() {
        XCTAssertEqual(WeeklySchedule.always.validate(), [])
        XCTAssertTrue(WeeklySchedule.always.isActive(at: date(5, 0, 0), calendar: calendar))
        XCTAssertTrue(WeeklySchedule.always.isActive(at: date(5, 23, 59), calendar: calendar))
    }

    func testDayKeyUsesTheCalendarsTimeZone() {
        let instant = date(5, 23, 30) // 23:30 in Los Angeles = 06:30 next day UTC
        XCTAssertEqual(WeeklySchedule.dayKey(for: instant, calendar: calendar), "2026-10-05")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(WeeklySchedule.dayKey(for: instant, calendar: utc), "2026-10-06")
    }

    // MARK: Overrides

    func testOverrideDurations() {
        let now = date(5, 20, 14)
        let hour = Override.make(.minutes(60), now: now, calendar: calendar, createdBy: "parent")
        XCTAssertTrue(hour.isActive(at: date(5, 21, 13)))
        XCTAssertFalse(hour.isActive(at: date(5, 21, 14)))

        let tomorrow = Override.make(.untilTomorrow, now: now, calendar: calendar, createdBy: "parent")
        XCTAssertEqual(tomorrow.endsAt, date(6, 0))

        var manual = Override.make(.untilResumed, now: now, calendar: calendar, createdBy: "parent")
        XCTAssertTrue(manual.isActive(at: date(20, 0)))
        manual.endedEarlyAt = date(5, 21)
        XCTAssertFalse(manual.isActive(at: date(5, 21, 1)))
        XCTAssertFalse(manual.isActive(at: date(5, 20, 0)), "not active before creation")
    }
}
