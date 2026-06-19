//
//  MCPDiffTests.swift
//  BurrowTests
//
//  End-to-end for burrow_diff v1 (roadmap B.8 agent surface): seed two
//  snapshots and assert the process-membership + disk-delta diff through the
//  real dispatch path.
//

import XCTest
@testable import Burrow

final class MCPDiffTests: XCTestCase {
    private var tempDir: URL!
    private var db: DB!
    private var catalog: ToolCatalog!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("burrow-diff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        db = try DB(at: tempDir.appendingPathComponent("burrow.db"))
        catalog = ToolCatalog(db: db)
    }

    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Snapshot with a "/" volume at `freeGB` free of 500 GB and the given
    /// process names in top_processes.
    private func snapshot(freeGB: Int64, procs: [String]) -> String {
        let total: Int64 = 500_000_000_000
        let used = total - freeGB * 1_000_000_000
        let procJSON = procs.map {
            "{\"pid\":1,\"name\":\"\($0)\",\"command\":\"/bin/\($0)\",\"cpu\":10,\"memory\":5}"
        }.joined(separator: ",")
        return """
        {"collected_at":"2026-06-08T03:16:25.068057-07:00","host":"h","platform":"darwin","uptime_seconds":100,"procs":1,
         "hardware":{"model":"Mac","cpu_model":"M","total_ram":"24 GB","disk_size":"460 GB","os_version":"26"},
         "health_score":90,"health_score_msg":"Good",
         "cpu":{"usage":10,"load1":1,"load5":1,"load15":1,"core_count":10,"logical_cpu":10},
         "memory":{"used":100,"total":200,"used_percent":50,"swap_used":0,"swap_total":0,"pressure":""},
         "disk_io":{"read_rate":0,"write_rate":0},
         "disks":[{"mount":"/","used":\(used),"total":\(total),"used_percent":50,"external":false}],
         "top_processes":[\(procJSON)]}
        """
    }

    func testDiff_reportsProcessChurnAndDiskDelta() throws {
        let now = Int(Date().timeIntervalSince1970)
        let then = now - 3600
        // Older: chrome+xcode, 200 GB free. Newer: chrome+docker, 150 GB free.
        try db.insert(prefix: MetricsStore.snapshotPrefix, ts: then,
                      json: snapshot(freeGB: 200, procs: ["chrome", "xcode"]))
        try db.insert(prefix: MetricsStore.snapshotPrefix, ts: now,
                      json: snapshot(freeGB: 150, procs: ["chrome", "docker"]))

        let json = try catalog.call(name: "burrow_diff", arguments: ["since": then - 10])
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any], json)
        XCTAssertEqual(o["processes_entered"] as? [String], ["docker"], json)
        XCTAssertEqual(o["processes_left"] as? [String], ["xcode"], json)
        // 150 GB − 200 GB = −50 GB.
        let delta = try XCTUnwrap((o["disk_free_delta_bytes"] as? NSNumber)?.int64Value, json)
        XCTAssertEqual(delta, -50_000_000_000)
    }

    func testDiff_reportsLoginItemChurn() throws {
        let now = Int(Date().timeIntervalSince1970)
        let then = now - 3600
        // Two snapshots (the process/disk diff needs them).
        try db.insert(prefix: MetricsStore.snapshotPrefix, ts: then, json: snapshot(freeGB: 100, procs: ["a"]))
        try db.insert(prefix: MetricsStore.snapshotPrefix, ts: now, json: snapshot(freeGB: 100, procs: ["a"]))
        // Two login-item inventories — a new persistence item appeared.
        try db.insert(prefix: Maintenance.startupInvPrefix, ts: then, json: "[\"/A.plist\"]")
        try db.insert(prefix: Maintenance.startupInvPrefix, ts: now, json: "[\"/A.plist\",\"/evil.plist\"]")

        let json = try catalog.call(name: "burrow_diff", arguments: ["since": then - 10])
        let o = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any], json)
        XCTAssertEqual(o["login_items_added"] as? [String], ["/evil.plist"], json)
        XCTAssertEqual(o["login_items_removed"] as? [String], [], json)
    }

    func testDiff_tooFewSnapshots_reportsError() throws {
        let now = Int(Date().timeIntervalSince1970)
        try db.insert(prefix: MetricsStore.snapshotPrefix, ts: now,
                      json: snapshot(freeGB: 100, procs: ["chrome"]))
        let json = try catalog.call(name: "burrow_diff", arguments: [:])
        XCTAssertTrue(json.contains("need at least two snapshots"), json)
    }
}
