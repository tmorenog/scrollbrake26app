import XCTest
@testable import BreakScrollCore

final class SyncResolverTests: XCTestCase {
    private let id = UUID()

    private func rule(_ version: Int, interval: TimeInterval = 900, at seconds: TimeInterval = 0, by: String = "parentA") -> InterventionRule {
        InterventionRule(
            id: id, name: "Social", usageInterval: interval,
            version: version, updatedAt: Date(timeIntervalSince1970: seconds), updatedBy: by
        )
    }

    func testNothingCachedAcceptsIncoming() {
        XCTAssertEqual(SyncResolver.resolve(cached: nil, incoming: rule(1)), .acceptIncoming)
    }

    func testHigherVersionWinsEvenWithAnOlderClock() {
        // Parent changes 15 min → 10 min; version 42 → 43, but the parent's clock is behind.
        let cached = rule(42, interval: 900, at: 2_000)
        let incoming = rule(43, interval: 600, at: 1_000)
        XCTAssertEqual(SyncResolver.resolve(cached: cached, incoming: incoming), .acceptIncoming)
    }

    func testStaleIncomingIsRejected() {
        XCTAssertEqual(SyncResolver.resolve(cached: rule(43), incoming: rule(42, at: 9_999)), .keepCached)
    }

    func testDuplicateDeliveryIsANoOp() {
        XCTAssertEqual(SyncResolver.resolve(cached: rule(43), incoming: rule(43)), .keepCached)
    }

    func testConflictingEqualVersionsBreakTiesDeterministically() {
        let a = rule(43, interval: 600, at: 1_000, by: "parentA")
        let b = rule(43, interval: 300, at: 1_001, by: "parentB")
        XCTAssertEqual(SyncResolver.resolve(cached: a, incoming: b), .acceptIncoming)
        XCTAssertEqual(SyncResolver.resolve(cached: b, incoming: a), .keepCached)

        let c = rule(43, interval: 300, at: 1_000, by: "parentB")
        XCTAssertEqual(SyncResolver.resolve(cached: a, incoming: c), .acceptIncoming)
        XCTAssertEqual(SyncResolver.resolve(cached: c, incoming: a), .keepCached)
    }

    func testMergeKeepsUnknownRulesAndUpdatesKnownOnes() {
        let other = InterventionRule(name: "Video", version: 1)
        let merged = SyncResolver.merge(cached: [rule(1), other], incoming: [rule(2, interval: 300)])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first { $0.id == id }?.usageInterval, 300)
        XCTAssertTrue(merged.contains(other))
    }
}
