//
//  AppModel.swift
//  BreakScroll
//
//  The app's view model. State shared with the extensions lives in the App
//  Group (SharedStore); this object reloads it and sends engine inputs through
//  InterventionCoordinator, the same path the extensions use.
//

import Combine
import FamilyControls
import Foundation
import UserNotifications
import BreakScrollCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state = SharedState()
    @Published private(set) var authorizationStatus: AuthorizationStatus
    @Published var authorizationError: String?
    /// Shown briefly on Home after an unlock, e.g. "Unlocked for another 15 minutes."
    @Published var unlockMessage: String?

    private let store = SharedStore.shared
    private let coordinator = InterventionCoordinator()
    private var cancellables = Set<AnyCancellable>()
    private var ticker: AnyCancellable?

    init() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        state = store.read()
        AuthorizationCenter.shared.$authorizationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.authorizationChanged(to: status) }
            .store(in: &cancellables)
    }

    // MARK: - Mode and authorization

    var mode: AppMode? { state.mode }
    var isAuthorized: Bool { authorizationStatus == .approved }

    /// Rules are only editable behind the parent passcode on a child's phone.
    var requiresPasscodeToEdit: Bool { mode == .familyChild }

    func choose(_ mode: AppMode) {
        store.mutate { $0.mode = mode }
        refresh()
    }

    /// Only offered before authorization succeeds.
    func resetMode() {
        store.mutate { $0.mode = nil }
        refresh()
    }

    func requestAuthorization() async {
        guard let mode, mode != .familyParent else { return }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: mode == .familyChild ? .child : .individual)
            authorizationError = nil
            await requestNotificationPermissionIfNeeded()
        } catch {
            authorizationError = Self.describe(error)
            Log.app.error("authorization failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func authorizationChanged(to status: AuthorizationStatus) {
        let wasAuthorized = authorizationStatus == .approved
        authorizationStatus = status
        // Revoking authorization voids every token (FamilyActivitySelection
        // docs), so the stored selections are useless now.
        // Only an explicit .denied counts; a transient status must not lift shields.
        if wasAuthorized && status == .denied {
            Log.app.notice("authorization revoked; stopping all rules")
            stopAll()
        }
    }

    /// Below iOS 26.5 the shield can't open BreakScroll, so the shield action
    /// posts a notification instead (SCREEN_TIME_FEASIBILITY.md Q8).
    private func requestNotificationPermissionIfNeeded() async {
        if #available(iOS 26.5, *) { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func describe(_ error: Error) -> String {
        guard let error = error as? FamilyControlsError else {
            return "Screen Time access couldn't be turned on. Please try again."
        }
        switch error {
        case .invalidAccountType:
            return "This iPhone needs to be signed in to iCloud with a child account in a Family Sharing group."
        case .authorizationConflict:
            return "Another app already manages Screen Time controls on this iPhone."
        case .authorizationCanceled:
            return "Setup was cancelled."
        case .restricted:
            return "Screen Time restrictions on this iPhone prevent BreakScroll from being set up."
        case .networkError:
            return "BreakScroll couldn't reach Apple. Check the connection and try again."
        case .unavailable:
            return "Screen Time controls aren't available on this iPhone."
        default:
            return "Screen Time access couldn't be turned on. Please try again."
        }
    }

    // MARK: - Rules

    var rules: [InterventionRule] { state.rules }

    func session(for rule: InterventionRule) -> InterventionSession {
        state.session(for: rule.id)
    }

    /// Saves a rule and restarts its monitoring with the new settings.
    func save(_ edited: InterventionRule) {
        var rule = edited
        rule.updatedAt = AppClock.now()
        rule.updatedBy = mode?.rawValue ?? "local"
        store.mutate { state in
            guard let existing = state.rule(rule.id) else {
                state.upsert(rule)
                if rule.enabled { coordinator.apply(.start, ruleID: rule.id, state: &state) }
                return
            }
            rule.version = existing.version + 1
            // Mid-break edits must not lift the shield (that would be an easy way
            // around it). The new settings apply when the next allowance is armed.
            if rule.enabled, existing.enabled, state.session(for: rule.id).phase.isShielded {
                state.upsert(rule)
                return
            }
            coordinator.apply(.stop, ruleID: rule.id, state: &state)
            state.upsert(rule)
            if rule.enabled {
                coordinator.apply(.start, ruleID: rule.id, state: &state)
            }
        }
        refresh()
    }

    func delete(_ rule: InterventionRule) {
        store.mutate { state in
            coordinator.apply(.stop, ruleID: rule.id, state: &state)
            state.removeRule(rule.id)
        }
        refresh()
    }

    func stopAll() {
        store.mutate { state in
            for rule in state.rules {
                coordinator.apply(.stop, ruleID: rule.id, state: &state)
            }
        }
        refresh()
    }

    /// "Delete BreakScroll Data": stops enforcement and removes rules and history.
    func deleteAllData() {
        store.mutate { state in
            for rule in state.rules {
                coordinator.apply(.stop, ruleID: rule.id, state: &state)
            }
            let mode = state.mode
            state = SharedState()
            state.mode = mode
        }
        refresh()
    }

    // MARK: - Interventions

    func send(_ input: InterventionInput, to rule: InterventionRule) {
        let before = session(for: rule)
        coordinator.send(input, ruleID: rule.id)
        refresh()
        let after = session(for: rule)
        if after.continuationsToday > before.continuationsToday {
            unlockMessage = "Unlocked for another \(ShieldCopy.describe(rule.usageInterval))."
        }
    }

    /// The rule whose pause or challenge should cover the app, if any.
    var activeIntervention: (rule: InterventionRule, session: InterventionSession)? {
        for rule in rules {
            let current = session(for: rule)
            switch current.phase {
            case .shielded, .pausing, .challenge, .rearmFailed, .arming(.continuation):
                return (rule, current)
            default:
                continue
            }
        }
        return nil
    }

    var todaySummary: DailySummary {
        let today = WeeklySchedule.dayKey(for: AppClock.now(), calendar: AppClock.calendar())
        let intervals = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0.usageInterval) })
        return DailySummary.summarize(state.records.filter { $0.dayKey == today }) { intervals[$0] }
            .first ?? DailySummary(dayKey: today)
    }

    // MARK: - Lifecycle

    func refresh() {
        let latest = store.read()
        if latest != state {
            state = latest
        }
    }

    /// While the app is in the foreground, reload once a second (extensions
    /// write the same file) and move finished pauses on to the challenge.
    func setActive(_ active: Bool) {
        ticker = nil
        guard active else { return }
        // Also recovers a missed intervalDidStart: inside active hours, a rule
        // left "outside active hours" goes back to monitoring.
        let now = AppClock.now()
        for rule in rules where rule.enabled {
            let inHours = rule.activeSchedule.isActive(at: now, calendar: AppClock.calendar())
            coordinator.send(inHours ? .intervalStarted : .refresh, ruleID: rule.id)
        }
        refresh()
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.tick() }
    }

    private func tick() {
        refresh()
        let now = AppClock.now()
        for rule in rules {
            if case .pausing(let until, _) = session(for: rule).phase, now >= until {
                send(.pauseElapsed, to: rule)
            }
        }
    }
}
