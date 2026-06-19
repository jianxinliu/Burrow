//
//  MetricsPrometheusTests.swift
//  BurrowTests
//
//  The Prometheus text-exposition formatter (roadmap B7): a pure
//  MoleStatus → exposition-text function, so a dev with Grafana can scrape
//  their Mac. Tested through the public `exposition(from:)` only.
//

import XCTest
@testable import Burrow

final class MetricsPrometheusTests: XCTestCase {
    private func decode(_ json: String) throws -> MoleStatus {
        try JSONDecoder().decode(MoleStatus.self, from: Data(json.utf8))
    }

    /// Minimal valid snapshot; disks/network/gpu/battery are optional and
    /// added per-test where the behavior needs them.
    private func base(cpu: Double = 42,
                      extra: String = "") -> String {
        """
        {"collected_at":"2026-06-08T03:16:25.068057-07:00","host":"h","platform":"darwin","uptime_seconds":100,"procs":1,
         "hardware":{"model":"Mac","cpu_model":"M","total_ram":"24 GB","disk_size":"460 GB","os_version":"26"},
         "health_score":90,"health_score_msg":"Good",
         "cpu":{"usage":\(cpu),"load1":1.5,"load5":1,"load15":1,"core_count":10,"logical_cpu":10},
         "memory":{"used":100,"total":200,"used_percent":50,"swap_used":0,"swap_total":0,"pressure":""},
         "disk_io":{"read_rate":0,"write_rate":0},
         "top_processes":[]\(extra)}
        """
    }

    func testExposition_cpuUsageGauge() throws {
        let out = MetricsPrometheus.exposition(from: try decode(base(cpu: 42)))
        XCTAssertTrue(out.contains("# TYPE burrow_cpu_usage_percent gauge"), out)
        XCTAssertTrue(out.contains("\nburrow_cpu_usage_percent 42\n"), out)
    }

    func testExposition_memoryAndHealthGauges() throws {
        let out = MetricsPrometheus.exposition(from: try decode(base()))
        XCTAssertTrue(out.contains("\nburrow_memory_used_bytes 100\n"), out)
        XCTAssertTrue(out.contains("\nburrow_memory_used_percent 50\n"), out)
        XCTAssertTrue(out.contains("\nburrow_health_score 90\n"), out)
    }

    func testExposition_disksAndNetworkAreLabeledSeries() throws {
        let extra = """
        ,"disks":[{"mount":"/","used":40,"total":100,"used_percent":40,"external":false}],
         "network":[{"name":"en0","rx_rate_mbs":1.5,"tx_rate_mbs":0.25,"ip":"10.0.0.2"}],
         "batteries":[{"percent":80,"status":"","time_left":"","health":"Good","cycle_count":120,"capacity":95}],
         "gpu":[{"name":"M","usage":12,"memory_used":0,"memory_total":0,"core_count":10}]
        """
        let out = MetricsPrometheus.exposition(from: try decode(base(extra: extra)))
        XCTAssertTrue(out.contains("burrow_disk_used_bytes{mount=\"/\"} 40"), out)
        XCTAssertTrue(out.contains("burrow_disk_free_bytes{mount=\"/\"} 60"), out)
        XCTAssertTrue(out.contains("burrow_network_rx_mbps{interface=\"en0\"} 1.5"), out)
        XCTAssertTrue(out.contains("burrow_battery_percent 80"), out)
        XCTAssertTrue(out.contains("burrow_gpu_usage_percent 12"), out)
    }

    func testExposition_omitsGpuWhenUnavailable() throws {
        let extra = #","gpu":[{"name":"M","usage":-1,"memory_used":0,"memory_total":0,"core_count":10}]"#
        let out = MetricsPrometheus.exposition(from: try decode(base(extra: extra)))
        XCTAssertFalse(out.contains("burrow_gpu_usage_percent"), out)
    }
}
