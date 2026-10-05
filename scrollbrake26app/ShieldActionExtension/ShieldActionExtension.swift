//
//  ShieldActionExtension.swift
//  ShieldActionExtension
//
//  Handles the shield's buttons:
//  - Primary ("Continue"): starts the pause in the engine, then opens
//    BreakScroll on iOS 26.5+ (`.openParentalControlsApp`). Earlier iOS can't
//    open the app from here, so we post a local notification that opens it
//    and close the shielded app. See SCREEN_TIME_FEASIBILITY.md Q8.
//  - Secondary ("I'm Done"): records the choice and closes the app; the
//    shield stays up.
//

import Foundation
import ManagedSettings
import UserNotifications
import BreakScrollCore

class ShieldActionExtension: ShieldActionDelegate {
    private let coordinator = InterventionCoordinator()

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action, completionHandler: completionHandler) { $0.contains(application) }
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action, completionHandler: completionHandler) { $0.contains(webDomain) }
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handle(action, completionHandler: completionHandler) { $0.contains(category) }
    }

    private func handle(
        _ action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void,
        matching matches: (FamilyActivitySelectionProbe) -> Bool
    ) {
        let state = SharedStore.shared.read()
        let ruleIDs = coordinator.shieldedRuleIDs(in: state, matching: matches)

        switch action {
        case .primaryButtonPressed:
            let copy = ShieldCopy.make(
                phase: ruleIDs.first.map { state.session(for: $0).phase },
                usageInterval: nil,
                mode: state.mode
            )
            guard copy.primaryAction == .continueInApp else {
                completionHandler(.close)
                return
            }
            for ruleID in ruleIDs {
                coordinator.send(.chooseContinue, ruleID: ruleID)
            }
            openBreakScroll(completionHandler)

        case .secondaryButtonPressed:
            for ruleID in ruleIDs {
                coordinator.send(.chooseDone, ruleID: ruleID)
            }
            completionHandler(.close)

        default:
            // Submenu items (iOS 26.4+) are reserved for "Ask a parent" (Phase 11).
            completionHandler(.close)
        }
    }

    private func openBreakScroll(_ completionHandler: @escaping (ShieldActionResponse) -> Void) {
        if #available(iOS 26.5, *) {
            completionHandler(.openParentalControlsApp)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Your break has started"
        content.body = "Tap to open BreakScroll and finish your pause."
        let request = UNNotificationRequest(identifier: "breakscroll.continue", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.shield.error("notification failed: \(error.localizedDescription, privacy: .public)")
            }
            completionHandler(.close)
        }
    }
}
