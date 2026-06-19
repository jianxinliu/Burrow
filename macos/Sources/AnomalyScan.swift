//
//  AnomalyScan.swift
//  Burrow
//
//  Connects the Anomaly rules (A.2) to real history: per-process CPU samples
//  for a recent window vs a baseline window → the processes whose usage has
//  regressed. Pure over the two sample maps (which MetricsStore.processCPUSamples
//  produces), so it's testable without a DB. Persisting findings under
//  `burrow.findings` (Maintenance pass) and the Home "Changes" card are
//  integration.
//

import Foundation

enum AnomalyScan {
    struct Finding: Equatable {
        let process: String
        let recentMedian: Double
        let baselineMedian: Double
    }

    /// Convenience: pull recent (last 24h) vs baseline (prior 14d) per-process
    /// CPU from the store and flag regressions. The window split the roadmap
    /// specifies for A.2.
    static func scan(metrics: MetricsStore, now: Int) -> [Finding] {
        let day = 86_400
        let recent = metrics.processCPUSamples(.init(since: now - day, until: now))
        let baseline = metrics.processCPUSamples(.init(since: now - 15 * day, until: now - day))
        return cpuFindings(baseline: baseline, recent: recent)
    }

    /// Flag every process whose recent CPU clears its own baseline per the
    /// Anomaly rule, worst (highest recent median) first.
    static func cpuFindings(baseline: [String: [Double]],
                            recent: [String: [Double]]) -> [Finding] {
        var out: [Finding] = []
        for (name, recentSamples) in recent {
            guard let baseSamples = baseline[name] else { continue }
            guard Anomaly.processCPUExceedsBaseline(baseline: baseSamples, recent: recentSamples) else { continue }
            out.append(Finding(process: name,
                               recentMedian: Anomaly.median(recentSamples),
                               baselineMedian: Anomaly.median(baseSamples)))
        }
        return out.sorted { $0.recentMedian > $1.recentMedian }
    }
}
