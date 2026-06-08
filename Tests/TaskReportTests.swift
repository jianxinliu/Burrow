//
//  TaskReportTests.swift
//  BurrowTests
//
//  parseTaskReport turns streamed `mo clean`/`mo optimize` output into
//  themed cards plus a summary. Two summary shapes exist: the dry-run
//  preview ("Potential space: …") and the real run's footer ("Tracked
//  cleanup: … / Free space change: … / Free space now: …"). The real-run
//  footer was previously unparsed, so the "Cleaned" banner came up blank.
//

import XCTest
@testable import Burrow

final class TaskReportTests: XCTestCase {
    // Real `mo clean` footer — the numbers users actually care about
    // post-run are how much was freed and how much is now free.
    func testParsesRealRunSummary() throws {
        let lines = [
            "======================================================================",
            "Cleanup complete",
            "Tracked cleanup: 1.02GB | Items cleaned: 337 | Categories: 35",
            "Free space change: +1.39GB",
            "Free space now: 2.50GB",
            "======================================================================",
        ]
        let summary = try XCTUnwrap(parseTaskReport(lines).summary)
        XCTAssertEqual(summary.space, "1.02GB")
        XCTAssertEqual(summary.items, "337")
        XCTAssertEqual(summary.categories, "35")
        XCTAssertEqual(summary.freeChange, "+1.39GB")
        XCTAssertEqual(summary.freeNow, "2.50GB")
    }

    // The dry-run preview packs everything onto one line and has no
    // free-space figures (nothing was actually deleted). Guards the
    // refactor that unified both summary shapes.
    func testParsesDryRunSummary() throws {
        let lines = [
            "➤ Developer tools",
            "  → npm cache, 191.8MB",
            "Potential space: 383.8MB | Items: 372 | Categories: 20",
        ]
        let result = parseTaskReport(lines)
        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.space, "383.8MB")
        XCTAssertEqual(summary.items, "372")
        XCTAssertEqual(summary.categories, "20")
        XCTAssertEqual(summary.freeChange, "", "dry-run frees nothing yet")
        XCTAssertEqual(summary.freeNow, "")
        XCTAssertEqual(result.groups.count, 1)
    }
}
