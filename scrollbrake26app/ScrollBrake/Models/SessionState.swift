//
//  SessionState.swift
//  ScrollBrake
//
//  Models representing session state and configuration.
//

import Foundation

/// Represents the current state of a monitoring session
struct SessionState {
    /// When the session started
    var startTime: Date?

    /// Accumulated usage time in seconds
    var accumulatedSeconds: Int

    /// Whether the session is currently active
    var isActive: Bool

    /// Whether we're in a reward window
    var isInRewardWindow: Bool

    /// When the reward window ends (if applicable)
    var rewardWindowEndTime: Date?

    init() {
        self.startTime = nil
        self.accumulatedSeconds = 0
        self.isActive = false
        self.isInRewardWindow = false
        self.rewardWindowEndTime = nil
    }

    /// Time remaining in the reward window (in seconds)
    var rewardWindowSecondsRemaining: Int {
        guard let endTime = rewardWindowEndTime else { return 0 }
        let remaining = endTime.timeIntervalSince(Date())
        return max(0, Int(remaining))
    }
}

/// Configuration for session limits
struct SessionConfiguration {
    /// Maximum session duration in minutes
    var sessionLimitMinutes: Int

    /// Break window in seconds (how long away = session reset)
    var breakWindowSeconds: Int

    /// Reward window in minutes (free time after solving challenge)
    var rewardWindowMinutes: Int

    /// Default configuration
    static let `default` = SessionConfiguration(
        sessionLimitMinutes: 5,
        breakWindowSeconds: 20,
        rewardWindowMinutes: 2
    )

    /// Session limit in seconds
    var sessionLimitSeconds: Int {
        sessionLimitMinutes * 60
    }

    /// Reward window in seconds
    var rewardWindowSeconds: Int {
        rewardWindowMinutes * 60
    }
}

/// Represents the type of monitoring event
enum MonitoringEvent {
    case sessionStarted
    case sessionLimitReached
    case sessionReset
    case breakDetected
    case rewardWindowStarted
    case rewardWindowEnded
    case shieldApplied
    case shieldRemoved
}

/// Logging helper for debugging
struct MonitoringLog {
    let timestamp: Date
    let event: MonitoringEvent
    let details: String?

    init(_ event: MonitoringEvent, details: String? = nil) {
        self.timestamp = Date()
        self.event = event
        self.details = details
    }

    var description: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeString = formatter.string(from: timestamp)
        if let details = details {
            return "[\(timeString)] \(event): \(details)"
        }
        return "[\(timeString)] \(event)"
    }
}
