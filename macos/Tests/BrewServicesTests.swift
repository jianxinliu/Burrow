//
//  BrewServicesTests.swift
//  BurrowTests
//
//  Pure parser for `brew services list --json` (plan §P3).
//

import XCTest
@testable import Burrow

final class BrewServicesTests: XCTestCase {
    func testParse_readsNameStatusUser_runningFirst() {
        let json = """
        [
          {"name":"redis","status":"none","user":null,"file":"/x"},
          {"name":"postgresql@14","status":"started","user":"henry","file":"/y"},
          {"name":"nginx","status":"started","user":"henry","file":"/z"}
        ]
        """
        let s = BrewServices.parse(json)
        XCTAssertEqual(s.map(\.name), ["nginx", "postgresql@14", "redis"], "running first, then alphabetical")
        XCTAssertTrue(s.first { $0.name == "postgresql@14" }?.running ?? false)
        XCTAssertFalse(s.first { $0.name == "redis" }?.running ?? true)
        XCTAssertEqual(s.first { $0.name == "postgresql@14" }?.user, "henry")
    }

    func testParse_emptyOrGarbageIsEmpty() {
        XCTAssertTrue(BrewServices.parse("").isEmpty)
        XCTAssertTrue(BrewServices.parse("not json").isEmpty)
        XCTAssertTrue(BrewServices.parse("[]").isEmpty)
    }

    func testParse_dropsRowsMissingRequiredFields() {
        let json = #"[{"status":"started"},{"name":"ok","status":"stopped"}]"#
        XCTAssertEqual(BrewServices.parse(json).map(\.name), ["ok"])
    }
}
