//
//  MetricTests.swift
//  BurrowTests
//
//  The Metric projection table: the ONE place the "0 / −1 means missing"
//  rules live. These rules were re-implemented in three view models (with
//  drift: HistoryLoader honestly skipped gpu < 0 while the sparklines
//  painted a fake max(0, …) zero) — the table makes the honest rule the
//  only rule, and the views become dumb projections.
//

import XCTest
@testable import Burrow

final class MetricTests: XCTestCase {
    /// Full-featured `mo status --json` fixture. Knobs cover every
    /// missing-data rule the table owns.
    private func status(gpuUsage: Double = 37,
                        cpuTemp: Double = 55, gpuTemp: Double = 48, batteryTemp: Double? = 31,
                        fanCount: Int? = 2, fanSpeed: Int = 1200,
                        battery: Bool = true,
                        rx: [Double] = [1.5, 0.5], tx: [Double] = [0.25, 0.25]) throws -> MoleStatus {
        let nets = zip(rx, tx).enumerated().map { i, r in
            "{\"name\":\"en\(i)\",\"rx_rate_mbs\":\(r.0),\"tx_rate_mbs\":\(r.1),\"ip\":\"10.0.0.\(i)\"}"
        }.joined(separator: ",")
        let batteries = battery
            ? "\"batteries\":[{\"percent\":88,\"status\":\"ok\",\"time_left\":\"2h\",\"health\":\"good\",\"cycle_count\":10,\"capacity\":95}],"
            : ""
        let fc = fanCount.map { ",\"fan_count\":\($0)" } ?? ""
        let bt = batteryTemp.map { ",\"battery_temp\":\($0)" } ?? ""
        let json = """
        {"collected_at":"2026-06-08T03:16:25.068057-07:00","host":"h","platform":"darwin",
         "uptime_seconds":100,"procs":1,
         "hardware":{"model":"Mac","cpu_model":"M","total_ram":"24 GB","disk_size":"460 GB","os_version":"26"},
         "health_score":90,"health_score_msg":"Good",
         "cpu":{"usage":42.5,"load1":1.5,"load5":1,"load15":1,"core_count":10,"logical_cpu":10},
         "memory":{"used":1,"total":2,"used_percent":50,"swap_used":0,"swap_total":0,"pressure":""},
         "disk_io":{"read_rate":12.5,"write_rate":3.5},
         "network":[\(nets)],
         \(batteries)
         "thermal":{"cpu_temp":\(cpuTemp),"gpu_temp":\(gpuTemp)\(bt),"fan_speed":\(fanSpeed)\(fc),"system_power":10},
         "gpu":[{"name":"G","usage":\(gpuUsage),"memory_used":1,"memory_total":2,"core_count":10}],
         "top_processes":[]}
        """
        return try JSONDecoder().decode(MoleStatus.self, from: Data(json.utf8))
    }

    func testValue_projectsEveryMetricFromAFullSnapshot() throws {
        let s = try status()
        XCTAssertEqual(Metric.cpuUsage.value(in: s), 42.5)
        XCTAssertEqual(Metric.cpuLoad1.value(in: s), 1.5)
        XCTAssertEqual(Metric.memoryUsedPercent.value(in: s), 50)
        XCTAssertEqual(Metric.gpuUsage.value(in: s), 37)
        XCTAssertEqual(Metric.diskRead.value(in: s), 12.5)
        XCTAssertEqual(Metric.diskWrite.value(in: s), 3.5)
        XCTAssertEqual(Metric.networkRx.value(in: s), 2.0, "sums every interface")
        XCTAssertEqual(Metric.networkTx.value(in: s), 0.5)
        XCTAssertEqual(Metric.thermalCPU.value(in: s), 55)
        XCTAssertEqual(Metric.thermalGPU.value(in: s), 48)
        XCTAssertEqual(Metric.thermalBattery.value(in: s), 31)
        XCTAssertEqual(Metric.fanSpeed.value(in: s), 1200)
        XCTAssertEqual(Metric.batteryPercent.value(in: s), 88)
        XCTAssertEqual(Metric.healthScore.value(in: s), 90)
    }

    func testValue_missingDataIsNilNeverAFakeZero() throws {
        // gpu usage −1 = "platform can't report" → nil, not 0.
        XCTAssertNil(Metric.gpuUsage.value(in: try status(gpuUsage: -1)))
        // thermal 0 = "no unprivileged sensor" → nil, never synthesized.
        XCTAssertNil(Metric.thermalCPU.value(in: try status(cpuTemp: 0)))
        XCTAssertNil(Metric.thermalGPU.value(in: try status(gpuTemp: 0)))
        XCTAssertNil(Metric.thermalBattery.value(in: try status(batteryTemp: nil)))
        XCTAssertNil(Metric.thermalBattery.value(in: try status(batteryTemp: 0)))
        // No battery hardware → nil.
        XCTAssertNil(Metric.batteryPercent.value(in: try status(battery: false)))
    }

    func testValue_fanSpeedGatesOnFanCountButParkedIsData() throws {
        // fan_count 0/absent = "couldn't read any fan" → nil…
        XCTAssertNil(Metric.fanSpeed.value(in: try status(fanCount: 0)))
        XCTAssertNil(Metric.fanSpeed.value(in: try status(fanCount: nil)))
        // …but a detected fan at 0 RPM is parked — a real, honest 0.
        XCTAssertEqual(Metric.fanSpeed.value(in: try status(fanCount: 2, fanSpeed: 0)), 0)
    }

    // MARK: series(of:) — one decode pass, drift included

    func testSeriesBundle_projectsAllRequestedMetricsAndCountsDrift() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("burrow-metric-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let db = try DB(at: tempDir.appendingPathComponent("burrow.db"))
        MetricsStore.resetDriftCounters()

        let good = """
        {"collected_at":"2026-06-08T03:16:25.068057-07:00","host":"h","platform":"darwin",
         "uptime_seconds":100,"procs":1,
         "hardware":{"model":"Mac","cpu_model":"M","total_ram":"24 GB","disk_size":"460 GB","os_version":"26"},
         "health_score":90,"health_score_msg":"Good",
         "cpu":{"usage":42.5,"load1":1.5,"load5":1,"load15":1,"core_count":10,"logical_cpu":10},
         "memory":{"used":1,"total":2,"used_percent":50,"swap_used":0,"swap_total":0,"pressure":""},
         "disk_io":{"read_rate":12.5,"write_rate":3.5},
         "gpu":[{"name":"G","usage":-1,"memory_used":1,"memory_total":2,"core_count":10}],
         "top_processes":[]}
        """
        try db.insert(prefix: MetricsStore.snapshotPrefix, ts: 100, json: good)
        try db.insert(prefix: MetricsStore.snapshotPrefix, ts: 200, json: "drifted")

        let bundle = MetricsStore(db: db).series(of: [.cpuUsage, .gpuUsage],
                                                 MetricsStore.Window(since: 0, until: 1000))
        XCTAssertEqual(bundle.series[.cpuUsage]?.map(\.ts), [100])
        XCTAssertEqual(bundle.series[.cpuUsage]?.map(\.value), [42.5])
        XCTAssertEqual(bundle.series[.gpuUsage]?.count, 0, "gpu −1 projects to no point, not a fake zero")
        XCTAssertEqual(bundle.droppedRows, 1)
        XCTAssertNotNil(bundle.firstSkip)
    }
}
