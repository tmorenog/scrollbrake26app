//
//  AuthorizationView.swift
//  BreakScroll
//

import SwiftUI
import BreakScrollCore

struct AuthorizationView: View {
    @EnvironmentObject private var model: AppModel
    let mode: AppMode
    @State private var isRequesting = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title.bold())
                Text(explanation)
                    .foregroundStyle(.secondary)
                Label("BreakScroll never sees which apps you use or what's in them.", systemImage: "eye.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let error = model.authorizationError {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                Spacer()

                Button {
                    isRequesting = true
                    Task {
                        await model.requestAuthorization()
                        isRequesting = false
                    }
                } label: {
                    Text(mode == .familyChild ? "Set Up Family Controls" : "Allow Screen Time Access")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRequesting)

                Button("Choose a Different Setup") {
                    model.resetMode()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
    }

    private var title: String {
        mode == .familyChild ? "A parent needs to approve" : "Allow Screen Time access"
    }

    private var explanation: String {
        if mode == .familyChild {
            return "Apple will ask a parent or guardian in your Family Sharing group to sign in on this iPhone. After that, BreakScroll's breaks apply here and can't be removed without a parent."
        }
        return "BreakScroll uses Screen Time to notice when you've used selected apps for a while. You'll confirm with Face ID or Touch ID, and you can turn this off later."
    }
}
