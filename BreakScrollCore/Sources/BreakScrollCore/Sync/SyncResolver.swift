import Foundation

/// Anything carried between the parent's and child's devices.
public protocol Versioned {
    var version: Int { get }
    var updatedAt: Date { get }
    var updatedBy: String { get }
}

extension InterventionRule: Versioned {}
extension ChildConfiguration: Versioned {}

/// Picks between the cached copy and an incoming one.
///
/// `version` is authoritative; `updatedAt` only breaks ties because device
/// clocks drift. Equal versions with different content happen only when two
/// parent devices edit offline at once; CloudKit's `ifServerRecordUnchanged`
/// save policy should prevent that, and this is the fallback.
public enum SyncResolver {
    public enum Decision: Equatable, Sendable {
        case acceptIncoming
        case keepCached
    }

    public static func resolve<T: Versioned & Equatable>(cached: T?, incoming: T) -> Decision {
        guard let cached else { return .acceptIncoming }
        if incoming.version != cached.version {
            return incoming.version > cached.version ? .acceptIncoming : .keepCached
        }
        if incoming == cached { return .keepCached }
        if incoming.updatedAt != cached.updatedAt {
            return incoming.updatedAt > cached.updatedAt ? .acceptIncoming : .keepCached
        }
        return incoming.updatedBy > cached.updatedBy ? .acceptIncoming : .keepCached
    }

    /// Merges incoming rules into the cache by id. Rules missing from `incoming` are kept,
    /// because deletion is expressed as `enabled = false` with a newer version.
    public static func merge(cached: [InterventionRule], incoming: [InterventionRule]) -> [InterventionRule] {
        var byID = Dictionary(uniqueKeysWithValues: cached.map { ($0.id, $0) })
        for rule in incoming where resolve(cached: byID[rule.id], incoming: rule) == .acceptIncoming {
            byID[rule.id] = rule
        }
        return byID.values.sorted { $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name < $1.name }
    }
}
