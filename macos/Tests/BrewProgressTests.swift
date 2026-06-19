//
//  BrewProgressTests.swift
//  BurrowTests
//
//  Brew-upgrade progress parsing (roadmap H).
//

import XCTest
@testable import Burrow

final class BrewProgressTests: XCTestCase {
    func testHeaderLines_becomePhrases() {
        XCTAssertEqual(BrewProgress.phrase("==> Pouring foo--1.1.bottle.tar.gz"),
                       "Pouring foo--1.1.bottle.tar.gz")
        XCTAssertEqual(BrewProgress.phrase("==> Downloading https://example.com/foo"),
                       "Downloading https://example.com/foo")
    }

    func testNonHeaderLines_areNoise() {
        XCTAssertNil(BrewProgress.phrase("Already up-to-date."))
        XCTAssertNil(BrewProgress.phrase(""))
        XCTAssertNil(BrewProgress.phrase("  some progress bar  "))
    }

    func testEmptyHeader_isNil() {
        XCTAssertNil(BrewProgress.phrase("==>   "))
    }
}
