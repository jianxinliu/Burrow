//
//  FolderGrowthTests.swift
//  BurrowTests
//
//  Growth attribution diff (roadmap A.3).
//

import XCTest
@testable import Burrow

final class FolderGrowthTests: XCTestCase {
    func testDiff_reportsGrowersBiggestFirst() {
        let changes = FolderGrowth.diff(
            old: ["~/Downloads": 100, "~/Documents": 50],
            new: ["~/Downloads": 300, "~/Documents": 50, "~/Movies": 80])
        XCTAssertEqual(changes.map(\.path), ["~/Downloads", "~/Movies"], "growers, biggest first")
        XCTAssertEqual(changes.first?.deltaBytes, 200)
        XCTAssertFalse(changes.contains { $0.path == "~/Documents" }, "unchanged folders dropped")
    }

    func testDiff_newFolderCountsFullSize() {
        let changes = FolderGrowth.diff(old: [:], new: ["~/New": 42])
        XCTAssertEqual(changes, [.init(path: "~/New", deltaBytes: 42)])
    }

    func testDiff_shrinkersSortLast() {
        let changes = FolderGrowth.diff(old: ["a": 100], new: ["a": 10, "b": 5])
        XCTAssertEqual(changes.map(\.path), ["b", "a"])
        XCTAssertEqual(changes.last?.deltaBytes, -90)
    }
}
