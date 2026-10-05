import XCTest
@testable import BreakScrollCore

final class PasscodeLockoutTests: XCTestCase {
    func testLocksAfterFreeAttemptsWithDoublingDelay() {
        var lockout = PasscodeLockout()
        let start = Date(timeIntervalSince1970: 0)
        for _ in 0..<4 { lockout.recordFailure(at: start) }
        XCTAssertFalse(lockout.isLocked(at: start))

        lockout.recordFailure(at: start)  // 5th
        XCTAssertTrue(lockout.isLocked(at: start.addingTimeInterval(59)))
        XCTAssertFalse(lockout.isLocked(at: start.addingTimeInterval(60)))

        lockout.recordFailure(at: start.addingTimeInterval(60))  // 6th
        XCTAssertTrue(lockout.isLocked(at: start.addingTimeInterval(179)))
        XCTAssertFalse(lockout.isLocked(at: start.addingTimeInterval(180)))

        for _ in 0..<20 { lockout.recordFailure(at: start) }
        XCTAssertEqual(lockout.lockedUntil, start.addingTimeInterval(3600), "capped at an hour")
    }

    func testSuccessResets() throws {
        var lockout = PasscodeLockout()
        for _ in 0..<6 { lockout.recordFailure(at: Date()) }
        lockout.recordSuccess()
        XCTAssertFalse(lockout.isLocked(at: Date()))
        XCTAssertEqual(lockout.failures, 0)
        XCTAssertEqual(try JSONDecoder().decode(PasscodeLockout.self, from: JSONEncoder().encode(lockout)), lockout)
    }
}
