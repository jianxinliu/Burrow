//
//  TimeMachineTests.swift
//  BurrowTests
//
//  tmutil output parsing (roadmap D.14), tested with real tmutil fixtures.
//

import XCTest
@testable import Burrow

final class TimeMachineTests: XCTestCase {
    func testLatestBackup_extractsToken() {
        let out = "/Volumes/.timemachine/Mac/2026-06-15-143000.backup\n"
        XCTAssertEqual(TimeMachine.latestBackupToken(out), "2026-06-15-143000")
    }

    func testLatestBackup_noBackup_isNil() {
        XCTAssertNil(TimeMachine.latestBackupToken(""))
        XCTAssertNil(TimeMachine.latestBackupToken("No backups found.\n"))
    }

    func testLocalSnapshots_listsAllTokens() {
        let out = """
        Snapshots for volume group containing disk /:
        com.apple.TimeMachine.2026-06-14-010000.local
        com.apple.TimeMachine.2026-06-15-020000.local
        """
        XCTAssertEqual(TimeMachine.localSnapshotTokens(out),
                       ["2026-06-14-010000", "2026-06-15-020000"])
    }

    func testDateFromToken_parsesUTC() throws {
        let d = try XCTUnwrap(TimeMachine.date(fromToken: "2026-06-15-143000"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour], from: d)
        XCTAssertEqual(c.year, 2026)
        XCTAssertEqual(c.month, 6)
        XCTAssertEqual(c.day, 15)
        XCTAssertEqual(c.hour, 14)
    }

    func testDateFromToken_malformed_isNil() {
        XCTAssertNil(TimeMachine.date(fromToken: "not-a-date"))
    }
}
