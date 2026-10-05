//
//  RuleEditorView.swift
//  BreakScroll
//

import FamilyControls
import ManagedSettings
import SwiftUI
import BreakScrollCore

struct RuleEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rule: InterventionRule
    @State private var selection: FamilyActivitySelection
    @State private var showingPicker = false
    let isNew: Bool
    let mode: AppMode?
    let onSave: (InterventionRule) -> Void

    init(rule: InterventionRule, isNew: Bool, mode: AppMode?, onSave: @escaping (InterventionRule) -> Void) {
        _rule = State(initialValue: rule)
        _selection = State(initialValue: SelectionCoder.decode(rule.selectionData) ?? FamilyActivitySelection())
        self.isNew = isNew
        self.mode = mode
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label(SelectionCoder.isEmpty(selection) ? "Choose Apps" : "Change Apps", systemImage: "square.grid.2x2")
                    }
                    SelectionSummary(selection: selection)
                } header: {
                    Text("Apps")
                } footer: {
                    if !selection.categoryTokens.isEmpty {
                        Text("Whole categories can include apps people rely on, like messaging, maps or school apps. Choose individual apps where you can.")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Name") {
                    TextField("Name", text: $rule.name)
                }

                Section {
                    Picker("Use for", selection: $rule.usageInterval) {
                        ForEach(options(InterventionRule.usageIntervalPresets, including: rule.usageInterval), id: \.self) {
                            Text(ShieldCopy.describe($0)).tag($0)
                        }
                    }
                    Picker("Then pause for", selection: $rule.pauseDuration) {
                        ForEach(options(InterventionRule.pauseDurationPresets, including: rule.pauseDuration), id: \.self) {
                            Text(RuleText.pauseLabel($0)).tag($0)
                        }
                    }
                    .disabled(rule.escalationPolicy.isEnabled)
                    Picker("Challenge", selection: $rule.challengeDifficulty) {
                        ForEach(ChallengeDifficulty.allCases, id: \.self) {
                            Text(RuleText.difficulty($0)).tag($0)
                        }
                    }
                    .disabled(rule.escalationPolicy.isEnabled)
                    Toggle("Make each continuation harder", isOn: escalationEnabled)
                } header: {
                    Text("Breaks")
                } footer: {
                    Text(rule.escalationPolicy.isEnabled
                        ? "Each time in a day: 20-second pause and easy math, then 30 seconds and medium, then 1 minute, then 2 minutes and hard math. \(fifthContinuation)"
                        : "\(RuleText.interval(rule)). \(RuleText.intervention(rule)).")
                }

                Section("Limits") {
                    Toggle("Limit continuations per day", isOn: maxContinuationsEnabled)
                    if let max = rule.maxContinuations {
                        Stepper("\(max) per day", value: maxContinuations, in: 1...20)
                    }
                    Toggle("Maximum daily time", isOn: dailyLimitEnabled)
                    if let limit = rule.dailyLimit {
                        Stepper(ShieldCopy.describe(limit), value: dailyLimitMinutes, in: 15...600, step: 15)
                    }
                }

                Section("Active Hours") {
                    WeekdayPicker(days: $rule.activeSchedule.activeDays)
                    Toggle("All day", isOn: allDay)
                    if !allDay.wrappedValue {
                        DatePicker("Starts", selection: time(\.start), displayedComponents: .hourAndMinute)
                        DatePicker("Ends", selection: time(\.end), displayedComponents: .hourAndMinute)
                    }
                }

                Section {
                    Toggle("Rule is on", isOn: $rule.enabled)
                }

                if !problems.isEmpty {
                    Section {
                        ForEach(problems, id: \.self) { Text($0).foregroundStyle(.red) }
                    }
                }
            }
            .familyActivityPicker(isPresented: $showingPicker, selection: $selection)
            .navigationTitle(isNew ? "New Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(ruleWithSelection)
                        dismiss()
                    }
                    .disabled(!problems.isEmpty)
                }
            }
        }
    }

    // MARK: - Derived state

    private var ruleWithSelection: InterventionRule {
        var result = rule
        result.selectionData = SelectionCoder.encode(selection)
        return result
    }

    private var problems: [String] {
        var messages = ruleWithSelection.validate().map(RuleText.validation)
        if SelectionCoder.isEmpty(selection) {
            messages.insert("Choose at least one app.", at: 0)
        }
        return messages
    }

    private var fifthContinuation: String {
        mode == .familyChild
            ? "After that, a parent is needed."
            : "After that, these apps stay paused until tomorrow."
    }

    private func options(_ presets: [TimeInterval], including value: TimeInterval) -> [TimeInterval] {
        presets.contains(value) ? presets : (presets + [value]).sorted()
    }

    // MARK: - Bindings

    private var escalationEnabled: Binding<Bool> {
        Binding(
            get: { rule.escalationPolicy.isEnabled },
            set: { rule.escalationPolicy = $0 ? .standard : .none }
        )
    }

    private var maxContinuationsEnabled: Binding<Bool> {
        Binding(get: { rule.maxContinuations != nil }, set: { rule.maxContinuations = $0 ? 4 : nil })
    }

    private var maxContinuations: Binding<Int> {
        Binding(get: { rule.maxContinuations ?? 4 }, set: { rule.maxContinuations = $0 })
    }

    private var dailyLimitEnabled: Binding<Bool> {
        Binding(get: { rule.dailyLimit != nil }, set: { rule.dailyLimit = $0 ? 90 * 60 : nil })
    }

    private var dailyLimitMinutes: Binding<Int> {
        Binding(
            get: { Int((rule.dailyLimit ?? 5400) / 60) },
            set: { rule.dailyLimit = TimeInterval($0 * 60) }
        )
    }

    private var allDay: Binding<Bool> {
        Binding(
            get: { rule.activeSchedule.start == .startOfDay && rule.activeSchedule.end == .endOfDay },
            set: { isAllDay in
                rule.activeSchedule.start = isAllDay ? .startOfDay : WeeklySchedule.daytime.start
                rule.activeSchedule.end = isAllDay ? .endOfDay : WeeklySchedule.daytime.end
            }
        )
    }

    private func time(_ keyPath: WritableKeyPath<WeeklySchedule, TimeOfDay>) -> Binding<Date> {
        Binding(
            get: {
                let value = rule.activeSchedule[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: min(value.hour, 23), minute: value.minute, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                rule.activeSchedule[keyPath: keyPath] = TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
            }
        )
    }
}

/// Shows what's selected using Apple's privacy-preserving labels. BreakScroll
/// itself never learns the app names.
private struct SelectionSummary: View {
    let selection: FamilyActivitySelection

    var body: some View {
        let apps = Array(selection.applicationTokens)
        ForEach(apps.prefix(8), id: \.self) { token in
            Label(token)
        }
        if apps.count > 8 {
            Text("and \(apps.count - 8) more apps").foregroundStyle(.secondary)
        }
        ForEach(Array(selection.categoryTokens), id: \.self) { token in
            Label(token)
        }
        ForEach(Array(selection.webDomainTokens), id: \.self) { token in
            Label(token)
        }
    }
}

private struct WeekdayPicker: View {
    @Binding var days: Set<Weekday>

    private var ordered: [Weekday] {
        let first = Calendar.current.firstWeekday
        return (0..<7).compactMap { Weekday(rawValue: (first - 1 + $0) % 7 + 1) }
    }

    var body: some View {
        HStack {
            ForEach(ordered, id: \.self) { day in
                let isOn = days.contains(day)
                Button {
                    if isOn {
                        days.remove(day)
                    } else {
                        days.insert(day)
                    }
                    return
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[day.rawValue - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isOn ? Color.accentColor : Color(.tertiarySystemFill), in: Circle())
                        .foregroundStyle(isOn ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day.rawValue - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
