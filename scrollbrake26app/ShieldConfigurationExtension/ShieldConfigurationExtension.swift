//
//  ShieldConfigurationExtension.swift
//  ShieldConfigurationExtension
//
//  Chooses the words on the system shield. Apple sandboxes this extension (no
//  network, nothing leaves the process); it only reads the App Group state to
//  find the matching rule's phase. Wording lives in BreakScrollCore.ShieldCopy.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit
import BreakScrollCore

class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration { $0.contains(application.token) }
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        configuration { $0.contains(application.token) || $0.contains(category.token) }
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration { $0.contains(webDomain.token) }
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        configuration { $0.contains(webDomain.token) || $0.contains(category.token) }
    }

    private func configuration(matching matches: (FamilyActivitySelectionProbe) -> Bool) -> ShieldConfiguration {
        let state = SharedStore.shared.read()
        let ruleID = InterventionCoordinator().shieldedRuleIDs(in: state, matching: matches).first
        let rule = ruleID.flatMap(state.rule)
        let copy = ShieldCopy.make(
            phase: ruleID.map { state.session(for: $0).phase },
            usageInterval: rule?.usageInterval,
            mode: state.mode
        )
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: nil,
            icon: UIImage(systemName: "hourglass"),
            title: ShieldConfiguration.Label(text: copy.title, color: .label),
            subtitle: ShieldConfiguration.Label(text: copy.subtitle, color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: copy.primaryButton, color: .white),
            primaryButtonBackgroundColor: .systemBlue,
            secondaryButtonLabel: copy.secondaryButton.map { ShieldConfiguration.Label(text: $0, color: .systemBlue) }
        )
    }
}
