//
//  ShieldActionExtension.swift
//  ShieldActionExtension
//
//  Handles user interactions with the shield overlay buttons.
//  When the user taps the primary button on the shield, this extension
//  can open our main app where they can solve the math challenge.
//
//  IMPORTANT: Opening the main app from an extension requires:
//  - The app must have a URL scheme registered
//  - We use the URL scheme to deep-link into the app
//

import ManagedSettingsUI
import ManagedSettings
import Foundation

/// Extension point for shield action handling
class ShieldActionExtension: ShieldActionDelegate {

    // MARK: - Shield Action Handling

    /// Handle primary button tap on application shield
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handleShieldAction(action: action, completionHandler: completionHandler)
    }

    /// Handle primary button tap on category shield
    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handleShieldAction(action: action, completionHandler: completionHandler)
    }

    /// Handle primary button tap on web domain shield
    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        handleShieldAction(action: action, completionHandler: completionHandler)
    }

    // MARK: - Shared Action Handler

    /// Common handler for all shield actions
    private func handleShieldAction(
        action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        switch action {
        case .primaryButtonPressed:
            // User wants to solve the challenge
            // Open our main app via URL scheme

            // Note: Opening URL from extension is limited
            // The .defer response tells the system to open the main app
            // The main app's URL scheme must be registered in Info.plist

            // Mark that shield action was triggered (for the main app to check)
            let persistence = PersistenceManager.shared
            persistence.isShieldActive = true

            // Return .defer to let iOS handle opening our app
            // This requires the app's URL scheme to be properly configured
            completionHandler(.defer)

        case .secondaryButtonPressed:
            // User wants to close the shield overlay (but apps stay blocked)
            completionHandler(.close)

        @unknown default:
            completionHandler(.close)
        }
    }
}

// MARK: - Notes on Shield Actions
/*
 ShieldActionResponse options:

 1. .close
    - Dismisses the shield overlay
    - The app remains shielded (blocked)
    - User can try again later

 2. .defer
    - Dismisses the shield and defers to the system
    - iOS will attempt to open the app that handles the action
    - Requires proper URL scheme configuration

 3. .none
    - Does nothing (shield stays visible)
    - Useful if you need to perform some action before responding

 To enable "Open ScrollBrake" functionality:
 1. Register URL scheme "scrollbrake://" in main app's Info.plist
 2. Handle the URL in the main app's scene delegate or App struct
 3. The .defer response will trigger iOS to open the URL
*/
