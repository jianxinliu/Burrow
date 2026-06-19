//
//  MCPPortsTests.swift
//  BurrowTests
//
//  burrow_ports shape (roadmap C.10). The enumeration is native + machine-
//  dependent (can't assert specific ports on a CI runner), so this asserts the
//  reply is well-formed JSON with the documented fields, exercising the real
//  dispatch + PortEnumerator → PortInspector path.
//

import XCTest
@testable import Burrow

final class MCPPortsTests: XCTestCase {
    private var tempDir: URL!
    private var db: DB!
    private var catalog: ToolCatalog!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("burrow-ports-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        db = try DB(at: tempDir.appendingPathComponent("burrow.db"))
        catalog = ToolCatalog(db: db)
    }

    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testPorts_returnsWellFormedJSON() throws {
        let json = try catalog.call(name: "burrow_ports", arguments: [:])
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any], json)
        XCTAssertNotNil(o["count"] as? Int, json)
        let ports = try XCTUnwrap(o["ports"] as? [[String: Any]], json)
        // Each entry, if any, carries the documented fields.
        for p in ports {
            XCTAssertNotNil(p["pid"] as? Int)
            XCTAssertNotNil(p["port"] as? Int)
            XCTAssertNotNil(p["proto"] as? String)
        }
    }

    func testPorts_isListedInCatalog() {
        XCTAssertTrue(catalog.descriptors().compactMap { $0["name"] as? String }.contains("burrow_ports"))
    }
}
