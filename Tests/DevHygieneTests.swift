//
//  DevHygieneTests.swift
//  BurrowTests
//
//  Dev-hygiene ecosystem catalog (roadmap C.9).
//

import XCTest
@testable import Burrow

final class DevHygieneTests: XCTestCase {
    func testCatalog_coversTheMajorEcosystems() {
        let names = Set(DevHygiene.catalog(home: "/Users/x").map(\.name))
        for expected in ["Xcode", "Homebrew", "npm", "Cargo", "Docker"] {
            XCTAssertTrue(names.contains(expected), "catalog is missing \(expected)")
        }
    }

    func testCatalog_pathsResolveUnderHome() {
        let cat = DevHygiene.catalog(home: "/Users/x")
        let xcode = cat.first { $0.name == "Xcode" }
        XCTAssertTrue(xcode?.paths.contains("/Users/x/Library/Developer/Xcode/DerivedData") ?? false)
        XCTAssertTrue(cat.allSatisfy { $0.paths.allSatisfy { $0.hasPrefix("/Users/x/") } })
    }

    func testTotal_sumsSizes() {
        XCTAssertEqual(DevHygiene.total([100, 200, 300]), 600)
    }
}
