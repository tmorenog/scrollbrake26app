//
//  HomeView.swift
//  BreakScroll
//
//  Home for the device that enforces rules: Self-Control Mode, or the child's
//  iPhone in Family Mode (where changes need the parent passcode).
//

import FamilyControls
import SwiftUI
import BreakScrollCore

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sheet: Sheet?
    @State private var confirmingDeleteData = false

    private enum ProtectedAction {
        case edit(InterventionRule)
        case delete(InterventionRule)
        case deleteAllData
    }

    private enum Sheet: Identifiable {
        case passcode(ProtectedAction)
        case editor(InterventionRule)

        var id: String {
            switch self {
            case .passcode: return "passcode"
            case .editor(let rule): return "editor-\(rule.id)"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let message = model.unlockMessage {
                    Section {
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .task {
                        try? await Task.sleep(for: .seconds(4))
                        model.unlockMessage = nil
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.rules.isEmpty ? "Add a rule to get started." : "You're all set.")
                            .font(.title2.bold())
                        Text(headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                if !model.rules.isEmpty {
                    Section("Rules") {
                        ForEach(model.rules) { rule in
                            RuleRow(rule: rule, session: model.session(for: rule), mode: model.mode) {
                                model.send(.chooseContinue, to: rule)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { request(.edit(rule)) }
                            .swipeActions {
                                Button("Delete", role: .destructive) { request(.delete(rule)) }
                            }
                        }
                    }

                    Section("Today") {
                        let summary = model.todaySummary
                        LabeledContent("Breaks taken", value: "\(summary.interventions)")
                        LabeledContent("Times stopped", value: "\(summary.stopped)")
                        LabeledContent("Times continued", value: "\(summary.continued)")
                    }
                }

                Section {
                    Button {
                        request(.edit(InterventionRule(name: "Social apps")))
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                }

                Section {
                    Button("Delete BreakScroll Data", role: .destructive) {
                        confirmingDeleteData = true
                    }
                    #if DEBUG
                    NavigationLink("Developer") { DebugPanelView() }
                    #endif
                } footer: {
                    Text("BreakScroll keeps only its own counts of breaks, on this iPhone. It never sees which apps you use or what's in them.")
                }
            }
            .navigationTitle("BreakScroll")
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .passcode(let action):
                    PasscodeSheet { perform(action) }
                case .editor(let rule):
                    RuleEditorView(rule: rule, isNew: !model.rules.contains { $0.id == rule.id }, mode: model.mode) { saved in
                        model.save(saved)
                    }
                }
            }
            .confirmationDialog("Delete all BreakScroll data?", isPresented: $confirmingDeleteData, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { request(.deleteAllData) }
            } message: {
                Text("This removes your rules and history and stops all breaks on this iPhone.")
            }
        }
    }

    private var headline: String {
        model.mode == .familyChild
            ? "Selected apps take a short break now and then. A parent sets the rules."
            : "Selected apps take a short break now and then, so you can decide whether to keep going."
    }

    private func request(_ action: ProtectedAction) {
        if model.requiresPasscodeToEdit {
            sheet = .passcode(action)
        } else {
            perform(action)
        }
    }

    private func perform(_ action: ProtectedAction) {
        switch action {
        case .edit(let rule):
            sheet = .editor(rule)
        case .delete(let rule):
            sheet = nil
            model.delete(rule)
        case .deleteAllData:
            sheet = nil
            model.deleteAllData()
        }
    }
}

private struct RuleRow: View {
    let rule: InterventionRule
    let session: InterventionSession
    let mode: AppMode?
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(rule.name).font(.headline)
                Spacer()
                Text(RuleText.status(session.phase, enabled: rule.enabled, mode: mode))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(RuleText.interval(rule))
            Text(RuleText.intervention(rule))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if case .stopped = session.phase {
                Button("Continue", action: onContinue)
                    .buttonStyle(.borderless)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}
