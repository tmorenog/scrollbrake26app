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

final class EdgeCaseScenarioTests: SimulatedDeviceTestCase {
    // MARK: Stop vs continue

    @MainActor
    func testImDoneOnTheShieldKeepsAppsPausedUntilChosen() async {
        let model = await onboardedModel()
        let social = rule(apps: [tiktok])
        model.save(social)
        device.use(tiktok, for: 600)

        XCTAssertEqual(tap(.secondaryButtonPressed, on: tiktok), .close)
        XCTAssertEqual(phase(model, social), .stopped(at: device.now))
        XCTAssertTrue(isBlocked(tiktok))
        XCTAssertNil(model.activeIntervention, "I'm Done doesn't pull BreakScroll over the screen")
        XCTAssertEqual(shield(for: tiktok).title?.text, "Taking a break")

        device.sleep(3600)
        XCTAssertEqual(device.use(tiktok, for: 10), 0)
        completeIntervention(model, social, app: tiktok)
        XCTAssertFalse(isBlocked(tiktok))
        XCTAssertEqual(model.todaySummary.stopped, 1)
        XCTAssertEqual(model.todaySummary.continued, 1)
    }

    @MainActor
    func testOpeningBreakScrollDirectlyShowsTheDecision() async {
        let model = await onboardedModel()
        let social = rule(apps: [tiktok])
        model.save(social)
        device.use(tiktok, for: 600)
        model.setActive(true)
        guard case .shielded? = model.activeIntervention?.session.phase else {
            return XCTFail("expected the decision screen")
        }
        model.send(.chooseContinue, to: social)
        guard case .pausing = phase(model, social) else { return XCTFail() }
    }

    // MARK: Crash and relaunch

    @MainActor
    func testAppKilledDuringPauseResumesFromTheAppGroup() async {
        var model: AppModel? = await onboardedModel()
        let social = rule(apps: [tiktok], pause: 30)
        model!.save(social)
        device.use(tiktok, for: 600)
        tap(.primaryButtonPressed, on: tiktok)
        model!.setActive(true)
        tick(model!, after: 10)
        model = nil  // process killed 10 seconds into the pause
        XCTAssertEqual(FakeTimers.activeCount, 0)

        let relaunched = AppModel()
        relaunched.setActive(true)
        guard case .pausing = relaunched.activeIntervention?.session.phase else {
            return XCTFail("pause lost after relaunch")
        }
        tick(relaunched, after: 20)
        solveChallenge(relaunched, social)
        XCTAssertFalse(isBlocked(tiktok))
    }

    @MainActor
    func testCorruptStateFileIsSetAsideNotFatal() async {
        try? Data("not json".utf8).write(to: SharedStore.shared.fileURL)
        let state = SharedStore.shared.read()
        XCTAssertEqual(state, SharedState())
        XCTAssertTrue(FileManager.default.fileExists(atPath: Self.containerURL.appendingPathComponent("state.corrupt.json").path))
        XCTAssertTrue(FakeLog.lines.contains { $0.contains("FAULT") && $0.contains("unreadable") })
    }

    // MARK: Failures never fail open

    @MainActor
    func testReArmFailureKeepsTheShieldUntilRetrySucceeds() async {
        let model = await onboardedModel()
        let social = rule(apps: [tiktok], pause: 0)
        model.save(social)
        device.use(tiktok, for: 600)
        tap(.primaryButtonPressed, on: tiktok)
        model.setActive(true)

        device.failNextStartMonitoring = 1
        solveChallenge(model, social)
        XCTAssertEqual(phase(model, social), .rearmFailed(.continuation))
        XCTAssertTrue(isBlocked(tiktok), "failed re-arm must not unlock")
        guard case .rearmFailed? = model.activeIntervention?.session.phase else { return XCTFail() }

        model.send(.retryArm, to: social)
        device.drain()
        XCTAssertEqual(phase(model, social), .monitoring)
        XCTAssertFalse(isBlocked(tiktok))
        XCTAssertEqual(device.use(tiktok, for: 600), 120)
    }

    @MainActor
    func testEmptySelectionIsNeverMonitoredAsAllActivity() async {
        let model = await onboardedModel()
        let empty = rule(apps: [])
        model.save(empty)
        device.drain()
        XCTAssertTrue(device.startMonitoringLog.isEmpty, "an empty event would count ALL device use")
        XCTAssertEqual(phase(model, empty), .inactive)
        XCTAssertEqual(device.use(maps, for: 1000), 1000)
        XCTAssertTrue(FakeLog.lines.contains { $0.contains("arm failed") })
    }

    @MainActor
    func testDuplicateAndStaleThresholdCallbacksAreIgnored() async {
        let model = await onboardedModel()
        let social = rule(apps: [tiktok])
        model.save(social)
        device.use(tiktok, for: 600)
        let monitor = DeviceActivityMonitorExtension()
        let gen1 = DeviceActivityEvent.Name(MonitoringNames.event(ruleID: social.id, generation: 1))
        let name = DeviceActivityName(activity(social))
        monitor.eventDidReachThreshold(gen1, activity: name)  // duplicate while shielded
        model.refresh()
        XCTAssertEqual(model.todaySummary.interventions, 1)

        completeIntervention(model, social, app: tiktok)
        monitor.eventDidReachThreshold(gen1, activity: name)  // late, from before the re-arm
        XCTAssertFalse(isBlocked(tiktok))
        model.refresh()
        XCTAssertEqual(model.todaySummary.interventions, 1)

        monitor.eventDidReachThreshold(DeviceActivityEvent.Name("com.scrollbrake.sessionLimitReached"), activity: name)
        XCTAssertFalse(isBlocked(tiktok), "unknown events are ignored")
    }

    // MARK: Schedules and days

    @MainActor
    func testLeavingActiveHoursLiftsTheShieldAndTheNextMorningStartsFresh() async {
        device.reset(now: date(day: 5, hour: 22, minute: 25), calendar: calendar)
        let model = await onboardedModel()
        let social = rule(apps: [tiktok], schedule: .daytime)  // 7:00–22:30
        model.save(social)
        XCTAssertEqual(device.use(tiktok, for: 600), 120)
        XCTAssertTrue(isBlocked(tiktok))

        device.sleep(240)  // 22:31
        device.wake()
        XCTAssertEqual(phase(model, social), .outsideActiveHours)
        XCTAssertFalse(isBlocked(tiktok))
        XCTAssertEqual(device.use(tiktok, for: 1800), 1800, "no interruptions outside active hours")

        device.now = date(day: 6, hour: 7, minute: 5)
        XCTAssertEqual(device.use(tiktok, for: 600), 120)
        XCTAssertTrue(isBlocked(tiktok))
        model.refresh()
        XCTAssertEqual(model.session(for: social).dayKey, "2026-10-06")
    }

    @MainActor
    func testWeekdayOnlyRuleDoesNotInterruptOnSaturday() async {
        device.reset(now: date(day: 10, hour: 10), calendar: calendar)  // Saturday
        let model = await onboardedModel()
        let school = rule(apps: [tiktok], schedule: WeeklySchedule(activeDays: Weekday.weekdays, start: TimeOfDay(hour: 7), end: TimeOfDay(hour: 22)))
        model.save(school)
        XCTAssertEqual(device.use(tiktok, for: 600), 600)
        XCTAssertFalse(isBlocked(tiktok))
        XCTAssertEqual(phase(model, school), .monitoring)

        device.now = date(day: 12, hour: 10)  // Monday
        XCTAssertEqual(device.use(tiktok, for: 600), 120)
    }

    @MainActor
    func testMidnightResetsTheDaysContinuations() async {
        device.reset(now: date(day: 5, hour: 23, minute: 40), calendar: calendar)
        let model = await onboardedModel()
        let social = rule(apps: [tiktok], schedule: .always, maxContinuations: 1)
        model.save(social)

        device.use(tiktok, for: 600)
        completeIntervention(model, social, app: tiktok)
        device.use(tiktok, for: 600)
        XCTAssertEqual(tap(.primaryButtonPressed, on: tiktok), .openParentalControlsApp)
        XCTAssertEqual(phase(model, social), .awaitingParent(reason: .maxContinuationsReached, since: device.now))
        XCTAssertEqual(shield(for: tiktok).title?.text, "That's all for now")
        XCTAssertEqual(tap(.primaryButtonPressed, on: tiktok), .close)

        device.now = date(day: 6, hour: 0, minute: 5)
        device.wake()
        model.refresh()
        XCTAssertEqual(model.session(for: social).continuationsToday, 0)
        XCTAssertEqual(shield(for: tiktok).title?.text, "Time for a quick break")
        completeIntervention(model, social, app: tiktok)
        XCTAssertFalse(isBlocked(tiktok))
    }

    @MainActor
    func testDailyMaximumCannotBeSolvedAwayAndLiftsTomorrow() async {
        let model = await onboardedModel()
        let capped = rule(apps: [tiktok], interval: 120, dailyLimit: 300)
        model.save(capped)
        XCTAssertEqual(device.eventIncludesPastActivity(MonitoringNames.dailyLimitActivity(ruleID: capped.id)), [true])

        XCTAssertEqual(device.use(tiktok, for: 600), 120)
        completeIntervention(model, capped, app: tiktok)
        XCTAssertEqual(device.use(tiktok, for: 600), 120)
        completeIntervention(model, capped, app: tiktok)
        XCTAssertEqual(device.use(tiktok, for: 600), 60, "the 5-minute daily cap arrives first")
        XCTAssertEqual(phase(model, capped), .dailyLimitReached(since: device.now))
        XCTAssertEqual(shield(for: tiktok).title?.text, "Today's limit has been reached")
        XCTAssertEqual(tap(.primaryButtonPressed, on: tiktok), .close)
        XCTAssertNil(model.activeIntervention)

        device.now = date(day: 6, hour: 9)
        device.wake()
        XCTAssertEqual(phase(model, capped), .monitoring)
        XCTAssertFalse(isBlocked(tiktok))
        XCTAssertEqual(device.use(tiktok, for: 600), 120)
    }

    // MARK: Multiple rules

    @MainActor
    func testTwoRulesShieldAndUnlockIndependently() async {
        let model = await onboardedModel()
        let short = rule("Short videos", apps: [tiktok], interval: 120)
        let photos = rule("Photos", apps: [instagram], interval: 180)
        model.save(short)
        model.save(photos)

        XCTAssertEqual(device.use(tiktok, for: 600), 120)
        XCTAssertFalse(isBlocked(instagram))
        XCTAssertEqual(device.use(instagram, for: 600), 180)
        XCTAssertTrue(isBlocked(tiktok) && isBlocked(instagram))
        XCTAssertEqual(shield(for: instagram).subtitle?.text.contains("3 minutes"), true)

        completeIntervention(model, short, app: tiktok)
        XCTAssertFalse(isBlocked(tiktok))
        XCTAssertTrue(isBlocked(instagram), "unlocking one rule leaves the other alone")
        XCTAssertEqual(phase(model, photos), .shielded(since: device.now.addingTimeInterval(-10)))
    }

    // MARK: Settings changes

    @MainActor
    func testEditingAnIntervalReArmsWithTheNewValue() async {
        let model = await onboardedModel()
        var social = rule(apps: [tiktok], interval: 120)
        model.save(social)
        device.use(tiktok, for: 60)

        social.usageInterval = 300
        model.save(social)
        XCTAssertEqual(model.rules.first?.version, 2)
        XCTAssertEqual(Array(device.thresholds(for: activity(social)).values), [300])
        XCTAssertEqual(device.use(tiktok, for: 600), 300)
    }

    @MainActor
    func testEditingDuringABreakKeepsTheShield() async {
        let model = await onboardedModel()
        var social = rule(apps: [tiktok], interval: 120)
        model.save(social)
        XCTAssertEqual(device.use(tiktok, for: 600), 120)

        social.usageInterval = 300
        model.save(social)
        XCTAssertTrue(isBlocked(tiktok), "editing must not be a way around a break")
        guard case .shielded = phase(model, social) else { return XCTFail("\(phase(model, social))") }

        completeIntervention(model, social, app: tiktok)
        XCTAssertEqual(device.use(tiktok, for: 600), 300, "the new interval applies from the next allowance")
    }

    @MainActor
    func testOpeningTheAppRecoversAMissedIntervalStart() async {
        device.reset(now: date(day: 5, hour: 22, minute: 35), calendar: calendar)
        let model = await onboardedModel()
        let social = rule(apps: [tiktok], schedule: .daytime)
        model.save(social)
        device.drain()
        XCTAssertEqual(phase(model, social), .monitoring)
        device.wake()

        // Next morning the extension's intervalDidStart never arrives.
        let monitor = device.makeMonitor
        device.makeMonitor = nil
        device.now = date(day: 6, hour: 6, minute: 0)
        device.wake()
        device.makeMonitor = monitor
        DeviceActivityMonitorExtension().intervalDidEnd(for: DeviceActivityName(activity(social)))
        XCTAssertEqual(phase(model, social), .outsideActiveHours)
        device.now = date(day: 6, hour: 9)
        device.makeMonitor = nil
        device.wake()  // 07:00 start delivered to nobody
        device.makeMonitor = monitor
        XCTAssertEqual(phase(model, social), .outsideActiveHours)

        model.setActive(true)  // the person opens BreakScroll
        XCTAssertEqual(phase(model, social), .monitoring)
        model.setActive(false)
        XCTAssertEqual(device.use(tiktok, for: 600), 120)
    }

    @MainActor
    func testATransientAuthorizationStatusDoesNotLiftShields() async {
        let model = await onboardedModel()
        let social = rule(apps: [tiktok])
        model.save(social)
        device.use(tiktok, for: 600)
        AuthorizationCenter.shared.authorizationStatus = .notDetermined
        AuthorizationCenter.shared.authorizationStatus = .approved
        XCTAssertTrue(isBlocked(tiktok))
        guard case .shielded = phase(model, social) else { return XCTFail() }
    }

    @MainActor
    func testDisablingARuleRemovesItsShieldAndMonitoring() async {
        let model = await onboardedModel()
        var social = rule(apps: [tiktok])
        model.save(social)
        device.use(tiktok, for: 600)
        social.enabled = false
        model.save(social)
        XCTAssertFalse(isBlocked(tiktok))
        XCTAssertTrue(device.activityNames.isEmpty)
        XCTAssertEqual(device.use(tiktok, for: 600), 600)
    }

    @MainActor
    func testAuthorizationRevokedStopsEverything() async {
        let model = await onboardedModel()
        let social = rule(apps: [tiktok])
        model.save(social)
        device.use(tiktok, for: 600)
        XCTAssertTrue(isBlocked(tiktok))

        AuthorizationCenter.shared.authorizationStatus = .denied  // a parent turned it off in Settings
        device.isAuthorized = false
        XCTAssertFalse(model.isAuthorized)
        XCTAssertFalse(isBlocked(tiktok))
        XCTAssertTrue(device.activityNames.isEmpty)
        XCTAssertEqual(phase(model, social), .inactive)
    }

    @MainActor
    func testDeleteAllDataLeavesNothingBehind() async {
        let model = await onboardedModel()
        model.save(rule(apps: [tiktok]))
        model.save(rule("Video", apps: [youtube], dailyLimit: 600))
        device.use(tiktok, for: 600)
        model.deleteAllData()
        XCTAssertTrue(model.rules.isEmpty)
        XCTAssertTrue(model.state.records.isEmpty)
        XCTAssertTrue(FakeShields.activeStoreNames.isEmpty)
        XCTAssertTrue(device.activityNames.isEmpty)
        XCTAssertEqual(model.mode, .selfControl, "the chosen setup survives")
    }
}
