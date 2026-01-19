//
//  AuthorizationManager.swift
//  ScrollBrake
//
//  Handles FamilyControls authorization.
//  Screen Time APIs require explicit user permission before they can be used.
//

import SwiftUI
import FamilyControls

/// Manages FamilyControls authorization state
@MainActor
class AuthorizationManager: ObservableObject {
    static let shared = AuthorizationManager()

    /// Current authorization status
    @Published var authorizationStatus: AuthorizationStatus = .notDetermined

    /// The authorization center
    private let center = AuthorizationCenter.shared

    private init() {
        // Check current status on init
        checkAuthorizationStatus()
    }

    /// Check the current authorization status
    func checkAuthorizationStatus() {
        switch center.authorizationStatus {
        case .notDetermined:
            authorizationStatus = .notDetermined
        case .denied:
            authorizationStatus = .denied
        case .approved:
            authorizationStatus = .approved
        @unknown default:
            authorizationStatus = .notDetermined
        }
    }

    /// Request authorization from the user
    /// This presents a system dialog asking for Screen Time access
    func requestAuthorization() async {
        do {
            // Request individual (personal device) authorization
            // For parent/child setups, you'd use .child instead
            try await center.requestAuthorization(for: .individual)
            authorizationStatus = .approved
            print("[AuthorizationManager] Authorization approved")
        } catch {
            authorizationStatus = .denied
            print("[AuthorizationManager] Authorization denied: \(error.localizedDescription)")
        }
    }
}

/// Authorization status enum matching FamilyControls
enum AuthorizationStatus {
    case notDetermined
    case denied
    case approved
}
