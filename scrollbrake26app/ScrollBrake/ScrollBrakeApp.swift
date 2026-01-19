//
//  ScrollBrakeApp.swift
//  ScrollBrake
//
//  Main app entry point for ScrollBrake - an app that enforces usage limits
//  on distracting apps using Apple's Screen Time APIs.
//
//  IMPORTANT: This app requires:
//  - iOS 16.0+ (for stable FamilyControls APIs)
//  - Physical device (Screen Time APIs don't work in Simulator)
//  - FamilyControls entitlement (requires Apple Developer account)
//

import SwiftUI
import FamilyControls

@main
struct ScrollBrakeApp: App {
    // Authorization manager handles FamilyControls permission
    @StateObject private var authorizationManager = AuthorizationManager.shared

    // Monitoring manager handles session tracking
    @StateObject private var monitoringManager = MonitoringManager.shared

    // Shield manager handles blocking/unblocking apps
    @StateObject private var shieldManager = ShieldManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authorizationManager)
                .environmentObject(monitoringManager)
                .environmentObject(shieldManager)
                .handleURLScheme() // Handle deep links from shield
                .onAppear {
                    // Check if we need to show math gate on launch
                    // (user was redirected here from a shielded app)
                    checkForShieldRedirect()
                }
        }
    }

    /// Check if the app was opened because user tried to access a shielded app
    private func checkForShieldRedirect() {
        let persistence = PersistenceManager.shared

        // If apps are currently shielded and user hasn't solved challenge yet
        if persistence.isShieldActive && !persistence.challengeSolvedRecently {
            // The ContentView will handle showing the MathGateView
            NotificationCenter.default.post(
                name: .showMathGate,
                object: nil
            )
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let showMathGate = Notification.Name("showMathGate")
    static let shieldStateChanged = Notification.Name("shieldStateChanged")
}
