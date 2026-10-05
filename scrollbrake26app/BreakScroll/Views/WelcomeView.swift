//
//  WelcomeView.swift
//  BreakScroll
//

import SwiftUI
import BreakScrollCore

struct WelcomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmingChildSetup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("Help make scrolling intentional.")
                            .font(.largeTitle.bold())
                        Text("BreakScroll doesn't simply ban apps. It adds short interruptions that help you decide whether you actually want to keep scrolling.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 12) {
                        ModeCard(
                            symbol: "person",
                            title: "Just for me",
                            detail: "Add short breaks to apps on this iPhone. You stay in control and can turn them off any time."
                        ) {
                            model.choose(.selfControl)
                        }
                        ModeCard(
                            symbol: "figure.and.child.holdinghands",
                            title: "This is my child's iPhone",
                            detail: "A parent approves setup here with their Apple Account. Afterwards, BreakScroll can't be removed without a parent."
                        ) {
                            confirmingChildSetup = true
                        }
                        ModeCard(
                            symbol: "iphone",
                            title: "I'm a parent, on my own iPhone",
                            detail: "Choose apps from your child's devices and see how breaks are going."
                        ) {
                            model.choose(.familyParent)
                        }
                    }
                }
                .padding(24)
            }
            .confirmationDialog(
                "Set up Family Controls on this iPhone?",
                isPresented: $confirmingChildSetup,
                titleVisibility: .visible
            ) {
                Button("Set Up Family Controls") { model.choose(.familyChild) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This iPhone must be signed in with your child's Apple Account, in your Family Sharing group. You'll approve with your own Apple Account.")
            }
        }
    }
}

private struct ModeCard: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 32)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
