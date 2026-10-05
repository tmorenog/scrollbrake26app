//
//  ScreenTimeEnforcer.swift
//  Shared by the app and all three extensions.
//
//  The only place that calls DeviceActivity and ManagedSettings. Each rule has
//  its own named ManagedSettingsStore so rules can shield and unshield
//  independently.
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import BreakScrollCore

enum SelectionCoder {
    static func encode(_ selection: FamilyActivitySelection) -> Data {
        (try? PropertyListEncoder().encode(selection)) ?? Data()
    }

    static func decode(_ data: Data) -> FamilyActivitySelection? {
        guard !data.isEmpty else { return nil }
        return try? PropertyListDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    static func isEmpty(_ selection: FamilyActivitySelection) -> Bool {
        selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty && selection.webDomainTokens.isEmpty
    }
}

struct ScreenTimeEnforcer {
    enum EnforcementError: Error {
        /// An event with no apps, categories or domains counts *all* device
        /// activity (DeviceActivityEvent docs), so we refuse to arm one.
        case emptySelection
    }

    private let center = DeviceActivityCenter()

    /// Starts (or replaces) the rule's activity with a single event that fires
    /// after `threshold` more seconds of use. See REPEATING_INTERVALS.md §3.
    func arm(_ rule: InterventionRule, generation: Int, threshold: TimeInterval) throws {
        let selection = try nonEmptySelection(rule)
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: Self.components(threshold),
            includesPastActivity: false
        )
        try center.startMonitoring(
            DeviceActivityName(MonitoringNames.activity(ruleID: rule.id)),
            during: Self.schedule(rule.activeSchedule),
            events: [DeviceActivityEvent.Name(MonitoringNames.event(ruleID: rule.id, generation: generation)): event]
        )
        Log.monitor.info("armed rule=\(rule.id.uuidString, privacy: .public) gen=\(generation) threshold=\(Int(threshold))s")
    }

    /// The daily cap runs midnight to midnight and is never re-armed during
    /// the day, so it counts the day's total use of the selection.
    func armDailyLimit(_ rule: InterventionRule, limit: TimeInterval) throws {
        let selection = try nonEmptySelection(rule)
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: Self.components(limit),
            includesPastActivity: true
        )
        try center.startMonitoring(
            DeviceActivityName(MonitoringNames.dailyLimitActivity(ruleID: rule.id)),
            during: Self.schedule(.always),
            events: [DeviceActivityEvent.Name(MonitoringNames.dailyLimitEvent(ruleID: rule.id)): event]
        )
        Log.monitor.info("armed daily limit rule=\(rule.id.uuidString, privacy: .public) limit=\(Int(limit))s")
    }

    func stopMonitoring(_ ruleID: UUID) {
        center.stopMonitoring([
            DeviceActivityName(MonitoringNames.activity(ruleID: ruleID)),
            DeviceActivityName(MonitoringNames.dailyLimitActivity(ruleID: ruleID)),
        ])
        Log.monitor.info("stopped rule=\(ruleID.uuidString, privacy: .public)")
    }

    func applyShield(_ rule: InterventionRule) {
        guard let selection = SelectionCoder.decode(rule.selectionData) else {
            Log.shield.error("no selection for rule=\(rule.id.uuidString, privacy: .public)")
            return
        }
        let store = Self.store(for: rule.id)
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        Log.shield.info("shield applied rule=\(rule.id.uuidString, privacy: .public)")
    }

    func removeShield(_ ruleID: UUID) {
        Self.store(for: ruleID).clearAllSettings()
        Log.shield.info("shield removed rule=\(ruleID.uuidString, privacy: .public)")
    }

    var monitoredActivities: [String] {
        center.activities.map(\.rawValue)
    }

    // MARK: - Helpers

    static func store(for ruleID: UUID) -> ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name("rule.\(ruleID.uuidString)"))
    }

    static func components(_ interval: TimeInterval) -> DateComponents {
        let total = max(1, Int(interval.rounded()))
        return DateComponents(hour: total / 3600, minute: (total % 3600) / 60, second: total % 60)
    }

    /// Active hours become the schedule's daily interval. Weekdays are filtered
    /// by the engine, which keeps us at one activity per rule (Apple allows 20).
    static func schedule(_ schedule: WeeklySchedule) -> DeviceActivitySchedule {
        let end = schedule.end == .endOfDay
            ? DateComponents(hour: 23, minute: 59, second: 59)
            : DateComponents(hour: schedule.end.hour, minute: schedule.end.minute)
        return DeviceActivitySchedule(
            intervalStart: DateComponents(hour: schedule.start.hour, minute: schedule.start.minute),
            intervalEnd: end,
            repeats: true
        )
    }

    private func nonEmptySelection(_ rule: InterventionRule) throws -> FamilyActivitySelection {
        guard let selection = SelectionCoder.decode(rule.selectionData), !SelectionCoder.isEmpty(selection) else {
            throw EnforcementError.emptySelection
        }
        return selection
    }
}
