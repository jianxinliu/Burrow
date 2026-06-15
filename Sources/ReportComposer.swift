//
//  ReportComposer.swift
//  Burrow
//
//  Gathers a WeeklyReport.Input from the metrics store (roadmap A.4). The one
//  place that turns history into report inputs, so the Home Report card and
//  the burrow_report MCP tool render the same digest and can't drift. v1
//  fills disk-forecast + top-energy from snapshots; cleanup/battery/login
//  stay nil ("unavailable") until those sources land — never faked.
//

import Foundation

enum ReportComposer {
    static func gather(metrics: MetricsStore, days: Int, now: Int) -> WeeklyReport.Input {
        let w = MetricsStore.Window(since: now - days * 86_400, until: now)
        let series = metrics.diskFreeSeries(mount: nil, w)
        let forecast = series.count >= 2 ? DiskForecast.forecast(series, now: now) : nil
        let top = metrics.processWindow(w).ranked(by: .cpuTime, limit: 5)
            .map { (name: $0.name, cpuSeconds: $0.estCPUSeconds) }
        return WeeklyReport.Input(periodDays: days, spaceReclaimedBytes: nil,
                                  topEnergy: top, newLoginItems: [],
                                  batteryHealthDeltaPct: nil, forecast: forecast)
    }
}
