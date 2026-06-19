//
//  StartupWatcherTests.swift
//  BurrowTests
//
//  New-persistence-item detection (roadmap D.12), tested through newlyAppeared.
//

import XCTest
@testable import Burrow

final class StartupWatcherTests: XCTestCase {
    private func item(_ path: String) -> StartupItem {
        StartupItem(label: path, kind: .launchAgent, scope: .user,
                    plistPath: path, executable: "/bin/x", problem: nil)
    }

    func testNewlyAppeared_returnsOnlyAddedItems() {
        let appeared = StartupWatcher.newlyAppeared(
            previousIDs: ["/a", "/b"], current: [item("/a"), item("/b"), item("/c")])
        XCTAssertEqual(appeared.map(\.id), ["/c"])
    }

    func testNewlyAppeared_noBaseline_treatsAllAsNew() {
        // First run: caller must suppress alerts when there's no baseline.
        let appeared = StartupWatcher.newlyAppeared(previousIDs: [], current: [item("/a"), item("/b")])
        XCTAssertEqual(Set(appeared.map(\.id)), ["/a", "/b"])
    }

    func testNewlyAppeared_nothingNew_isEmpty() {
        XCTAssertTrue(StartupWatcher.newlyAppeared(
            previousIDs: ["/a", "/old"], current: [item("/a")]).isEmpty)
    }

    // MARK: check (baseline fold)

    func testCheck_firstRun_alertsNothingButSetsBaseline() {
        let r = StartupWatcher.check(previousBaselineJSON: nil, current: [item("/a"), item("/b")])
        XCTAssertTrue(r.newItems.isEmpty, "no baseline → don't alarm on everything")
        XCTAssertTrue(r.baselineJSON.contains("/a") && r.baselineJSON.contains("/b"))
    }

    func testCheck_subsequentRun_reportsAppearance() {
        let first = StartupWatcher.check(previousBaselineJSON: nil, current: [item("/a")])
        let second = StartupWatcher.check(previousBaselineJSON: first.baselineJSON,
                                          current: [item("/a"), item("/evil")])
        XCTAssertEqual(second.newItems.map(\.id), ["/evil"])
    }

    func testCheck_emptyBaseline_treatedAsFirstRun() {
        let r = StartupWatcher.check(previousBaselineJSON: "[]", current: [item("/a")])
        XCTAssertTrue(r.newItems.isEmpty)
    }
}
