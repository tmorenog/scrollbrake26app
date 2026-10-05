//
//  RootView.swift
//  BreakScroll
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        content
            .fullScreenCover(isPresented: interventionIsActive) {
                InterventionView()
                    .environmentObject(model)
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

    /// The cover follows the engine's phase; the views never dismiss it directly.
    private var interventionIsActive: Binding<Bool> {
        Binding(get: { model.activeIntervention != nil }, set: { _ in })
    }
}
