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
}
