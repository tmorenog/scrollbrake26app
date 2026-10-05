//
//  InterventionCoordinator.swift
//  Shared by the app and all three extensions.
//
//  Runs BreakScrollCore's pure InterventionEngine against the shared state and
//  performs its effects. Arm results are fed straight back into the engine
//  inside the same coordinated write, so "re-arm, then unshield" is ordered.
//

import Foundation
import BreakScrollCore

struct InterventionCoordinator {
    var store = SharedStore.shared
    var enforcer = ScreenTimeEnforcer()
    var calendar = Calendar.current

    @discardableResult
    func send(_ input: InterventionInput, ruleID: UUID) -> InterventionSession? {
        store.mutate { state in
            apply(input, ruleID: ruleID, state: &state)
        }
    }

    /// Use inside an existing `SharedStore.mutate` transaction.
    @discardableResult
    func apply(_ input: InterventionInput, ruleID: UUID, state: inout SharedState, now: Date = Date()) -> InterventionSession? {
        guard let rule = state.rule(ruleID) else {
            Log.engine.error("unknown rule=\(ruleID.uuidString, privacy: .public)")
            return nil
        }
        let engine = InterventionEngine(rule: rule, calendar: calendar)
        var session = state.session(for: ruleID)
        var queue = [input]

        while !queue.isEmpty {
            let next = queue.removeFirst()
            for effect in engine.handle(next, session: &session, now: now) {
                switch effect {
                case .arm(let generation, let threshold):
                    do {
                        try enforcer.arm(rule, generation: generation, threshold: threshold)
                        queue.append(.armSucceeded(generation: generation))
                    } catch {
                        Log.monitor.error("arm failed rule=\(ruleID.uuidString, privacy: .public): \(String(describing: error), privacy: .public)")
                        queue.append(.armFailed(generation: generation))
                    }
                case .armDailyLimit(let limit):
                    do {
                        try enforcer.armDailyLimit(rule, limit: limit)
                    } catch {
                        Log.monitor.error("daily limit arm failed: \(String(describing: error), privacy: .public)")
                    }
                case .stopMonitoring:
                    enforcer.stopMonitoring(ruleID)
                case .applyShield:
                    enforcer.applyShield(rule)
                case .removeShield:
                    enforcer.removeShield(ruleID)
                case .record(let record):
                    state.append(record)
                }
            }
        }

        state.setSession(session)
        Log.engine.info("""
            rule=\(ruleID.uuidString, privacy: .public) input=\(String(describing: input), privacy: .public) \
            phase=\(String(describing: session.phase), privacy: .public) gen=\(session.armedGeneration)
            """)
        return session
    }

    /// Rule IDs whose shield is up and whose selection matches `matches`.
    /// Falls back to every shielded rule if none match (e.g. a category shield).
    func shieldedRuleIDs(in state: SharedState, matching matches: (FamilyActivitySelectionProbe) -> Bool) -> [UUID] {
        let shielded = state.rules.filter { state.session(for: $0.id).phase.isShielded }
        let matching = shielded.filter { rule in
            SelectionCoder.decode(rule.selectionData).map { matches(FamilyActivitySelectionProbe(selection: $0)) } ?? false
        }
        return (matching.isEmpty ? shielded : matching).map(\.id)
    }
}
