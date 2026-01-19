//
//  PersistenceManager.swift
//  ScrollBrake
//
//  Handles persistence of settings and state using App Group UserDefaults.
//  App Groups allow sharing data between the main app and extensions.
//
//  IMPORTANT: The App Group identifier must match in:
//  - Main app entitlements
//  - DeviceActivityMonitor extension entitlements
//  - ShieldConfiguration extension entitlements
//  - ShieldAction extension entitlements
//

import Foundation
import FamilyControls

/// Manages all persistent storage for ScrollBrake
class PersistenceManager {
    static let shared = PersistenceManager()

    // MARK: - App Group Configuration

    /// The App Group identifier - must match entitlements
    /// Format: group.{bundle-identifier}
    static let appGroupIdentifier = "group.com.scrollbrake26app.shared"

    /// UserDefaults instance using App Group for cross-process sharing
    private let defaults: UserDefaults

    // MARK: - Keys
    private enum Keys {
        static let sessionLimitMinutes = "sessionLimitMinutes"
        static let breakWindowSeconds = "breakWindowSeconds"
        static let rewardWindowMinutes = "rewardWindowMinutes"
        static let isMonitoringActive = "isMonitoringActive"
        static let isShieldActive = "isShieldActive"
        static let currentSessionStartTime = "currentSessionStartTime"
        static let familyActivitySelection = "familyActivitySelection"
        static let lastChallengeSolvedTime = "lastChallengeSolvedTime"
        static let rewardWindowEndTime = "rewardWindowEndTime"
        static let selectedAppsCount = "selectedAppsCount"
    }

    // MARK: - Initialization

    private init() {
        // Try to use App Group UserDefaults, fall back to standard if not available
        if let groupDefaults = UserDefaults(suiteName: PersistenceManager.appGroupIdentifier) {
            self.defaults = groupDefaults
            print("[PersistenceManager] Using App Group UserDefaults")
        } else {
            self.defaults = UserDefaults.standard
            print("[PersistenceManager] WARNING: App Group not available, using standard UserDefaults")
        }

        // Set defaults if not already set
        registerDefaults()
    }

    private func registerDefaults() {
        defaults.register(defaults: [
            Keys.sessionLimitMinutes: 5,
            Keys.breakWindowSeconds: 20,
            Keys.rewardWindowMinutes: 2,
            Keys.isMonitoringActive: false,
            Keys.isShieldActive: false,
            Keys.selectedAppsCount: 0
        ])
    }

    // MARK: - Settings Properties

    /// Session limit in minutes (default: 5)
    var sessionLimitMinutes: Int {
        get { defaults.integer(forKey: Keys.sessionLimitMinutes) }
        set { defaults.set(newValue, forKey: Keys.sessionLimitMinutes) }
    }

    /// Break window in seconds (default: 20)
    var breakWindowSeconds: Int {
        get { defaults.integer(forKey: Keys.breakWindowSeconds) }
        set { defaults.set(newValue, forKey: Keys.breakWindowSeconds) }
    }

    /// Reward window in minutes (default: 2)
    var rewardWindowMinutes: Int {
        get { defaults.integer(forKey: Keys.rewardWindowMinutes) }
        set { defaults.set(newValue, forKey: Keys.rewardWindowMinutes) }
    }

    // MARK: - State Properties

    /// Whether monitoring is currently active
    var isMonitoringActive: Bool {
        get { defaults.bool(forKey: Keys.isMonitoringActive) }
        set { defaults.set(newValue, forKey: Keys.isMonitoringActive) }
    }

    /// Whether apps are currently shielded
    var isShieldActive: Bool {
        get { defaults.bool(forKey: Keys.isShieldActive) }
        set { defaults.set(newValue, forKey: Keys.isShieldActive) }
    }

    /// When the current session started
    var currentSessionStartTime: Date? {
        get { defaults.object(forKey: Keys.currentSessionStartTime) as? Date }
        set { defaults.set(newValue, forKey: Keys.currentSessionStartTime) }
    }

    /// When the last challenge was solved
    var lastChallengeSolvedTime: Date? {
        get { defaults.object(forKey: Keys.lastChallengeSolvedTime) as? Date }
        set { defaults.set(newValue, forKey: Keys.lastChallengeSolvedTime) }
    }

    /// When the reward window ends
    var rewardWindowEndTime: Date? {
        get { defaults.object(forKey: Keys.rewardWindowEndTime) as? Date }
        set { defaults.set(newValue, forKey: Keys.rewardWindowEndTime) }
    }

    /// Number of selected apps (for display purposes)
    var selectedAppsCount: Int {
        get { defaults.integer(forKey: Keys.selectedAppsCount) }
        set { defaults.set(newValue, forKey: Keys.selectedAppsCount) }
    }

    // MARK: - Computed Properties

    /// Whether the challenge was solved recently (within reward window)
    var challengeSolvedRecently: Bool {
        guard let solvedTime = lastChallengeSolvedTime else { return false }
        let rewardDuration = TimeInterval(rewardWindowMinutes * 60)
        return Date().timeIntervalSince(solvedTime) < rewardDuration
    }

    /// Whether we're currently in a reward window
    var isInRewardWindow: Bool {
        guard let endTime = rewardWindowEndTime else { return false }
        return Date() < endTime
    }

    // MARK: - FamilyActivitySelection Persistence

    /// Save the FamilyActivitySelection
    /// Note: FamilyActivitySelection contains opaque tokens that can be encoded
    func saveFamilyActivitySelection(_ selection: FamilyActivitySelection) {
        do {
            let encoder = PropertyListEncoder()
            let data = try encoder.encode(selection)
            defaults.set(data, forKey: Keys.familyActivitySelection)

            // Update count for display
            selectedAppsCount = selection.applicationTokens.count +
                               selection.categoryTokens.count +
                               selection.webDomainTokens.count

            print("[PersistenceManager] Saved selection: \(selectedAppsCount) items")
        } catch {
            print("[PersistenceManager] Failed to save selection: \(error)")
        }
    }

    /// Load the FamilyActivitySelection
    func loadFamilyActivitySelection() -> FamilyActivitySelection? {
        guard let data = defaults.data(forKey: Keys.familyActivitySelection) else {
            return nil
        }

        do {
            let decoder = PropertyListDecoder()
            let selection = try decoder.decode(FamilyActivitySelection.self, from: data)
            return selection
        } catch {
            print("[PersistenceManager] Failed to load selection: \(error)")
            return nil
        }
    }

    // MARK: - Utility Methods

    /// Record that the challenge was solved
    func recordChallengeSolved() {
        lastChallengeSolvedTime = Date()
    }

    /// Clear all session-related data
    func clearSessionData() {
        currentSessionStartTime = nil
        isShieldActive = false
        lastChallengeSolvedTime = nil
        rewardWindowEndTime = nil
    }

    /// Clear all data (full reset)
    func clearAllData() {
        let domain = Bundle.main.bundleIdentifier ?? "com.scrollbrake"
        defaults.removePersistentDomain(forName: domain)
        registerDefaults()
    }
}
