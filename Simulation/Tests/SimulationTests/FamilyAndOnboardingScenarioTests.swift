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

final class FamilyAndOnboardingScenarioTests: SimulatedDeviceTestCase {
    @MainActor
    func testEachModeRequestsTheRightAuthorization() async {
        let child = AppModel()
        child.choose(.familyChild)
        await child.requestAuthorization()
        XCTAssertEqual(AuthorizationCenter.shared.requestedMembers, [.child])
        XCTAssertTrue(child.requiresPasscodeToEdit)

        AuthorizationCenter.shared.reset()
        let adult = AppModel()
        adult.choose(.selfControl)
        await adult.requestAuthorization()
        XCTAssertEqual(AuthorizationCenter.shared.requestedMembers, [.individual])
        XCTAssertFalse(adult.requiresPasscodeToEdit)

        AuthorizationCenter.shared.reset()
        let parent = AppModel()
        parent.choose(.familyParent)
        await parent.requestAuthorization()
        XCTAssertEqual(AuthorizationCenter.shared.requestedMembers, [], "the parent's own iPhone enforces nothing")
    }

    @MainActor
    func testAuthorizationErrorsAreExplained() async {
        let model = AppModel()
        model.choose(.familyChild)
        AuthorizationCenter.shared.nextError = FamilyControlsError.invalidAccountType
        await model.requestAuthorization()
        XCTAssertFalse(model.isAuthorized)
        XCTAssertEqual(
            model.authorizationError,
            "This iPhone needs to be signed in to iCloud with a child account in a Family Sharing group."
        )
        await model.requestAuthorization()
        XCTAssertTrue(model.isAuthorized)
        XCTAssertNil(model.authorizationError)
    }

    @MainActor
    func testModeSurvivesRelaunchAndCanBeChangedBeforeSetup() async {
        let model = AppModel()
        model.choose(.familyChild)
        XCTAssertEqual(AppModel().mode, .familyChild)
        model.resetMode()
        XCTAssertNil(AppModel().mode)
    }

    @MainActor
    func testEscalatingFrictionOnAChildsPhone() async {
        let model = await onboardedModel(.familyChild)
        let social = rule(apps: [tiktok], interval: 60, escalation: .standard)
        model.save(social)

        var pauses: [TimeInterval] = []
        var difficulties: [ChallengeDifficulty] = []
        for _ in 1...4 {
            XCTAssertEqual(device.use(tiktok, for: 600), 60)
            tap(.primaryButtonPressed, on: tiktok)
            guard case .pausing(let until, let difficulty) = phase(model, social) else { return XCTFail() }
            pauses.append(until.timeIntervalSince(device.now))
            difficulties.append(difficulty)
            model.setActive(true)
            tick(model, after: until.timeIntervalSince(device.now))
            solveChallenge(model, social)
            model.setActive(false)
        }
        XCTAssertEqual(pauses, [20, 30, 60, 120])
        XCTAssertEqual(difficulties, [.easy, .medium, .medium, .hard])

        // Fifth time: local challenges can't unlock; a parent is needed.
        XCTAssertEqual(device.use(tiktok, for: 600), 60)
        XCTAssertEqual(tap(.primaryButtonPressed, on: tiktok), .openParentalControlsApp)
        XCTAssertEqual(phase(model, social), .awaitingParent(reason: .escalationStage, since: device.now))
        let config = shield(for: tiktok)
        XCTAssertEqual(config.title?.text, "Time to check with a parent")
        XCTAssertNil(config.secondaryButtonLabel)
        XCTAssertEqual(tap(.primaryButtonPressed, on: tiktok), .close)
        XCTAssertTrue(isBlocked(tiktok))
    }

    @MainActor
    func testShieldForAnUnmatchedAppUsesNeutralDefaults() async {
        let config = shield(for: maps)
        XCTAssertEqual(config.title?.text, "Time for a quick break")
        XCTAssertEqual(config.subtitle?.text, "Take a moment before deciding whether you'd like to continue.")
    }

    @MainActor
    func testRandomizedMultiDaySoak() async {
        for seed in 1...40 {
            resetSimulatedDevice()
            await soak(seed: UInt64(seed), days: 3)
        }
    }

    /// Three days of random use: two rules (one with a daily cap), random
    /// I'm Done / Continue choices, wrong answers, idle gaps, nights.
    @MainActor
    private func soak(seed: UInt64, days: Int) async {
        let model = await onboardedModel(seed % 2 == 0 ? .selfControl : .familyChild)
        let social = rule("Social", apps: [tiktok, instagram], interval: 300, pause: 20)
        let video = rule("Video", apps: [youtube], interval: 600, pause: 30, difficulty: .hard, dailyLimit: 3600)
        model.save(social)
        model.save(video)

        var generator = SeededGenerator(seed: seed)
        let apps = [tiktok, instagram, youtube, maps]
        var unlocks = 0
        let end = date(day: 5 + days, hour: 0)
        while device.now < end {
            let app = apps[Int.random(in: 0..<apps.count, using: &generator)]
            device.use(app, for: Int.random(in: 10...500, using: &generator))
            let covering = app.token == youtube.token ? video : social
            for rule in [covering] where isBlocked(app) && app.token != maps.token {
                switch phase(model, rule) {
                case .shielded, .stopped:
                    if Int.random(in: 0..<3, using: &generator) == 0 {
                        tap(.secondaryButtonPressed, on: app)
                    } else {
                        tap(.primaryButtonPressed, on: app)
                        model.setActive(true)
                        if case .pausing(let until, _) = phase(model, rule) {
                            tick(model, after: until.timeIntervalSince(device.now))
                        }
                        if Bool.random(using: &generator) { solveChallenge(model, rule, correctly: false) }
                        solveChallenge(model, rule)
                        unlocks += 1
                        model.setActive(false)
                    }
                default:
                    break
                }
            }
            device.sleep(TimeInterval(Int.random(in: 0...(Bool.random(using: &generator) ? 900 : 14_400), using: &generator)))
            device.wake()
            checkInvariants(model, [social, video], seed: seed)
        }
        model.refresh()
        XCTAssertEqual(model.state.records.filter { $0.kind == .unlocked }.count, unlocks, "seed \(seed)")
        let interventions = model.state.records.filter { $0.kind == .intervention }.count
        XCTAssertGreaterThan(interventions, 0, "seed \(seed)")
        XCTAssertLessThanOrEqual(unlocks, interventions, "seed \(seed)")
    }

    @MainActor
    private func checkInvariants(_ model: AppModel, _ rules: [InterventionRule], seed: UInt64) {
        model.refresh()
        for rule in rules {
            let session = model.session(for: rule)
            let where_ = "seed \(seed) \(rule.name) at \(device.now): \(session.phase)"
            let storeBlocks = !(FakeShields.stores["rule.\(rule.id.uuidString)"]?.applications ?? []).isEmpty
            XCTAssertEqual(storeBlocks, session.phase.isShielded, "shield/engine mismatch, \(where_)")

            if session.phase == .monitoring {
                // The system is watching exactly the generation the engine expects.
                XCTAssertEqual(
                    Array(device.thresholds(for: MonitoringNames.activity(ruleID: rule.id)).keys),
                    [MonitoringNames.event(ruleID: rule.id, generation: session.armedGeneration)],
                    "registered event drifted, \(where_)"
                )
            }
            if !rule.activeSchedule.isActive(at: device.now, calendar: calendar), storeBlocks {
                switch session.phase {
                case .dailyLimitReached, .arming(.liftDailyLimit): break
                default: XCTFail("shielded outside active hours, \(where_)")
                }
            }
        }
    }
}
