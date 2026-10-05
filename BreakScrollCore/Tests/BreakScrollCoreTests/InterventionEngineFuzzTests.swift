import XCTest
@testable import BreakScrollCore

/// Random input sequences against the engine, checking safety invariants
/// after every step. Deterministic: each seed replays the same sequence.
final class InterventionEngineFuzzTests: XCTestCase {
    private var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return cal
    }()

    func testRandomSequencesKeepInvariants() throws {
        for seed in UInt64(1)...UInt64(300) {
            try run(seed: seed, steps: 400)
        }
    }

    private func run(seed: UInt64, steps: Int) throws {
        var rng = SeededGenerator(seed: seed)
        let maxContinuations: Int? = Bool.random(using: &rng) ? Int.random(in: 1...4, using: &rng) : nil
        let rule = InterventionRule(
            name: "Fuzz",
            usageInterval: 120,
            pauseDuration: [0, 10, 30].randomElement(using: &rng)!,
            challengeDifficulty: ChallengeDifficulty.allCases.randomElement(using: &rng)!,
            escalationPolicy: Bool.random(using: &rng) ? .standard : .none,
            activeSchedule: [.daytime, .always, WeeklySchedule(activeDays: Weekday.weekdays, start: TimeOfDay(hour: 8), end: TimeOfDay(hour: 20))]
                .randomElement(using: &rng)!,
            maxContinuations: maxContinuations,
            dailyLimit: Bool.random(using: &rng) ? 1800 : nil
        )
        var challengeRNG = SeededGenerator(seed: seed &* 31)
        let engine = InterventionEngine(rule: rule, calendar: calendar) { difficulty in
            MathChallengeGenerator.make(difficulty, using: &challengeRNG)
        }

        var session = InterventionSession(ruleID: rule.id)
        var now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 6))!
        var shieldUp = false                // what the device would show
        var lastGeneration = 0
        var unlocksToday = 0
        var day = WeeklySchedule.dayKey(for: now, calendar: calendar)
        var pendingArm: Int?

        for step in 0..<steps {
            now = now.addingTimeInterval(TimeInterval([1, 5, 30, 120, 900, 3600, 6 * 3600].randomElement(using: &rng)!))
            let input = randomInput(session: session, pendingArm: pendingArm, rng: &rng)
            let before = session
            let effects = engine.handle(input, session: &session, now: now)
            let context = "seed \(seed) step \(step) input \(input) \(before.phase) → \(session.phase)"

            if WeeklySchedule.dayKey(for: now, calendar: calendar) != day {
                day = WeeklySchedule.dayKey(for: now, calendar: calendar)
                unlocksToday = 0
            }

            // Shield changes only through effects, and only where allowed.
            for effect in effects {
                switch effect {
                case .applyShield:
                    shieldUp = true
                case .removeShield:
                    // The shield only comes down after a successful (re-)arm, an
                    // explicit stop, or leaving active hours. Never on a failure.
                    switch input {
                    case .armSucceeded, .stop, .intervalEnded:
                        break
                    default:
                        XCTFail("shield removed by \(input): \(context)")
                    }
                    shieldUp = false
                case .arm(let generation, let threshold):
                    XCTAssertGreaterThan(generation, lastGeneration, context)
                    XCTAssertEqual(threshold, rule.usageInterval, context)
                    lastGeneration = generation
                    pendingArm = generation
                case .record(let record):
                    if record.kind == .unlocked { unlocksToday += 1 }
                    XCTAssertEqual(record.dayKey, session.dayKey, context)
                case .stopMonitoring, .armDailyLimit:
                    break
                }
            }

            // Inactive / outside hours / plain monitoring never show a shield;
            // every "blocked" phase does (re-arming from .start doesn't).
            switch session.phase {
            case .inactive, .outsideActiveHours, .monitoring, .arming(.start):
                XCTAssertFalse(shieldUp, "shield up while \(session.phase): \(context)")
            default:
                XCTAssertTrue(shieldUp, "shield down while \(session.phase): \(context)")
            }
            XCTAssertEqual(session.phase.isShielded, shieldUp, context)

            XCTAssertGreaterThanOrEqual(session.armedGeneration, before.armedGeneration, context)
            XCTAssertEqual(session.continuationsToday, unlocksToday, context)
            if let max = maxContinuations {
                XCTAssertLessThanOrEqual(session.continuationsToday, max, context)
            }
            let restored = try JSONDecoder().decode(InterventionSession.self, from: JSONEncoder().encode(session))
            XCTAssertEqual(restored, session, context)
            if case .arming = session.phase {} else { pendingArm = nil }
        }
    }

    /// Mostly plausible inputs for the current phase, plus random noise
    /// (stale generations, out-of-order callbacks) to try to break things.
    private func randomInput(session: InterventionSession, pendingArm: Int?, rng: inout SeededGenerator) -> InterventionInput {
        if Int.random(in: 0..<5, using: &rng) == 0 {
            let generation = session.armedGeneration + Int.random(in: -2...1, using: &rng)
            return [
                .start, .stop, .refresh, .intervalStarted, .intervalEnded, .dailyLimitReached,
                .chooseDone, .chooseContinue, .pauseElapsed, .retryArm, .requestDifferentProblem,
                .thresholdReached(generation: generation), .armSucceeded(generation: generation),
                .armFailed(generation: generation), .submitAnswer("\(Int.random(in: 0...200, using: &rng))"),
            ].randomElement(using: &rng)!
        }
        switch session.phase {
        case .inactive:
            return Int.random(in: 0..<10, using: &rng) == 0 ? .stop : .start
        case .arming:
            let generation = pendingArm ?? session.armedGeneration
            return Int.random(in: 0..<6, using: &rng) == 0 ? .armFailed(generation: generation) : .armSucceeded(generation: generation)
        case .monitoring, .outsideActiveHours:
            return [.thresholdReached(generation: session.armedGeneration), .intervalStarted, .intervalEnded, .refresh]
                .randomElement(using: &rng)!
        case .shielded, .stopped:
            return Bool.random(using: &rng) ? .chooseContinue : .chooseDone
        case .pausing:
            return .pauseElapsed
        case .challenge(let challenge, _):
            return .submitAnswer(Bool.random(using: &rng) ? "\(challenge.answer)" : "\(challenge.answer + 1)")
        case .rearmFailed:
            return .retryArm
        case .awaitingParent, .dailyLimitReached:
            return [.refresh, .intervalStarted, .chooseContinue].randomElement(using: &rng)!
        }
    }
}
