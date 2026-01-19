//
//  DeviceActivityMonitorExtension.swift
//  DeviceActivityMonitorExtension
//
//  This extension runs in the background and receives callbacks from the
//  DeviceActivity framework when monitoring events occur.
//
//  CRITICAL: This extension runs in a separate process from the main app.
//  Communication with the main app happens via:
//  - App Group UserDefaults (for state sharing)
//  - ManagedSettingsStore (for applying/removing shields)
//
//  IMPORTANT LIMITATIONS:
//  ======================
//  1. This extension has very limited capabilities - no UI, no network, minimal memory
//  2. Callbacks must complete quickly or the system may terminate the extension
//  3. We cannot directly launch the main app from here (user must tap the shield)
//  4. The "break window" logic is approximated - see comments in MonitoringManager
//

import DeviceActivity
import ManagedSettings
import FamilyControls
import Foundation

/// Extension point for DeviceActivity monitoring
class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    /// Shared persistence using App Group
    private let persistence = PersistenceManager.shared

    /// ManagedSettings store for applying shields
    private let store = ManagedSettingsStore()

    // MARK: - Interval Callbacks

    /// Called when a monitoring interval starts
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        print("[Extension] Interval started for: \(activity.rawValue)")

        // Record session start time
        persistence.currentSessionStartTime = Date()
    }

    /// Called when a monitoring interval ends
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        print("[Extension] Interval ended for: \(activity.rawValue)")

        // If shield is still active when interval ends, keep it active
        // The user needs to solve the challenge to remove it
    }

    // MARK: - Event Callbacks

    /// Called when a usage threshold is reached
    /// This is where we apply the shield when the session limit is hit
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        print("[Extension] Event threshold reached: \(event.rawValue) for activity: \(activity.rawValue)")

        // Check which event triggered
        if event == .sessionLimitReached {
            handleSessionLimitReached()
        } else if event == .sessionWarning {
            handleSessionWarning()
        }
    }

    /// Called when device activity warning time is reached
    override func intervalWillStartWarning(for activity: DeviceActivityName) {
        super.intervalWillStartWarning(for: activity)
        print("[Extension] Interval will start warning for: \(activity.rawValue)")
    }

    /// Called when device activity warning time ends
    override func intervalWillEndWarning(for activity: DeviceActivityName) {
        super.intervalWillEndWarning(for: activity)
        print("[Extension] Interval will end warning for: \(activity.rawValue)")
    }

    // MARK: - Event Handlers

    /// Handle the session limit being reached
    private func handleSessionLimitReached() {
        print("[Extension] Session limit reached - applying shield")

        // Check if we're in a reward window (should not apply shield)
        if persistence.isInRewardWindow {
            print("[Extension] In reward window, not applying shield")
            return
        }

        // Apply shield to all selected apps
        applyShield()

        // Mark shield as active
        persistence.isShieldActive = true

        // The shield UI will show when user tries to open a blocked app
        // User must open ScrollBrake and solve the math challenge to remove shield
    }

    /// Handle the session warning event (optional - for future use)
    private func handleSessionWarning() {
        print("[Extension] Session warning - limit approaching")
        // Could send a notification here if desired
        // For MVP, we don't implement warnings
    }

    /// Apply shield to selected apps
    private func applyShield() {
        guard let selection = persistence.loadFamilyActivitySelection() else {
            print("[Extension] No selection found, cannot apply shield")
            return
        }

        // Apply shield to applications
        store.shield.applications = selection.applicationTokens

        // Apply shield to categories
        if !selection.categoryTokens.isEmpty {
            store.shield.applicationCategories = .specific(selection.categoryTokens)
        }

        // Apply shield to web domains
        store.shield.webDomains = selection.webDomainTokens

        print("[Extension] Shield applied to \(selection.applicationTokens.count) apps, \(selection.categoryTokens.count) categories, \(selection.webDomainTokens.count) domains")
    }

    /// Remove shield from all apps
    private func removeShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil

        persistence.isShieldActive = false

        print("[Extension] Shield removed")
    }
}

// MARK: - DeviceActivity Names (must match main app)
extension DeviceActivityName {
    static let sessionMonitor = DeviceActivityName("com.scrollbrake.sessionMonitor")
}

// MARK: - Event Names (must match main app)
extension DeviceActivityEvent.Name {
    static let sessionLimitReached = DeviceActivityEvent.Name("com.scrollbrake.sessionLimitReached")
    static let sessionWarning = DeviceActivityEvent.Name("com.scrollbrake.sessionWarning")
}
