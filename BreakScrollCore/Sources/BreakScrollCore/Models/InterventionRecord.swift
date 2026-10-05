import Foundation

/// Something BreakScroll itself did or saw. This is the only activity data we
/// keep: no app identities, no content, nothing Screen Time doesn't give us.
public struct InterventionRecord: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// The usage threshold was reached and the shield went up.
        case intervention
        /// "I'm Done".
        case stopped
        /// "Continue" (the pause and challenge follow).
        case continued
        /// Challenge answered correctly; `attempts` is set.
        case challengeSolved
        /// A new allowance was armed and the shield removed.
        case unlocked
        /// A local challenge can't unlock; a parent is needed.
        case parentRequired
        case dailyLimitReached
        /// Re-arming failed, so the shield stayed up.
        case rearmFailed
    }

    public var kind: Kind
    public var ruleID: UUID
    public var dayKey: String
    public var occurredAt: Date
    public var attempts: Int?

    public init(kind: Kind, ruleID: UUID, dayKey: String, occurredAt: Date, attempts: Int? = nil) {
        self.kind = kind
        self.ruleID = ruleID
        self.dayKey = dayKey
        self.occurredAt = occurredAt
        self.attempts = attempts
    }
}

/// The privacy-preserving daily numbers a parent sees, and the only activity
/// data synced off the child's device: counts per day, no timestamps.
public struct DailySummary: Codable, Equatable, Sendable {
    public var dayKey: String
    public var interventions: Int
    public var stopped: Int
    public var continued: Int
    /// Allowance granted by unlocks (unlocks × interval). This is time BreakScroll
    /// *granted*, not measured usage, and must be labelled that way.
    public var allowanceGranted: TimeInterval

    public init(dayKey: String, interventions: Int = 0, stopped: Int = 0, continued: Int = 0, allowanceGranted: TimeInterval = 0) {
        self.dayKey = dayKey
        self.interventions = interventions
        self.stopped = stopped
        self.continued = continued
        self.allowanceGranted = allowanceGranted
    }

    /// Builds one summary per day from local records.
    public static func summarize(
        _ records: [InterventionRecord],
        usageInterval: (UUID) -> TimeInterval?
    ) -> [DailySummary] {
        var byDay: [String: DailySummary] = [:]
        for record in records {
            var summary = byDay[record.dayKey] ?? DailySummary(dayKey: record.dayKey)
            switch record.kind {
            case .intervention:
                summary.interventions += 1
            case .stopped:
                summary.stopped += 1
            case .unlocked:
                summary.continued += 1
                summary.allowanceGranted += usageInterval(record.ruleID) ?? 0
            case .continued, .challengeSolved, .parentRequired, .dailyLimitReached, .rearmFailed:
                break
            }
            byDay[record.dayKey] = summary
        }
        return byDay.values.sorted { $0.dayKey < $1.dayKey }
    }
}
