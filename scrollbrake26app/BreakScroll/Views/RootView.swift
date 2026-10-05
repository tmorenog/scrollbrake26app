//
//  RootView.swift
//  BreakScroll
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        // A break replaces everything rather than covering it: a cover can't be
        // presented over an open sheet (rule editor, passcode, app picker), and
        // replacing the root also dismisses those sheets.
        if model.activeIntervention != nil {
            InterventionView()
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case nil:
            WelcomeView()
        case .familyParent?:
            ParentHomeView()
        case let mode?:
            if model.isAuthorized {
                HomeView()
            } else {
                AuthorizationView(mode: mode)
            }
        }
    }
}
