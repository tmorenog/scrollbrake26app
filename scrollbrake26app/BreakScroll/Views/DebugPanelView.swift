//
//  DebugPanelView.swift
//  BreakScroll
//
//  DEBUG builds only: short thresholds and pauses for on-device testing
//  (REPEATING_INTERVALS.md §5), plus a view of the shared state.
//

#if DEBUG
import SwiftUI
import BreakScrollCore

struct DebugPanelView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Mode", value: model.mode?.rawValue ?? "none")
                LabeledContent("Authorization", value: String(describing: model.authorizationStatus))
                ForEach(ScreenTimeEnforcer().monitoredActivities, id: \.self) {
                    Text($0).font(.caption.monospaced())
                }
            }

            ForEach(model.rules) { rule in
                let session = model.session(for: rule)
                Section(rule.name) {
                    LabeledContent("Phase", value: String(describing: session.phase))
                    LabeledContent("Generation", value: "\(session.armedGeneration)")
                    LabeledContent("Continuations today", value: "\(session.continuationsToday)")

                    HStack {
                        Text("Threshold")
                        Spacer()
                        ForEach([30.0, 60, 120], id: \.self) { seconds in
                            Button(ShieldCopy.describe(seconds)) { update(rule) { $0.usageInterval = seconds } }
                                .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        Text("Pause")
                        Spacer()
                        ForEach([3.0, 5, 10], id: \.self) { seconds in
                            Button("\(Int(seconds))s") {
                                update(rule) {
                                    $0.pauseDuration = seconds
                                    $0.escalationPolicy = .none
                                }
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button("Force Shield") { model.send(.thresholdReached(generation: session.armedGeneration), to: rule) }
                    Button("Simulate Challenge") {
                        model.send(.thresholdReached(generation: session.armedGeneration), to: rule)
                        model.send(.chooseContinue, to: rule)
                    }
                    Button("Remove Shield and Restart") {
                        model.send(.stop, to: rule)
                        model.send(.start, to: rule)
                    }
                }
            }

            Section("App Group state.json") {
                Text(stateJSON)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }

            Section {
                Button("Reset Setup", role: .destructive) {
                    model.deleteAllData()
                    ParentPasscode.remove()
                    model.resetMode()
                }
            }
        }
        .navigationTitle("Developer")
    }

    private func update(_ rule: InterventionRule, _ change: (inout InterventionRule) -> Void) {
        var edited = rule
        change(&edited)
        model.save(edited)
    }

    private var stateJSON: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var state = model.state
        state.records = Array(state.records.suffix(20))
        return (try? encoder.encode(state)).flatMap { String(data: $0, encoding: .utf8) } ?? "unreadable"
    }
}
#endif
