import BreakScrollCore
import Combine
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import ManagedSettingsUI
import UserNotifications
import XCTest
import os
@testable import BreakScrolliOS

/// Shared setup for scenarios on the simulated iPhone. Each test starts at
/// Monday 2026-10-05 09:00 in Los Angeles with an empty App Group.
class SimulatedDeviceTestCase: XCTestCase {
    static let containerURL = FileManager.default.temporaryDirectory.appendingPathComponent("breakscroll-sim")

    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    let tiktok = FakeApp("tiktok", category: "social")
    let instagram = FakeApp("instagram", category: "social")
    let youtube = FakeApp("youtube", category: "entertainment")
    let maps = FakeApp("maps", category: "navigation")

    var device: FakeDevice { FakeDevice.shared }

    override func setUp() {
        super.setUp()
        resetSimulatedDevice()
    }

    /// A factory-fresh iPhone: empty App Group, no shields, no monitoring.
    func resetSimulatedDevice() {
        try? FileManager.default.removeItem(at: Self.containerURL)
        try? FileManager.default.createDirectory(at: Self.containerURL, withIntermediateDirectories: true)
        FakeAppGroup.containerURL = Self.containerURL
        precondition(SharedStore.shared.fileURL.deletingLastPathComponent().path == Self.containerURL.path)

        FakeShields.reset()
        device.reset(now: date(day: 5, hour: 9), calendar: calendar)
        device.makeMonitor = { DeviceActivityMonitorExtension() }
        AppClock.now = { FakeDevice.shared.now }
        let calendar = self.calendar
        AppClock.calendar = { calendar }
        AuthorizationCenter.shared.reset()
        FakeTimers.handlers = [:]
        UNUserNotificationCenter.current().delivered = []
        NSFileCoordinator.nestedCoordinations = 0
        FakeLog.lines = []
    }

    override func tearDown() {
        XCTAssertEqual(NSFileCoordinator.nestedCoordinations, 0, "nested file coordination can deadlock on iOS")
        super.tearDown()
    }

    // MARK: - Builders

    func date(day: Int, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    func selection(_ apps: [FakeApp], categories: [String] = []) -> Data {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = Set(apps.map(\.token))
        selection.categoryTokens = Set(categories.map { ActivityCategoryToken($0) })
        return SelectionCoder.encode(selection)
    }

    func rule(
        _ name: String = "Social",
        apps: [FakeApp],
        categories: [String] = [],
        interval: TimeInterval = 120,
        pause: TimeInterval = 10,
        difficulty: ChallengeDifficulty = .easy,
        escalation: EscalationPolicy = .none,
        schedule: WeeklySchedule = .daytime,
        maxContinuations: Int? = nil,
        dailyLimit: TimeInterval? = nil
    ) -> InterventionRule {
        InterventionRule(
            name: name, selectionData: selection(apps, categories: categories), usageInterval: interval,
            pauseDuration: pause, challengeDifficulty: difficulty, escalationPolicy: escalation,
            activeSchedule: schedule, maxContinuations: maxContinuations, dailyLimit: dailyLimit
        )
    }

    /// Onboarding: choose a mode and grant Screen Time access.
    @MainActor
    func onboardedModel(_ mode: AppMode = .selfControl) async -> AppModel {
        let model = AppModel()
        model.choose(mode)
        await model.requestAuthorization()
        XCTAssertTrue(model.isAuthorized)
        return model
    }

    // MARK: - Interactions

    @MainActor
    func phase(_ model: AppModel, _ rule: InterventionRule) -> InterventionPhase {
        model.refresh()
        return model.session(for: rule).phase
    }

    func isBlocked(_ app: FakeApp) -> Bool {
        FakeShields.isBlocked(app: app.token, category: app.category)
    }

    /// What the system shield shows when `app` is opened, via the real extension.
    func shield(for app: FakeApp) -> ShieldConfiguration {
        let ext = ShieldConfigurationExtension()
        let blockedDirectly = FakeShields.stores.values.contains { $0.applications?.contains(app.token) == true }
        if !blockedDirectly, let category = app.category {
            return ext.configuration(shielding: Application(token: app.token), in: ActivityCategory(token: category))
        }
        return ext.configuration(shielding: Application(token: app.token))
    }

    /// Taps a shield button, via the real Shield Action extension.
    @discardableResult
    func tap(_ action: ShieldAction, on app: FakeApp) -> ShieldActionResponse? {
        var response: ShieldActionResponse?
        ShieldActionExtension().handle(action: action, for: app.token) { response = $0 }
        device.drain()
        return response
    }

    /// The app is in the foreground and its once-a-second ticker runs.
    @MainActor
    func tick(_ model: AppModel, after seconds: TimeInterval = 1) {
        device.sleep(seconds)
        FakeTimers.fire()
        device.drain()
    }

    @MainActor
    func solveChallenge(_ model: AppModel, _ rule: InterventionRule, correctly: Bool = true) {
        guard case .challenge(let challenge, _) = phase(model, rule) else {
            return XCTFail("expected a challenge, got \(phase(model, rule))")
        }
        model.send(.submitAnswer(String(correctly ? challenge.answer : challenge.answer + 1)), to: rule)
        device.drain()
    }

    /// Shield → Continue → BreakScroll opens → pause → challenge → solved.
    @MainActor
    func completeIntervention(_ model: AppModel, _ rule: InterventionRule, app: FakeApp, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(tap(.primaryButtonPressed, on: app), .openParentalControlsApp, file: file, line: line)
        model.setActive(true)
        guard case .pausing(let until, _) = phase(model, rule) else {
            return XCTFail("expected pause, got \(phase(model, rule))", file: file, line: line)
        }
        tick(model, after: until.timeIntervalSince(device.now))
        solveChallenge(model, rule)
        XCTAssertEqual(phase(model, rule), .monitoring, file: file, line: line)
        model.setActive(false)
    }

    func activity(_ rule: InterventionRule) -> String { MonitoringNames.activity(ruleID: rule.id) }
}
