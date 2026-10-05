import Foundation

/// Limits guessing of the parent passcode: after `freeAttempts` wrong tries,
/// each further wrong try locks entry for a doubling period (1, 2, 4… minutes,
/// capped at an hour). A correct passcode resets everything.
public struct PasscodeLockout: Codable, Equatable, Sendable {
    public private(set) var failures = 0
    public private(set) var lockedUntil: Date?

    public static let freeAttempts = 5
    public static let baseLock: TimeInterval = 60
    public static let maxLock: TimeInterval = 3600

    public init() {}

    public func isLocked(at now: Date) -> Bool {
        lockedUntil.map { now < $0 } ?? false
    }

    public mutating func recordFailure(at now: Date) {
        failures += 1
        let excess = failures - Self.freeAttempts
        guard excess >= 0 else { return }
        let lock = min(Self.maxLock, Self.baseLock * pow(2, Double(excess)))
        lockedUntil = now.addingTimeInterval(lock)
    }

    public mutating func recordSuccess() {
        failures = 0
        lockedUntil = nil
    }
}
