//
//  WeeklyReport.swift
//  Burrow
//
//  The weekly system digest (roadmap A.4): a pure composer over facts already
//  on disk (history deltas, space reclaimed, top energy, new login items,
//  battery delta, the disk forecast). Markdown out — the same artifact the
//  Home "Report" card renders and the future burrow_report MCP tool returns,
//  so the two can't drift. Gathering the Input from the DB is integration.
//

import Foundation

enum WeeklyReport {
    struct Input {
        var periodDays: Int
        /// nil = cleanup history unavailable (distinct from a genuine zero).
        var spaceReclaimedBytes: Int64?
        var topEnergy: [(name: String, cpuSeconds: Double)]
        var newLoginItems: [String]
        /// Negative = health declined since the period start; nil = unknown.
        var batteryHealthDeltaPct: Double?
        var forecast: DiskForecast.Projection?
        /// Regressed processes from AnomalyScan (A.2); empty = nothing flagged.
        var anomalies: [AnomalyScan.Finding] = []
    }

    static func markdown(_ i: Input) -> String {
        var out = "# Burrow weekly report\n\n_Last \(i.periodDays) days._\n\n"

        out += "## Cleanup\n"
        if let reclaimed = i.spaceReclaimedBytes {
            out += reclaimed > 0
                ? "- Freed **\(Fmt.bytes(reclaimed))** this period.\n\n"
                : "- No space reclaimed this period.\n\n"
        } else {
            out += "- Cleanup history unavailable.\n\n"
        }

        // Only name a fill date when the forecaster was willing to — never a
        // bare date (see DiskForecast).
        if let f = i.forecast, let days = f.daysUntilFull {
            out += "## Disk\n- At the current rate, the disk fills in **~\(phrase(days))** "
                + "(based on \(Int(f.basisDays.rounded())) days).\n\n"
        }

        if !i.topEnergy.isEmpty {
            out += "## Top energy users\n"
            for e in i.topEnergy.prefix(5) {
                out += "- \(e.name) — \(Int(e.cpuSeconds.rounded())) CPU-seconds\n"
            }
            out += "\n"
        }

        if let d = i.batteryHealthDeltaPct, d < 0 {
            out += "## Battery\n- Health down **\(String(format: "%.1f", -d))%** since the period start.\n\n"
        }

        if !i.anomalies.isEmpty {
            out += "## Changes\nProcesses using notably more CPU than their recent baseline:\n"
            for a in i.anomalies.prefix(5) {
                out += "- \(a.process) — now ~\(Int(a.recentMedian.rounded()))% CPU (was ~\(Int(a.baselineMedian.rounded()))%)\n"
            }
            out += "\n"
        }

        // Persistence items that appeared this period — a light security note.
        if !i.newLoginItems.isEmpty {
            out += "## New startup items\nThese now launch automatically and appeared this period:\n"
            for item in i.newLoginItems { out += "- `\(item)`\n" }
            out += "\n"
        }
        return out
    }

    /// Days → the roundest honest phrase ("3 weeks", not "21 days").
    private static func phrase(_ days: Double) -> String {
        if days < 14 { return "\(Int(days.rounded())) days" }
        if days < 60 { return "\(Int((days / 7).rounded())) weeks" }
        return "\(Int((days / 30).rounded())) months"
    }
}
