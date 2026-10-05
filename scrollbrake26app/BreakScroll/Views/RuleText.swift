//
//  RuleText.swift
//  BreakScroll
//
//  Plain-language descriptions of rules, shared by several screens.
//

import Foundation
import BreakScrollCore

enum RuleText {
    /// "15 minutes at a time"
    static func interval(_ rule: InterventionRule) -> String {
        "\(ShieldCopy.describe(rule.usageInterval)) at a time"
    }

    /// "Then a 30-second pause and a quick challenge"
    static func intervention(_ rule: InterventionRule) -> String {
        if rule.escalationPolicy.isEnabled {
            return "Then a pause and a challenge that get longer each time"
        }
        let pause = rule.pauseDuration > 0 ? "a \(pauseAdjective(rule.pauseDuration)) pause" : nil
        let challenge = rule.challengeDifficulty == .none ? nil : "a quick challenge"
        switch (pause, challenge) {
        case let (pause?, challenge?): return "Then \(pause) and \(challenge)"
        case let (pause?, nil): return "Then \(pause)"
        case let (nil, challenge?): return "Then \(challenge)"
        case (nil, nil): return "Then a moment to decide"
        }
    }

    /// "30-second", "2-minute"
    static func pauseAdjective(_ seconds: TimeInterval) -> String {
        let value = Int(seconds)
        return value < 60 ? "\(value)-second" : "\(value / 60)-minute"
    }

    static func pauseLabel(_ seconds: TimeInterval) -> String {
        seconds == 0 ? "No pause" : ShieldCopy.describe(seconds)
    }

    static func difficulty(_ difficulty: ChallengeDifficulty) -> String {
        switch difficulty {
        case .none: return "None"
        case .easy: return "Easy math"
        case .medium: return "Medium math"
        case .hard: return "Hard math"
        }
    }

    static func status(_ phase: InterventionPhase, enabled: Bool, mode: AppMode?) -> String {
        guard enabled else { return "Off" }
        switch phase {
        case .inactive: return "Off"
        case .outsideActiveHours: return "Outside active hours"
        case .arming, .monitoring: return "On"
        case .shielded, .pausing, .challenge, .rearmFailed: return "Break in progress"
        case .stopped: return "Taking a break"
        case .awaitingParent: return mode == .familyChild ? "Ask a parent for more time" : "Done for today"
        case .dailyLimitReached: return "Today's limit reached"
        }
    }

    static func validation(_ error: InterventionRule.ValidationError) -> String {
        switch error {
        case .emptyName: return "Give this rule a name."
        case .usageIntervalOutOfRange: return "Choose how long apps can be used between breaks."
        case .negativePause: return "The pause can't be negative."
        case .invalidMaxContinuations: return "The number of continuations can't be negative."
        case .dailyLimitShorterThanInterval: return "The daily maximum must be at least as long as one session."
        case .schedule(.noActiveDays): return "Choose at least one day."
        case .schedule(.invalidTime): return "Check the start and end times."
        case .schedule(.intervalTooShort): return "Active hours must be at least 15 minutes long."
        }
    }
}
