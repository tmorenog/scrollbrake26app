import Foundation

/// Makes each additional continuation in a day harder.
public struct EscalationStage: Codable, Equatable, Sendable {
    /// First continuation (1-based, per day) this stage applies to. It stays in
    /// effect until a later stage's `continuationNumber` is reached.
    public var continuationNumber: Int
    public var pauseDuration: TimeInterval
    public var challengeDifficulty: ChallengeDifficulty
    /// Phase 2: needs the cross-device approval flow (see SCREEN_TIME_FEASIBILITY.md).
    public var requiresParentApproval: Bool

    public init(
        continuationNumber: Int,
        pauseDuration: TimeInterval,
        challengeDifficulty: ChallengeDifficulty,
        requiresParentApproval: Bool = false
    ) {
        self.continuationNumber = continuationNumber
        self.pauseDuration = pauseDuration
        self.challengeDifficulty = challengeDifficulty
        self.requiresParentApproval = requiresParentApproval
    }
}

public struct EscalationPolicy: Codable, Equatable, Sendable {
    /// Empty means no escalation: the rule's base pause and challenge always apply.
    public var stages: [EscalationStage]

    public init(stages: [EscalationStage]) {
        self.stages = stages.sorted { $0.continuationNumber < $1.continuationNumber }
    }

    public static let none = EscalationPolicy(stages: [])

    /// The example ladder from the product spec.
    public static let standard = EscalationPolicy(stages: [
        EscalationStage(continuationNumber: 1, pauseDuration: 20, challengeDifficulty: .easy),
        EscalationStage(continuationNumber: 2, pauseDuration: 30, challengeDifficulty: .medium),
        EscalationStage(continuationNumber: 3, pauseDuration: 60, challengeDifficulty: .medium),
        EscalationStage(continuationNumber: 4, pauseDuration: 120, challengeDifficulty: .hard),
        EscalationStage(
            continuationNumber: 5, pauseDuration: 120, challengeDifficulty: .hard,
            requiresParentApproval: true
        ),
    ])

    public var isEnabled: Bool { !stages.isEmpty }

    public func stage(forContinuation number: Int) -> EscalationStage? {
        stages.last { $0.continuationNumber <= number }
    }
}

/// What the person must do to earn the next allowance.
public enum InterventionStep: Equatable, Sendable {
    case pauseAndChallenge(pause: TimeInterval, difficulty: ChallengeDifficulty)
    /// Local challenges can't unlock; a parent (or the owner, in Self-Control Mode) must.
    case parentRequired(ParentRequiredReason)
}

public enum ParentRequiredReason: String, Codable, Equatable, Sendable {
    case escalationStage
    case maxContinuationsReached
    case dailyLimitReached
}

/// One intervention rule: X minutes of the selected apps, then an intervention, repeated.
///
/// `selectionData` is a `PropertyListEncoder`-encoded `FamilyActivitySelection`.
/// It's opaque here so the core stays free of Screen Time frameworks; the iOS
/// layer encodes and decodes it.
public struct InterventionRule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var selectionData: Data
    public var usageInterval: TimeInterval
    public var pauseDuration: TimeInterval
    public var challengeDifficulty: ChallengeDifficulty
    public var escalationPolicy: EscalationPolicy
    public var activeSchedule: WeeklySchedule
    /// Continuations allowed per day before a parent is required. `nil` = unlimited.
    public var maxContinuations: Int?
    /// Optional hard cap per day; no challenge lifts it.
    public var dailyLimit: TimeInterval?
    public var enabled: Bool

    // Sync metadata (see SyncResolver).
    public var version: Int
    public var updatedAt: Date
    public var updatedBy: String

    public init(
        id: UUID = UUID(),
        name: String,
        selectionData: Data = Data(),
        usageInterval: TimeInterval = InterventionRule.defaultUsageInterval,
        pauseDuration: TimeInterval = InterventionRule.defaultPauseDuration,
        challengeDifficulty: ChallengeDifficulty = .medium,
        escalationPolicy: EscalationPolicy = .none,
        activeSchedule: WeeklySchedule = .daytime,
        maxContinuations: Int? = nil,
        dailyLimit: TimeInterval? = nil,
        enabled: Bool = true,
        version: Int = 1,
        updatedAt: Date = Date(),
        updatedBy: String = ""
    ) {
        self.id = id
        self.name = name
        self.selectionData = selectionData
        self.usageInterval = usageInterval
        self.pauseDuration = pauseDuration
        self.challengeDifficulty = challengeDifficulty
        self.escalationPolicy = escalationPolicy
        self.activeSchedule = activeSchedule
        self.maxContinuations = maxContinuations
        self.dailyLimit = dailyLimit
        self.enabled = enabled
        self.version = version
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }

    public static let defaultUsageInterval: TimeInterval = 15 * 60
    public static let defaultPauseDuration: TimeInterval = 30

    public static let usageIntervalPresets: [TimeInterval] = [5, 10, 15, 20, 30, 45, 60].map { $0 * 60 }
    public static let pauseDurationPresets: [TimeInterval] = [0, 10, 20, 30, 60, 120, 300]

    /// The pause and challenge (or parent requirement) for the `number`-th
    /// continuation today (1-based).
    public func step(forContinuation number: Int) -> InterventionStep {
        if let max = maxContinuations, number > max {
            return .parentRequired(.maxContinuationsReached)
        }
        if let stage = escalationPolicy.stage(forContinuation: number) {
            if stage.requiresParentApproval {
                return .parentRequired(.escalationStage)
            }
            return .pauseAndChallenge(pause: stage.pauseDuration, difficulty: stage.challengeDifficulty)
        }
        return .pauseAndChallenge(pause: pauseDuration, difficulty: challengeDifficulty)
    }

    public enum ValidationError: Error, Equatable, Sendable {
        case emptyName
        case usageIntervalOutOfRange
        case negativePause
        case invalidMaxContinuations
        case dailyLimitShorterThanInterval
        case schedule(WeeklySchedule.ValidationError)
    }

    public func validate() -> [ValidationError] {
        var errors: [ValidationError] = []
        if name.trimmingCharacters(in: .whitespaces).isEmpty { errors.append(.emptyName) }
        if usageInterval < 30 || usageInterval > 24 * 3600 { errors.append(.usageIntervalOutOfRange) }
        if pauseDuration < 0 { errors.append(.negativePause) }
        if let max = maxContinuations, max < 0 { errors.append(.invalidMaxContinuations) }
        if let limit = dailyLimit, limit < usageInterval { errors.append(.dailyLimitShorterThanInterval) }
        errors += activeSchedule.validate().map(ValidationError.schedule)
        return errors
    }
}
