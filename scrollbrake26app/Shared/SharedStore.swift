//
//  SharedStore.swift
//  Shared by the app and all three extensions.
//
//  One JSON file in the App Group container holds everything the processes
//  share. Every read-modify-write goes through NSFileCoordinator because the
//  app, the monitor extension and the shield action extension can all write
//  at the same moment.
//

import Foundation
import BreakScrollCore

/// Local enforcement state for this device. Cross-device sync state (Phase 10)
/// will live separately, in CloudKit.
struct SharedState: Codable, Equatable {
    var mode: AppMode?
    var rules: [InterventionRule] = []
    var sessions: [InterventionSession] = []
    var records: [InterventionRecord] = []

    static let maxRecords = 5_000

    func rule(_ id: UUID) -> InterventionRule? {
        rules.first { $0.id == id }
    }

    func session(for ruleID: UUID) -> InterventionSession {
        sessions.first { $0.ruleID == ruleID } ?? InterventionSession(ruleID: ruleID)
    }

    mutating func setSession(_ session: InterventionSession) {
        if let index = sessions.firstIndex(where: { $0.ruleID == session.ruleID }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }

    mutating func upsert(_ rule: InterventionRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
    }

    mutating func removeRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
        sessions.removeAll { $0.ruleID == id }
    }

    mutating func append(_ record: InterventionRecord) {
        records.append(record)
        if records.count > Self.maxRecords {
            records.removeFirst(records.count - Self.maxRecords)
        }
    }
}

final class SharedStore {
    static let shared = SharedStore()

    let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else if let container = AppGroup.containerURL {
            self.fileURL = container.appendingPathComponent("state.json")
        } else {
            // Without the App Group the extensions can't see this file, so
            // enforcement won't work. Check every target's entitlements.
            Log.store.fault("App Group \(AppGroup.identifier, privacy: .public) unavailable")
            self.fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("state.json")
        }
    }

    func read() -> SharedState {
        var result = SharedState()
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
            result = Self.load(from: url)
        }
        if let coordinationError {
            Log.store.error("read failed: \(coordinationError.localizedDescription, privacy: .public)")
        }
        return result
    }

    /// Atomic read-modify-write across processes.
    @discardableResult
    func mutate<T>(_ body: (inout SharedState) -> T) -> T {
        var result: T?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordinationError) { url in
            var state = Self.load(from: url)
            result = body(&state)
            do {
                try JSONEncoder().encode(state).write(to: url, options: .atomic)
            } catch {
                Log.store.error("write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        if let result {
            return result
        }
        // Coordination failed before running `body`. Fall back to an
        // uncoordinated read-modify-write of the real file rather than acting
        // on empty state.
        Log.store.error("mutate uncoordinated: \(coordinationError?.localizedDescription ?? "unknown", privacy: .public)")
        var state = Self.load(from: fileURL)
        let value = body(&state)
        try? JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
        return value
    }

    private static func load(from url: URL) -> SharedState {
        guard let data = try? Data(contentsOf: url) else { return SharedState() }
        do {
            return try JSONDecoder().decode(SharedState.self, from: data)
        } catch {
            // Keep the unreadable file for diagnosis rather than silently losing rules.
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
            Log.store.fault("state.json unreadable, starting fresh: \(error.localizedDescription, privacy: .public)")
            return SharedState()
        }
    }
}
