//
//  ShieldConfigurationExtension.swift
//  ShieldConfigurationExtension
//
//  Customizes the appearance of the shield overlay shown when blocked apps are opened.
//  This extension allows us to customize the title, subtitle, icon, and button labels
//  of the shield UI that iOS displays.
//
//  IMPORTANT: This extension runs in a separate process and has limited capabilities.
//  It cannot perform complex operations - just return configuration data.
//

import ManagedSettingsUI
import ManagedSettings
import UIKit

/// Extension point for shield configuration
class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    // MARK: - Application Shield Configuration

    /// Configure the shield for blocked applications
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        return createShieldConfiguration(for: application.localizedDisplayName)
    }

    /// Configure the shield for application categories
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        return createShieldConfiguration(for: category.localizedDisplayName ?? "this category")
    }

    /// Configure the shield for web domains
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        return createShieldConfiguration(for: webDomain.domain ?? "this website")
    }

    /// Configure the shield for web domain categories
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        return createShieldConfiguration(for: category.localizedDisplayName ?? "this category")
    }

    // MARK: - Shield Configuration Builder

    /// Create a consistent shield configuration
    private func createShieldConfiguration(for name: String?) -> ShieldConfiguration {
        let displayName = name ?? "this app"

        return ShieldConfiguration(
            // Background color - dark with slight transparency
            backgroundBlurStyle: .systemMaterialDark,

            // Background color as fallback
            backgroundColor: UIColor.systemBackground,

            // Custom icon (using SF Symbol)
            icon: UIImage(systemName: "brain.head.profile"),

            // Main title
            title: ShieldConfiguration.Label(
                text: "Time for a Break!",
                color: .label
            ),

            // Subtitle with context
            subtitle: ShieldConfiguration.Label(
                text: "You've reached your session limit for \(displayName). Open scrollbrake26app to continue.",
                color: .secondaryLabel
            ),

            // Primary button - opens our app
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Open scrollbrake26app",
                color: .white
            ),

            // Primary button background
            primaryButtonBackgroundColor: .systemBlue,

            // Secondary button - for dismissing without action
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: "Close",
                color: .systemBlue
            )
        )
    }
}

// MARK: - Notes on Shield Customization
/*
 ShieldConfiguration options:

 1. backgroundBlurStyle: UIBlurEffect.Style
    - .systemMaterial, .systemMaterialDark, .systemMaterialLight, etc.

 2. backgroundColor: UIColor
    - Fallback color if blur isn't available

 3. icon: UIImage?
    - Custom icon displayed on the shield
    - Keep it simple (SF Symbols work well)

 4. title: ShieldConfiguration.Label
    - Main heading text

 5. subtitle: ShieldConfiguration.Label
    - Secondary text with more details

 6. primaryButtonLabel: ShieldConfiguration.Label
    - Main action button text

 7. primaryButtonBackgroundColor: UIColor
    - Background color of primary button

 8. secondaryButtonLabel: ShieldConfiguration.Label
    - Secondary action button text (usually dismisses)

 The primary button action is handled by ShieldActionExtension.
 The secondary button typically just dismisses the shield overlay.
*/
