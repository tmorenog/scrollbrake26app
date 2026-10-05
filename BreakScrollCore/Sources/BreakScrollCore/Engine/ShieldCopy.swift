import Foundation

/// The words on the system shield. Calm and neutral: no judgement about how
/// the time was spent. `ShieldConfiguration` only allows an icon, a title, a
/// subtitle and two buttons, so that's all this describes.
public struct ShieldCopy: Equatable, Sendable {
    public var title: String
    public var subtitle: String
    public var primaryButton: String
    /// `nil` hides the secondary button.
    public var secondaryButton: String?

    /// What the primary button does, so the Shield Action extension and the
    /// copy can't drift apart.
    public enum PrimaryAction: Equatable, Sendable {
        /// Start (or resume) the pause and challenge in BreakScroll.
        case continueInApp
        /// Nothing to do locally; just close the shielded app.
        case close
    }

    public var primaryAction: PrimaryAction

    /// - Parameters:
    ///   - phase: the matching rule's phase, or `nil` if no rule matched.
    ///   - usageInterval: the matching rule's interval.
    public static func make(phase: InterventionPhase?, usageInterval: TimeInterval?, mode: AppMode?) -> ShieldCopy {
        switch phase {
        case .stopped:
            return ShieldCopy(
                title: "Taking a break",
                subtitle: "Whenever you're ready, you can continue after a short pause and a quick challenge.",
                primaryButton: "Continue",
                secondaryButton: "Close",
                primaryAction: .continueInApp
            )
        case .pausing, .challenge, .arming, .rearmFailed:
            return ShieldCopy(
                title: "Your break is in progress",
                subtitle: "Open BreakScroll to finish your pause and challenge.",
                primaryButton: "Open BreakScroll",
                secondaryButton: "Close",
                primaryAction: .continueInApp
            )
        case .awaitingParent:
            return ShieldCopy(
                title: mode == .familyChild ? "Time to check with a parent" : "That's all for now",
                subtitle: mode == .familyChild
                    ? "You've used today's continuations for this app."
                    : "You've used today's continuations for this app. They reset tomorrow.",
                primaryButton: "OK",
                secondaryButton: nil,
                primaryAction: .close
            )
        case .dailyLimitReached:
            return ShieldCopy(
                title: "Today's limit has been reached",
                subtitle: "This app will be available again tomorrow.",
                primaryButton: "OK",
                secondaryButton: nil,
                primaryAction: .close
            )
        case .shielded, .inactive, .outsideActiveHours, .monitoring, nil:
            let usage = usageInterval.map { "You've been using this app for \(describe($0)). " } ?? ""
            return ShieldCopy(
                title: "Time for a quick break",
                subtitle: usage + "Take a moment before deciding whether you'd like to continue.",
                primaryButton: "Continue",
                secondaryButton: "I'm Done",
                primaryAction: .continueInApp
            )
        }
    }

    /// "15 minutes", "1 minute", "30 seconds" (debug thresholds).
    public static func describe(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        if seconds < 60 {
            return seconds == 1 ? "1 second" : "\(seconds) seconds"
        }
        let minutes = (seconds + 30) / 60
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
}
