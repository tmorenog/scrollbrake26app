//
//  FamilyActivitySelectionProbe.swift
//  Shared by the app and all three extensions.
//

import FamilyControls
import ManagedSettings

/// Answers "does this rule cover the shielded item?" for the shield extensions.
struct FamilyActivitySelectionProbe {
    let selection: FamilyActivitySelection

    func contains(_ token: ApplicationToken?) -> Bool {
        token.map { selection.applicationTokens.contains($0) } ?? false
    }

    func contains(_ token: ActivityCategoryToken?) -> Bool {
        token.map { selection.categoryTokens.contains($0) } ?? false
    }

    func contains(_ token: WebDomainToken?) -> Bool {
        token.map { selection.webDomainTokens.contains($0) } ?? false
    }
}
