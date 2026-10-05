import Foundation

/// Which role this install of BreakScroll plays. Stored locally; it only picks
/// the UI. It is never trusted for authorization: parent powers come from
/// owning the CloudKit configuration zone (see SCREEN_TIME_FEASIBILITY.md §4).
public enum AppMode: String, Codable, Sendable {
    /// Adult limiting their own device (`FamilyControlsMember.individual`).
    case selfControl
    /// Parent's device: edits rules for children, enforces nothing locally.
    case familyParent
    /// Child's device (`FamilyControlsMember.child`): enforces the parent's rules.
    case familyChild
}

/// One child as the parent sees them. `nickname` is typed by the parent; we
/// never read identity from the system.
public struct ChildConfiguration: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var nickname: String
    public var rules: [InterventionRule]
    public var version: Int
    public var updatedAt: Date
    public var updatedBy: String

    public init(
        id: UUID = UUID(),
        nickname: String,
        rules: [InterventionRule] = [],
        version: Int = 1,
        updatedAt: Date = Date(),
        updatedBy: String = ""
    ) {
        self.id = id
        self.nickname = nickname
        self.rules = rules
        self.version = version
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }
}

public struct FamilyConfiguration: Codable, Equatable, Sendable {
    public var id: UUID
    public var children: [ChildConfiguration]

    public init(id: UUID = UUID(), children: [ChildConfiguration] = []) {
        self.id = id
        self.children = children
    }
}

/// A temporary pause of all BreakScroll interventions.
public struct Override: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    /// `nil` means "until manually resumed".
    public var endsAt: Date?
    public var createdBy: String
    public var endedEarlyAt: Date?

    public init(id: UUID = UUID(), createdAt: Date, endsAt: Date?, createdBy: String, endedEarlyAt: Date? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.endsAt = endsAt
        self.createdBy = createdBy
        self.endedEarlyAt = endedEarlyAt
    }

    public func isActive(at date: Date) -> Bool {
        guard date >= createdAt, endedEarlyAt.map({ date < $0 }) ?? true else { return false }
        return endsAt.map { date < $0 } ?? true
    }

    public enum Duration: Equatable, Sendable {
        case minutes(Int)
        case untilTomorrow
        case untilResumed
    }

    public static func make(_ duration: Duration, now: Date, calendar: Calendar, createdBy: String) -> Override {
        let endsAt: Date?
        switch duration {
        case .minutes(let minutes):
            endsAt = now.addingTimeInterval(TimeInterval(minutes * 60))
        case .untilTomorrow:
            endsAt = calendar.nextDate(
                after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime
            )
        case .untilResumed:
            endsAt = nil
        }
        return Override(createdAt: now, endsAt: endsAt, createdBy: createdBy)
    }
}

// MARK: - Phase 2 (needs the CloudKit layer)

public struct ParentApprovalRequest: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var childID: UUID
    public var ruleID: UUID
    public var requestedAllowance: TimeInterval
    public var createdAt: Date

    public init(id: UUID = UUID(), childID: UUID, ruleID: UUID, requestedAllowance: TimeInterval, createdAt: Date) {
        self.id = id
        self.childID = childID
        self.ruleID = ruleID
        self.requestedAllowance = requestedAllowance
        self.createdAt = createdAt
    }
}

public struct ParentApprovalDecision: Codable, Equatable, Sendable {
    public enum Outcome: Codable, Equatable, Sendable {
        case allow(TimeInterval)
        case allowUntil(Date)
        case decline
    }

    public var requestID: UUID
    public var outcome: Outcome
    public var decidedAt: Date

    public init(requestID: UUID, outcome: Outcome, decidedAt: Date) {
        self.requestID = requestID
        self.outcome = outcome
        self.decidedAt = decidedAt
    }
}
