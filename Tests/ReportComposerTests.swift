//
//  ReportComposerTests.swift
//  BurrowTests
//
//  The history→report-input gather (roadmap A.4), shared by the Home card and
//  burrow_report. Seeds snapshots and asserts the composed Input.
//

import XCTest
@testable import Burrow

final class ReportComposerTests: XCTestCase {
    private var tempDir: URL!
    private var db: DB!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("burrow-rc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        db = try DB(at: tempDir.appendingPathComponent("burrow.db"))
    }

    override func tearDown() {
        db = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func snapshot(freeGB: Int64, proc: String) -> String {
        let total: Int64 = 500_000_000_000
        let used = total - freeGB * 1_000_000_000
        return """
        {"collected_at":"2026-06-08T03:16:25.068057-07:00","host":"h","platform":"darwin","uptime_seconds":100,"procs":1,
         "hardware":{"model":"Mac","cpu_model":"M","total_ram":"24 GB","disk_size":"460 GB","os_version":"26"},
         "health_score":90,"health_score_msg":"Good",
         "cpu":{"usage":10,"load1":1,"load5":1,"load15":1,"core_count":10,"logical_cpu":10},
         "memory":{"used":100,"total":200,"used_percent":50,"swap_used":0,"swap_total":0,"pressure":""},
         "disk_io":{"read_rate":0,"write_rate":0},
         "disks":[{"mount":"/","used":\(used),"total":\(total),"used_percent":50,"external":false}],
         "top_processes":[{"pid":1,"name":"\(proc)","command":"/bin/\(proc)","cpu":80,"memory":5}]}
        """
    }

    func testGather_fillsForecastAndTopEnergy() throws {
        let now = Int(Date().timeIntervalSince1970)
        let day = 86_400
        for d in 0...30 {
            let free = Int64(130_000_000_000) - Int64(d) * 1_000_000_000
            try db.insert(prefix: MetricsStore.snapshotPrefix,
                          ts: now - (30 - d) * day, json: snapshot(freeGB: free / 1_000_000_000, proc: "xcode"))
        }
        let input = ReportComposer.gather(metrics: MetricsStore(db: db), days: 60, now: now)
        XCTAssertEqual(input.periodDays, 60)
        XCTAssertNil(input.spaceReclaimedBytes, "cleanup history isn't a v1 source")
        XCTAssertNotNil(input.forecast?.daysUntilFull, "steady decline yields a forecast")
        XCTAssertEqual(input.topEnergy.first?.name, "xcode")
    }
}
