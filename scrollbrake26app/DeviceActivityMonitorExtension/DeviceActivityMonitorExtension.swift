//
//  DeviceActivityMonitorExtension.swift
//  DeviceActivityMonitorExtension
//
//  Runs on the enforcing device (the child's iPhone in Family Mode), even when
//  BreakScroll isn't running. It only translates system callbacks into engine
//  inputs; all decisions live in BreakScrollCore's InterventionEngine.
//

import DeviceActivity
import Foundation
import BreakScrollCore

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let coordinator = InterventionCoordinator()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        Log.monitor.info("intervalDidStart \(activity.rawValue, privacy: .public)")
        guard case .rule(let ruleID)? = MonitoringNames.parse(activity: activity.rawValue) else { return }
        coordinator.send(.intervalStarted, ruleID: ruleID)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        Log.monitor.info("intervalDidEnd \(activity.rawValue, privacy: .public)")
        guard case .rule(let ruleID)? = MonitoringNames.parse(activity: activity.rawValue) else { return }
        coordinator.send(.intervalEnded, ruleID: ruleID)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        switch MonitoringNames.parse(event: event.rawValue) {
        case .threshold(let ruleID, let generation)?:
            Log.monitor.info("threshold rule=\(ruleID.uuidString, privacy: .public) gen=\(generation)")
            coordinator.send(.thresholdReached(generation: generation), ruleID: ruleID)
        case .dailyLimit(let ruleID)?:
            Log.monitor.info("daily limit rule=\(ruleID.uuidString, privacy: .public)")
            coordinator.send(.dailyLimitReached, ruleID: ruleID)
        case nil:
            Log.monitor.error("unknown event \(event.rawValue, privacy: .public)")
        }
    }
}
