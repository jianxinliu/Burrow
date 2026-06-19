//
//  AgentAuditTests.swift
//  BurrowTests
//
//  Agent-audit record encoding (roadmap B.5), tested through encode/decode.
//

import XCTest
@testable import Burrow

final class AgentAuditTests: XCTestCase {
    private let entry = AgentAudit.Entry(
        tool: "burrow_clean", client: "claude-code", dryRun: true,
        durationMs: 42, ok: true, summary: "would free 1.2 GB",
        argsJSON: "{\"confirm\":false}")

    func testEncodeDecode_roundTrips() {
        let json = AgentAudit.encode(entry)
        XCTAssertEqual(AgentAudit.decode(json), entry)
    }

    func testEncode_isKeySortedAndCarriesFields() {
        let json = AgentAudit.encode(entry)
        XCTAssertTrue(json.contains("\"tool\":\"burrow_clean\""))
        XCTAssertTrue(json.contains("\"client\":\"claude-code\""))
        XCTAssertTrue(json.contains("\"dryRun\":true"))
        // sortedKeys → "client" precedes "tool"
        let ci = json.range(of: "\"client\"")!.lowerBound
        let ti = json.range(of: "\"tool\"")!.lowerBound
        XCTAssertLessThan(ci, ti, "keys are sorted for deterministic rows")
    }

    func testDecode_garbage_isNil() {
        XCTAssertNil(AgentAudit.decode("not json"))
    }
}
