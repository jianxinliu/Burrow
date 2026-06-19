//
//  QueryEventsTests.swift
//  BurrowTests
//
//  The SSE /events auth gate (roadmap B.6): the token parse is pure, so it's
//  unit-tested without a socket. (The streaming itself is exercised by hand.)
//

import XCTest
@testable import Burrow

final class QueryEventsTests: XCTestCase {
    func testEventsToken_parsesTokenParam() {
        XCTAssertEqual(QueryServer.eventsToken(from: "/events?token=abc123"), "abc123")
        XCTAssertEqual(QueryServer.eventsToken(from: "/events?foo=1&token=xy&bar=2"), "xy")
    }

    func testEventsToken_absent_isEmpty() {
        XCTAssertEqual(QueryServer.eventsToken(from: "/events"), "")
        XCTAssertEqual(QueryServer.eventsToken(from: "/events?foo=1"), "")
    }
}
