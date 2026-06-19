//
//  Anomaly.swift
//  Burrow
//
//  Baseline-vs-recent regression detection (roadmap A.2). Pure statistics:
//  arrays in, a verdict out — so the "WindowServer baseline doubled" and
//  "battery drains faster than two weeks ago" findings are computed the same
//  way wherever they're surfaced (Home card, notifications, the Explain lens,
//  a future MCP tool), and the credibility tuning lives in one place.
//
//  The rules are deliberately conservative: a finding needs a clear effect
//  size on top of statistical exceedance, because a false "your Mac is
//  degrading" alert costs more trust than a missed one.
//

import Foundation

enum Anomaly {
    // MARK: Statistical primitives

    /// Linear-interpolated percentile (the numpy/"type 7" convention), so
    /// p95 of a short baseline is stable and well-defined. `p` is 0...100.
    static func percentile(_ xs: [Double], _ p: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        if s.count == 1 { return s[0] }
        let rank = (p / 100.0) * Double(s.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = Int(rank.rounded(.up))
        let frac = rank - Double(lo)
        return s[lo] + (s[hi] - s[lo]) * frac
    }

    static func median(_ xs: [Double]) -> Double { percentile(xs, 50) }

    // MARK: Process CPU regression

    /// True when a process's recent CPU is *sustainedly* above its own
    /// baseline: the typical recent value clears the baseline's 95th
    /// percentile AND beats the baseline median by at least `minDelta` points.
    /// The effect-size floor stops near-idle processes (0.5% → 2%) from
    /// tripping a "doubled!" alert that's technically true but meaningless.
    static func processCPUExceedsBaseline(baseline: [Double], recent: [Double],
                                          minSamples: Int = 5, minDelta: Double = 10) -> Bool {
        guard baseline.count >= minSamples, recent.count >= minSamples else { return false }
        let recentMid = median(recent)
        return recentMid > percentile(baseline, 95)
            && (recentMid - median(baseline)) >= minDelta
    }

    // MARK: Battery drain regression

    /// Discharge rate of one session in percent-per-hour (positive = losing
    /// charge), via least-squares slope over elapsed hours. Robust to a
    /// noisy reading or two. nil when the session is too short to have a rate.
    static func batteryDrainRate(_ session: [(ts: Int, percent: Double)]) -> Double? {
        guard session.count >= 2 else { return nil }
        let pts = session.map { (h: Double($0.ts) / 3600.0, p: $0.percent) }
        let n = Double(pts.count)
        let meanH = pts.reduce(0) { $0 + $1.h } / n
        let meanP = pts.reduce(0) { $0 + $1.p } / n
        var num = 0.0, den = 0.0
        for pt in pts { num += (pt.h - meanH) * (pt.p - meanP); den += (pt.h - meanH) * (pt.h - meanH) }
        guard den > 0 else { return nil }
        return -(num / den)  // negate: a falling % is a positive drain rate
    }

    /// True when the recent discharge drains meaningfully faster than the
    /// baseline sessions: at least `factor`× the median baseline rate and at
    /// least `minDelta` %/hr faster in absolute terms.
    static func batteryDrainRegressed(baselineRates: [Double], recentRate: Double,
                                      factor: Double = 1.25, minDelta: Double = 1) -> Bool {
        guard !baselineRates.isEmpty else { return false }
        let base = median(baselineRates)
        return base > 0 && recentRate >= base * factor && (recentRate - base) >= minDelta
    }
}
