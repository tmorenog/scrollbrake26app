//
//  URLHandler.swift
//  ScrollBrake
//
//  Handles URL scheme deep linking when user taps "Open ScrollBrake"
//  on the shield overlay.
//
//  URL Scheme: scrollbrake://
//  Supported paths:
//  - scrollbrake://challenge - Open math challenge directly
//  - scrollbrake://home - Open home screen
//  - scrollbrake:// - Default to challenge if shield is active
//

import SwiftUI

/// URL handler modifier for the app
struct URLHandlerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.onOpenURL { url in
            handleURL(url)
        }
    }

    private func handleURL(_ url: URL) {
        print("[URLHandler] Received URL: \(url)")

        guard url.scheme == "scrollbrake" else {
            print("[URLHandler] Unknown scheme: \(url.scheme ?? "nil")")
            return
        }

        let path = url.host ?? ""

        switch path {
        case "challenge":
            // Directly show the math challenge
            showMathGate()

        case "home":
            // Just open the app (default behavior)
            break

        default:
            // Default behavior: check if shield is active
            let persistence = PersistenceManager.shared
            if persistence.isShieldActive && !persistence.challengeSolvedRecently {
                showMathGate()
            }
        }
    }

    private func showMathGate() {
        NotificationCenter.default.post(
            name: .showMathGate,
            object: nil
        )
    }
}

// MARK: - View Extension
extension View {
    /// Add URL handling to any view
    func handleURLScheme() -> some View {
        modifier(URLHandlerModifier())
    }
}
