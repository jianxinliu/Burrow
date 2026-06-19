//
//  AnsiTests.swift
//  BurrowTests
//

import XCTest
@testable import Burrow

final class AnsiTests: XCTestCase {
    func testStrip_removesColourCodes_keepsText() {
        XCTAssertEqual(Ansi.strip("\u{1B}[0;32mhello\u{1B}[0m"), "hello")
    }

    func testStrip_removesCursorAndClearSequences() {
        XCTAssertEqual(Ansi.strip("a\u{1B}[2Jb\u{1B}[1;1Hc"), "abc")
    }

    func testStrip_leavesPlainTextUntouched() {
        XCTAssertEqual(Ansi.strip("just plain text"), "just plain text")
        XCTAssertEqual(Ansi.strip(""), "")
    }

    func testStrip_handlesTrailingLoneEscape() {
        // A bare ESC with no following '[' is kept (incomplete sequence).
        XCTAssertEqual(Ansi.strip("x\u{1B}"), "x\u{1B}")
    }
}
