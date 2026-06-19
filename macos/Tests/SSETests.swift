//
//  SSETests.swift
//  BurrowTests
//
//  SSE wire framing (roadmap B.6), tested through `event`/`comment`.
//

import XCTest
@testable import Burrow

final class SSETests: XCTestCase {
    func testEvent_singleLine() {
        let s = SSEFrame.event("alert", data: "{\"k\":1}")
        XCTAssertEqual(s, "event: alert\ndata: {\"k\":1}\n\n")
    }

    func testEvent_withId() {
        let s = SSEFrame.event("alert", data: "x", id: 7)
        XCTAssertTrue(s.hasPrefix("id: 7\nevent: alert\n"))
    }

    func testEvent_multiLineDataGetsPerLinePrefix() {
        let s = SSEFrame.event("log", data: "line1\nline2")
        XCTAssertTrue(s.contains("data: line1\n"))
        XCTAssertTrue(s.contains("data: line2\n"))
        XCTAssertTrue(s.hasSuffix("\n\n"), "event terminates with a blank line")
    }

    func testComment_isIgnorableKeepAlive() {
        XCTAssertEqual(SSEFrame.comment("keep-alive"), ": keep-alive\n\n")
    }
}
