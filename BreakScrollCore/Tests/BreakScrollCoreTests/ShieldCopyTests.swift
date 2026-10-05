import XCTest
@testable import BreakScrollCore

final class ShieldCopyTests: XCTestCase {
    func testThresholdShieldOffersAChoice() {
        let copy = ShieldCopy.make(phase: .shielded(since: Date()), usageInterval: 900, mode: .familyChild)
        XCTAssertEqual(copy.title, "Time for a quick break")
        XCTAssertEqual(
            copy.subtitle,
            "You've been using this app for 15 minutes. Take a moment before deciding whether you'd like to continue."
        )
        XCTAssertEqual(copy.primaryButton, "Continue")
        XCTAssertEqual(copy.secondaryButton, "I'm Done")
        XCTAssertEqual(copy.primaryAction, .continueInApp)
    }

    func testBlockedPhasesOnlyClose() {
        for phase in [InterventionPhase.dailyLimitReached(since: Date()), .awaitingParent(reason: .maxContinuationsReached, since: Date())] {
            let copy = ShieldCopy.make(phase: phase, usageInterval: 900, mode: .selfControl)
            XCTAssertEqual(copy.primaryAction, .close)
            XCTAssertNil(copy.secondaryButton)
        }
    }

    func testParentWordingOnlyInFamilyMode() {
        let phase = InterventionPhase.awaitingParent(reason: .escalationStage, since: Date())
        XCTAssertEqual(ShieldCopy.make(phase: phase, usageInterval: nil, mode: .familyChild).title, "Time to check with a parent")
        XCTAssertEqual(ShieldCopy.make(phase: phase, usageInterval: nil, mode: .selfControl).title, "That's all for now")
    }

    func testCopyStaysNeutral() {
        let phases: [InterventionPhase?] = [
            nil, .shielded(since: Date()), .stopped(at: Date()), .pausing(until: Date(), difficulty: .easy),
            .rearmFailed(.continuation), .awaitingParent(reason: .escalationStage, since: Date()),
            .dailyLimitReached(since: Date()),
        ]
        for phase in phases {
            for mode in [AppMode.selfControl, .familyChild] {
                let copy = ShieldCopy.make(phase: phase, usageInterval: 900, mode: mode)
                let text = [copy.title, copy.subtitle].joined(separator: " ").lowercased()
                for word in ["wast", "bad", "too much", "addict"] {
                    XCTAssertFalse(text.contains(word), "\(word) in: \(text)")
                }
            }
        }
    }

    func testDurations() {
        XCTAssertEqual(ShieldCopy.describe(30), "30 seconds")
        XCTAssertEqual(ShieldCopy.describe(60), "1 minute")
        XCTAssertEqual(ShieldCopy.describe(900), "15 minutes")
        XCTAssertEqual(ShieldCopy.describe(150), "3 minutes")
    }
}
