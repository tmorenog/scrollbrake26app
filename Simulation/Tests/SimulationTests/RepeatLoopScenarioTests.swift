import BreakScrollCore
import Combine
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import UserNotifications
import XCTest
import os
@testable import BreakScrolliOS

/// The MVP: X minutes → shield → pause → challenge → X more minutes → repeat.
final class RepeatLoopScenarioTests: SimulatedDeviceTestCase {
    @MainActor
    func testMVPLoopRepeatsWithAFreshAllowanceEachTime() async {
        let model = await onboardedModel()
        let social = rule(apps: [tiktok], interval: 120, pause: 10, difficulty: .easy)
        model.save(social)
        device.drain()

        XCTAssertEqual(device.activityNames, [activity(social)])
        XCTAssertEqual(Array(device.thresholds(for: activity(social)).values), [120])
        XCTAssertEqual(device.eventIncludesPastActivity(activity(social)), [false])
        XCTAssertEqual(phase(model, social), .monitoring)

        for cycle in 1...5 {
            // Exactly X minutes of use before the shield, every cycle. If usage
            // from before the re-arm leaked in, the shield would return at once.
            XCTAssertEqual(device.use(tiktok, for: 600), 120, "cycle \(cycle)")
            XCTAssertTrue(isBlocked(tiktok))
            XCTAssertFalse(isBlocked(maps), "only selected apps are shielded")
            XCTAssertEqual(device.use(maps, for: 30), 30)

            let config = shield(for: tiktok)
            XCTAssertEqual(config.title?.text, "Time for a quick break")
            XCTAssertEqual(
                config.subtitle?.text,
                "You've been using this app for 2 minutes. Take a moment before deciding whether you'd like to continue."
            )
            XCTAssertEqual(config.primaryButtonLabel?.text, "Continue")
            XCTAssertEqual(config.secondaryButtonLabel?.text, "I'm Done")

            XCTAssertEqual(tap(.primaryButtonPressed, on: tiktok), .openParentalControlsApp)
            model.setActive(true)
            guard case .pausing(let until, .easy)? = model.activeIntervention?.session.phase else {
                return XCTFail("cycle \(cycle): expected the pause, got \(String(describing: model.activeIntervention))")
            }
            XCTAssertEqual(until.timeIntervalSince(device.now), 10, accuracy: 0.5)

            tick(model, after: 5)
            guard case .pausing = phase(model, social) else { return XCTFail("pause ended early") }
            tick(model, after: 5)
            guard case .challenge = phase(model, social) else { return XCTFail("no challenge after the pause") }

            solveChallenge(model, social, correctly: false)
            guard case .challenge(_, let failed) = phase(model, social) else { return XCTFail() }
            XCTAssertEqual(failed, 1)
            XCTAssertTrue(isBlocked(tiktok), "a wrong answer keeps the shield")

            solveChallenge(model, social)
            XCTAssertEqual(phase(model, social), .monitoring)
            XCTAssertFalse(isBlocked(tiktok))
            XCTAssertNil(model.activeIntervention)
            XCTAssertEqual(model.unlockMessage, "Unlocked for another 2 minutes.")
            XCTAssertEqual(model.session(for: social).continuationsToday, cycle)
            model.setActive(false)
        }

        let summary = model.todaySummary
        XCTAssertEqual(summary.interventions, 5)
        XCTAssertEqual(summary.continued, 5)
        XCTAssertEqual(summary.stopped, 0)
        XCTAssertEqual(summary.allowanceGranted, 600)

        // One arm at setup plus one per unlock, each with a single event.
        let arms = device.startMonitoringLog.filter { $0.activity == activity(social) }
        XCTAssertEqual(arms.count, 6)
        XCTAssertEqual(arms.map(\.events.first), (1...6).map { MonitoringNames.event(ruleID: social.id, generation: $0) })
    }

    @MainActor
    func testReArmDeliversIntervalCallbacksWithoutLosingTheCount() async {
        let model = await onboardedModel()
        let social = rule(apps: [tiktok])
        model.save(social)
        XCTAssertEqual(device.use(tiktok, for: 600), 120)
        completeIntervention(model, social, app: tiktok)
        // Re-arming overwrote an ongoing interval: the simulated system sent
        // intervalDidEnd + intervalDidStart (the worst case). They must be harmless.
        XCTAssertTrue(device.callbackLog.suffix(2).elementsEqual(["intervalDidEnd \(activity(social))", "intervalDidStart \(activity(social))"]))
        XCTAssertEqual(model.session(for: social).continuationsToday, 1)
        XCTAssertFalse(isBlocked(tiktok))
    }

    @MainActor
    func testUsageWhileShieldedNeverCounts() async {
        let model = await onboardedModel()
        let social = rule(apps: [tiktok])
        model.save(social)
        XCTAssertEqual(device.use(tiktok, for: 600), 120)
        // Sitting on the shield for ten minutes, trying again and again.
        for _ in 0..<10 {
            device.sleep(60)
            XCTAssertEqual(device.use(tiktok, for: 60), 0)
        }
        completeIntervention(model, social, app: tiktok)
        XCTAssertEqual(device.use(tiktok, for: 119), 119, "the new allowance is a full 2 minutes")
        XCTAssertFalse(isBlocked(tiktok))
        XCTAssertEqual(device.use(tiktok, for: 5), 1)
        XCTAssertTrue(isBlocked(tiktok))
    }

    @MainActor
    func testDebugThirtySecondThreshold() async {
        let model = await onboardedModel()
        let quick = rule(apps: [tiktok], interval: 30, pause: 3)
        model.save(quick)
        XCTAssertEqual(device.use(tiktok, for: 100), 30)
        XCTAssertEqual(shield(for: tiktok).subtitle?.text.hasPrefix("You've been using this app for 30 seconds."), true)
        completeIntervention(model, quick, app: tiktok)
        XCTAssertEqual(device.use(tiktok, for: 100), 30)
    }

    @MainActor
    func testCategorySelectionCombinesItsApps() async {
        let model = await onboardedModel()
        let social = rule(apps: [], categories: ["social"])
        model.save(social)
        XCTAssertEqual(device.use(tiktok, for: 60), 60)
        XCTAssertEqual(device.use(instagram, for: 100), 60, "TikTok and Instagram share the category's allowance")
        XCTAssertTrue(isBlocked(tiktok))
        XCTAssertTrue(isBlocked(instagram))
        XCTAssertFalse(isBlocked(youtube))
        XCTAssertEqual(shield(for: instagram).title?.text, "Time for a quick break")

        var response: ShieldActionResponse?
        ShieldActionExtension().handle(action: .primaryButtonPressed, for: instagram.category!) { response = $0 }
        XCTAssertEqual(response, .openParentalControlsApp)
        guard case .pausing = phase(model, social) else { return XCTFail("category tap didn't continue") }
    }
}
