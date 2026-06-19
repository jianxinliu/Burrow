//
//  MetricsPrometheus.swift
//  Burrow
//
//  Render the latest snapshot as Prometheus text exposition (roadmap B7),
//  served from `GET /metrics?format=prometheus`. Pure: MoleStatus in,
//  exposition text out — so a dev with Grafana can scrape their own Mac in
//  minutes. Gauges only (these are instantaneous readings); per-disk and
//  per-interface values are labeled series.
//

import Foundation

enum MetricsPrometheus {
    static func exposition(from s: MoleStatus) -> String {
        var out = ""
        gauge(&out, "burrow_cpu_usage_percent", "Current CPU usage (percent).", s.cpu.usage)
        gauge(&out, "burrow_load1", "1-minute load average.", s.cpu.load1)
        gauge(&out, "burrow_cpu_cores", "Physical core count.", Double(s.cpu.coreCount))
        gauge(&out, "burrow_memory_used_bytes", "Memory used (bytes).", Double(s.memory.used))
        gauge(&out, "burrow_memory_total_bytes", "Memory total (bytes).", Double(s.memory.total))
        gauge(&out, "burrow_memory_used_percent", "Memory used (percent).", s.memory.usedPercent)
        gauge(&out, "burrow_health_score", "Burrow health score (0-100).", Double(s.healthScore))
        gauge(&out, "burrow_uptime_seconds", "System uptime (seconds).", Double(s.uptimeSeconds))

        // Per-disk + per-interface are labeled series on one metric name.
        labeled(&out, "burrow_disk_used_bytes", "Disk space used (bytes), by mount.",
                s.disks.map { ("mount=\"\(esc($0.mount))\"", Double($0.used)) })
        labeled(&out, "burrow_disk_total_bytes", "Disk total (bytes), by mount.",
                s.disks.map { ("mount=\"\(esc($0.mount))\"", Double($0.total)) })
        labeled(&out, "burrow_disk_free_bytes", "Disk free (bytes), by mount.",
                s.disks.map { ("mount=\"\(esc($0.mount))\"", Double($0.total > $0.used ? $0.total - $0.used : 0)) })
        labeled(&out, "burrow_disk_used_percent", "Disk used (percent), by mount.",
                s.disks.map { ("mount=\"\(esc($0.mount))\"", $0.usedPercent) })
        labeled(&out, "burrow_network_rx_mbps", "Receive rate (MB/s), by interface.",
                s.network.map { ("interface=\"\(esc($0.name))\"", $0.rxRateMbs) })
        labeled(&out, "burrow_network_tx_mbps", "Transmit rate (MB/s), by interface.",
                s.network.map { ("interface=\"\(esc($0.name))\"", $0.txRateMbs) })

        if let b = s.batteries?.first {
            gauge(&out, "burrow_battery_percent", "Battery charge (percent).", b.percent)
            gauge(&out, "burrow_battery_cycle_count", "Battery cycle count.", Double(b.cycleCount))
        }
        if let g = s.gpu?.first, g.usage >= 0 {   // -1 = unavailable on Apple Silicon
            gauge(&out, "burrow_gpu_usage_percent", "GPU usage (percent).", g.usage)
        }
        return out
    }

    private static func gauge(_ out: inout String, _ name: String, _ help: String, _ v: Double) {
        out += "# HELP \(name) \(help)\n# TYPE \(name) gauge\n\(name) \(num(v))\n"
    }

    /// A labeled gauge: one `# HELP`/`# TYPE` then one line per series.
    /// Empty series (no disks/interfaces) emits nothing.
    private static func labeled(_ out: inout String, _ name: String, _ help: String,
                                _ series: [(labels: String, value: Double)]) {
        guard !series.isEmpty else { return }
        out += "# HELP \(name) \(help)\n# TYPE \(name) gauge\n"
        for s in series { out += "\(name){\(s.labels)} \(num(s.value))\n" }
    }

    /// Escape a Prometheus label value (backslash and double-quote).
    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Whole numbers print without a decimal point (`42`, not `42.0`); the
    /// rest keep their value. Prometheus accepts both.
    private static func num(_ v: Double) -> String {
        v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(v)
    }
}
