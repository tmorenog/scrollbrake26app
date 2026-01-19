//
//  ShieldManager.swift
//  ScrollBrake
//
//  Manages ManagedSettings shield application and removal.
//  When apps are shielded, iOS shows a system overlay preventing access.
//

import Foundation
import ManagedSettings
import FamilyControls

@MainActor
class ShieldManager: ObservableObject {
    static let shared = ShieldManager()

    /// Whether shield is currently active
    @Published var isShieldActive: Bool = false

    /// The managed settings store for applying shields
    /// Using a named store allows us to manage it from both app and extension
    private let store = ManagedSettingsStore()

    /// Persistence manager
    private let persistence = PersistenceManager.shared

    private init() {
        // Load saved state
        isShieldActive = persistence.isShieldActive
    }

    // MARK: - Public Methods

    /// Apply shield to the selected apps
    /// This blocks access to the apps until shield is removed
    func applyShield() {
        guard let selection = persistence.loadFamilyActivitySelection() else {
            print("[ShieldManager] No selection to shield")
            return
        }

        // Apply shield to selected applications
        store.shield.applications = selection.applicationTokens

        // Apply shield to selected categories
        store.shield.applicationCategories = .specific(selection.categoryTokens)

        // Apply shield to web domains
        store.shield.webDomains = selection.webDomainTokens

        isShieldActive = true
        persistence.isShieldActive = true

        // Post notification for UI updates
        NotificationCenter.default.post(name: .shieldStateChanged, object: nil)

        print("[ShieldManager] Shield applied to \(selection.applicationTokens.count) apps, \(selection.categoryTokens.count) categories")
    }

    /// Remove shield from all apps
    func removeShield() {
        // Clear all shields
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil

        isShieldActive = false
        persistence.isShieldActive = false

        // Post notification for UI updates
        NotificationCenter.default.post(name: .shieldStateChanged, object: nil)

        print("[ShieldManager] Shield removed")
    }

    /// Apply shield from extension context (non-MainActor)
    /// This is called from the DeviceActivityMonitor extension
    static func applyShieldFromExtension() {
        let store = ManagedSettingsStore()
        let persistence = PersistenceManager.shared

        guard let selection = persistence.loadFamilyActivitySelection() else {
            print("[ShieldManager] Extension: No selection to shield")
            return
        }

        store.shield.applications = selection.applicationTokens
        store.shield.applicationCategories = .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens

        persistence.isShieldActive = true

        print("[ShieldManager] Extension: Shield applied")
    }

    /// Remove shield from extension context (non-MainActor)
    static func removeShieldFromExtension() {
        let store = ManagedSettingsStore()
        let persistence = PersistenceManager.shared

        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil

        persistence.isShieldActive = false

        print("[ShieldManager] Extension: Shield removed")
    }
}

// MARK: - ManagedSettingsStore Extension
extension ManagedSettingsStore {
    /// Convenience method to check if any shields are active
    var hasActiveShields: Bool {
        return shield.applications != nil ||
               shield.applicationCategories != nil ||
               shield.webDomains != nil
    }
}
