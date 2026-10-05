//
//  ParentHomeView.swift
//  BreakScroll
//
//  The parent's own iPhone. Until family sync (Phase 10), rules are set on the
//  child's iPhone. This screen already lets a parent check that Apple's picker
//  shows their child's apps here (experiment E3 in SCREEN_TIME_FEASIBILITY.md).
//

import FamilyControls
import ManagedSettings
import SwiftUI

struct ParentHomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection = FamilyActivitySelection()
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Family")
                            .font(.title2.bold())
                        Text("Breaks run on your child's iPhone, even when it's offline. For now, set rules there: open BreakScroll on their iPhone and use your parent passcode. Changing rules from this iPhone is coming next.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    Button("Choose from Your Child's Apps") { showingPicker = true }
                    let apps = Array(selection.applicationTokens)
                    ForEach(apps, id: \.self) { Label($0) }
                    ForEach(Array(selection.categoryTokens), id: \.self) { Label($0) }
                } header: {
                    Text("Preview")
                } footer: {
                    Text("Apple shows apps from your children's devices here. If you see this iPhone's own apps instead, family app selection isn't available on this iPhone yet.")
                }

                Section {
                    Button("Change Setup") { model.resetMode() }
                }
            }
            .navigationTitle("BreakScroll")
            .familyActivityPicker(isPresented: $showingPicker, selection: $selection)
        }
    }
}
