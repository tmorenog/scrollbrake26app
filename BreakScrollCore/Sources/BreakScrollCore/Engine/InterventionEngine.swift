import Foundation

/// Where one rule's intervention lifecycle currently is.
///
///     inactive ─start─▶ arming ─ok─▶ monitoring ─threshold─▶ shielded
///                                        ▲                   │      │
///                                        │                 Done  Continue
///                                        │                   ▼      ▼
///                                        │               stopped  pausing ─▶ challenge
///                                        │                              wrong ↺   │ right
///                                        └──────ok── arming(.continuation) ◀───────┘
///                                                         │ failed
///                                                         ▼
///                                                    rearmFailed (shield stays up)
public enum InterventionPhase: Codable, Equatable, Sendable {
    case inactive
    case outsideActiveHours
    /// Waiting for `startMonitoring` to succeed. Unless the purpose is
    /// `.start`, the shield is up and comes down only once arming succeeds.
    case arming(ArmPurpose)
    case monitoring
    /// Threshold reached; the shield shows "I'm Done" / "Continue".
    case shielded(since: Date)
    /// The person chose "I'm Done"; the shield stays up.
    case stopped(at: Date)
    case pausing(until: Date, difficulty: ChallengeDifficulty)
    case challenge(MathChallenge, failedAttempts: Int)
    case rearmFailed(ArmPurpose)
    case awaitingParent(reason: ParentRequiredReason, since: Date)
    case dailyLimitReached(since: Date)

    /// Whether the selected apps should currently be shielded.
    public var isShielded: Bool {
        switch self {
        case .inactive, .outsideActiveHours, .monitoring:
            return false
        case .arming(let purpose):
            return purpose != .start
        case .shielded, .stopped, .pausing, .challenge, .rearmFailed, .awaitingParent, .dailyLimitReached:
            return true
        }
    }
}

/// Why monitoring is being (re-)armed.
public enum ArmPurpose: String, Codable, Sendable {
    /// Monitoring begins; nothing is shielded.
    case start
    /// The person earned another allowance (counts toward today's continuations).
    case continuation
    /// A new day lifted the daily cap (doesn't count as a continuation).
    case liftDailyLimit
}

/// Persisted (App Group) state for one rule on the enforcing device.
public struct InterventionSession: Codable, Equatable, Sendable {
    public var ruleID: UUID
    public var phase: InterventionPhase
    /// Bumped on every arm; embedded in the DeviceActivity event name so stale
    /// or duplicate threshold callbacks can be told apart.
    public var armedGeneration: Int
    public var dayKey: String
    /// Unlocks granted today. The next continuation is `continuationsToday + 1`.
    public var continuationsToday: Int

    public init(
        ruleID: UUID,
        phase: InterventionPhase = .inactive,
        armedGeneration: Int = 0,
        dayKey: String = "",
        continuationsToday: Int = 0
    ) {
        self.ruleID = ruleID
        self.phase = phase
        self.armedGeneration = armedGeneration
        self.dayKey = dayKey
        self.continuationsToday = continuationsToday
    }
}

public enum InterventionInput: Equatable, Sendable {
    /// Begin enforcing the rule.
    case start
    /// No-op apart from day rollover. Send when the app comes to the foreground.
    case refresh
    /// Rule disabled, override started, or authorization revoked.
    case stop
    case armSucceeded(generation: Int)
    case armFailed(generation: Int)
    case retryArm
    /// `DeviceActivityMonitor.intervalDidStart`, or the app coming to the foreground.
    case intervalStarted
    /// `DeviceActivityMonitor.intervalDidEnd`. Also fires during our own re-arm,
    /// so it's ignored while still inside active hours.
    case intervalEnded
    case thresholdReached(generation: Int)
    case dailyLimitReached
    case chooseDone
    case chooseContinue
    case pauseElapsed
    case submitAnswer(String)
    case requestDifferentProblem
}

/// Side effects for the platform layer to perform. Arm results are fed back in
/// as `.armSucceeded` / `.armFailed`.
public enum InterventionEffect: Equatable, Sendable {
    /// `DeviceActivityCenter.startMonitoring` for the rule's activity, with one
    /// event named `MonitoringNames.event(ruleID:generation:)`, using
    /// `includesPastActivity: false`.
    case arm(generation: Int, threshold: TimeInterval)
    /// Start the separate daily-cap activity (never re-armed during the day).
    case armDailyLimit(TimeInterval)
    case stopMonitoring
    case applyShield
    case removeShield
    case record(InterventionRecord)
}

/// A pure reducer for one rule. No Screen Time calls, no I/O, no clocks: the
/// caller passes `now`, so every path is unit-testable.
public struct InterventionEngine {
    public var rule: InterventionRule
    public var calendar: Calendar
    public var makeChallenge: (ChallengeDifficulty) -> MathChallenge?

    /// After this many wrong answers the problem is replaced, so guessing doesn't pay off.
    public static let attemptsBeforeNewProblem = 3

    public init(
        rule: InterventionRule,
        calendar: Calendar,
        makeChallenge: @escaping (ChallengeDifficulty) -> MathChallenge? = { MathChallengeGenerator.make($0) }
    ) {
        self.rule = rule
        self.calendar = calendar
        self.makeChallenge = makeChallenge
    }

    @discardableResult
    public func handle(_ input: InterventionInput, session: inout InterventionSession, now: Date) -> [InterventionEffect] {
        var effects: [InterventionEffect] = []
        rollDayIfNeeded(&session, now: now, effects: &effects)

        switch input {
        case .start:
            guard rule.enabled, session.phase == .inactive else { break }
            beginArm(.start, &session, &effects)
            if let limit = rule.dailyLimit {
                effects.append(.armDailyLimit(limit))
            }

        case .refresh:
            break

        case .stop:
            session.phase = .inactive
            effects += [.stopMonitoring, .removeShield]

        case .armSucceeded(let generation):
            guard case .arming(let purpose) = session.phase, generation == session.armedGeneration else { break }
            session.phase = .monitoring
            switch purpose {
            case .start:
                break
            case .continuation:
                session.continuationsToday += 1
                effects += [.removeShield, record(.unlocked, session, now)]
            case .liftDailyLimit:
                effects.append(.removeShield)
            }

        case .armFailed(let generation):
            guard case .arming(let purpose) = session.phase, generation == session.armedGeneration else { break }
            if purpose == .start {
                session.phase = .inactive
            } else {
                // Never fail open: keep the shield and let the person retry.
                session.phase = .rearmFailed(purpose)
                effects.append(record(.rearmFailed, session, now))
            }

        case .retryArm:
            guard case .rearmFailed(let purpose) = session.phase else { break }
            beginArm(purpose, &session, &effects)

        case .intervalStarted:
            if session.phase == .outsideActiveHours {
                session.phase = .monitoring
            }

        case .intervalEnded:
            guard !rule.activeSchedule.isActive(at: now, calendar: calendar) else { break }
            switch session.phase {
            case .monitoring, .shielded, .stopped, .pausing, .challenge, .awaitingParent, .rearmFailed:
                session.phase = .outsideActiveHours
                effects.append(.removeShield)
            case .inactive, .outsideActiveHours, .arming, .dailyLimitReached:
                break
            }

        case .thresholdReached(let generation):
            // Stale generation, a duplicate callback, or an inactive weekday.
            guard session.phase == .monitoring,
                  generation == session.armedGeneration,
                  rule.activeSchedule.isActive(at: now, calendar: calendar) else { break }
            session.phase = .shielded(since: now)
            effects += [.applyShield, record(.intervention, session, now)]

        case .dailyLimitReached:
            switch session.phase {
            case .inactive, .outsideActiveHours, .dailyLimitReached:
                break
            default:
                session.phase = .dailyLimitReached(since: now)
                effects += [.applyShield, record(.dailyLimitReached, session, now)]
            }

        case .chooseDone:
            switch session.phase {
            case .shielded, .pausing, .challenge, .rearmFailed:
                session.phase = .stopped(at: now)
                effects.append(record(.stopped, session, now))
            default:
                break
            }

        case .chooseContinue:
            switch session.phase {
            case .shielded, .stopped:
                beginContinuation(&session, now: now, &effects)
            default:
                break
            }

        case .pauseElapsed:
            guard case .pausing(let until, let difficulty) = session.phase, now >= until else { break }
            beginChallenge(difficulty, failedAttempts: 0, &session, &effects)

        case .submitAnswer(let answer):
            guard case .challenge(let challenge, let failed) = session.phase else { break }
            if challenge.isCorrect(answer) {
                effects.append(record(.challengeSolved, session, now, attempts: failed + 1))
                beginArm(.continuation, &session, &effects)
            } else if (failed + 1) % Self.attemptsBeforeNewProblem == 0 {
                beginChallenge(challenge.difficulty, failedAttempts: failed + 1, &session, &effects)
            } else {
                session.phase = .challenge(challenge, failedAttempts: failed + 1)
            }

        case .requestDifferentProblem:
            guard case .challenge(let challenge, let failed) = session.phase else { break }
            beginChallenge(challenge.difficulty, failedAttempts: failed, &session, &effects)
        }
        return effects
    }

    // MARK: - Helpers

    private func rollDayIfNeeded(_ session: inout InterventionSession, now: Date, effects: inout [InterventionEffect]) {
        let today = WeeklySchedule.dayKey(for: now, calendar: calendar)
        guard today != session.dayKey else { return }
        let isFirstDay = session.dayKey.isEmpty
        session.dayKey = today
        session.continuationsToday = 0
        guard !isFirstDay else { return }

        switch session.phase {
        case .dailyLimitReached:
            // A new day lifts the daily cap.
            beginArm(.liftDailyLimit, &session, &effects)
        case .awaitingParent:
            // Today's continuation count reset, so local challenges apply again.
            session.phase = .shielded(since: now)
        default:
            break
        }
    }

    private func beginArm(_ purpose: ArmPurpose, _ session: inout InterventionSession, _ effects: inout [InterventionEffect]) {
        session.armedGeneration += 1
        session.phase = .arming(purpose)
        effects.append(.arm(generation: session.armedGeneration, threshold: rule.usageInterval))
    }

    private func beginContinuation(_ session: inout InterventionSession, now: Date, _ effects: inout [InterventionEffect]) {
        switch rule.step(forContinuation: session.continuationsToday + 1) {
        case .parentRequired(let reason):
            session.phase = .awaitingParent(reason: reason, since: now)
            effects.append(record(.parentRequired, session, now))
        case .pauseAndChallenge(let pause, let difficulty):
            effects.append(record(.continued, session, now))
            if pause > 0 {
                session.phase = .pausing(until: now.addingTimeInterval(pause), difficulty: difficulty)
            } else {
                beginChallenge(difficulty, failedAttempts: 0, &session, &effects)
            }
        }
    }

    private func beginChallenge(
        _ difficulty: ChallengeDifficulty,
        failedAttempts: Int,
        _ session: inout InterventionSession,
        _ effects: inout [InterventionEffect]
    ) {
        if let challenge = makeChallenge(difficulty) {
            session.phase = .challenge(challenge, failedAttempts: failedAttempts)
        } else {
            // `.none` difficulty: the pause alone earns the next allowance.
            beginArm(.continuation, &session, &effects)
        }
    }

    private func record(
        _ kind: InterventionRecord.Kind,
        _ session: InterventionSession,
        _ now: Date,
        attempts: Int? = nil
    ) -> InterventionEffect {
        .record(InterventionRecord(kind: kind, ruleID: rule.id, dayKey: session.dayKey, occurredAt: now, attempts: attempts))
    }
}

/// Names shared by the app and the DeviceActivity extension.
public enum MonitoringNames {
    public static func activity(ruleID: UUID) -> String {
        "rule.\(ruleID.uuidString)"
    }

    public static func dailyLimitActivity(ruleID: UUID) -> String {
        "daily.\(ruleID.uuidString)"
    }

    public static func event(ruleID: UUID, generation: Int) -> String {
        "rule.\(ruleID.uuidString).g\(generation)"
    }

    public static func dailyLimitEvent(ruleID: UUID) -> String {
        "daily.\(ruleID.uuidString).limit"
    }

    public enum ParsedActivity: Equatable, Sendable {
        case rule(UUID)
        case dailyLimit(UUID)
    }

    public static func parse(activity name: String) -> ParsedActivity? {
        let parts = name.split(separator: ".")
        guard parts.count == 2, let ruleID = UUID(uuidString: String(parts[1])) else { return nil }
        switch parts[0] {
        case "rule": return .rule(ruleID)
        case "daily": return .dailyLimit(ruleID)
        default: return nil
        }
    }

    public enum ParsedEvent: Equatable, Sendable {
        case threshold(ruleID: UUID, generation: Int)
        case dailyLimit(ruleID: UUID)
    }

    public static func parse(event name: String) -> ParsedEvent? {
        let parts = name.split(separator: ".")
        guard parts.count == 3, let ruleID = UUID(uuidString: String(parts[1])) else { return nil }
        switch (parts[0], parts[2]) {
        case ("rule", let tag) where tag.hasPrefix("g"):
            guard let generation = Int(tag.dropFirst()) else { return nil }
            return .threshold(ruleID: ruleID, generation: generation)
        case ("daily", "limit"):
            return .dailyLimit(ruleID: ruleID)
        default:
            return nil
        }
    }
}
