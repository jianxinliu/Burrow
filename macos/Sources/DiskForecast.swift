//
//  DiskForecast.swift
//  Burrow
//
//  Disk-full forecasting from free-space history (roadmap A.3). Pure: a
//  series of (timestamp, free-bytes) in, a projection out — so the Home disk
//  tile and the History disk chart can both say "full in ~3 weeks" from the
//  same honest estimate.
//
//  Honest by construction. It refuses to name a date when the trend is flat,
//  when free space is *growing*, or when there's less than a week of history,
//  and it resists single-sample cliffs (a temp file briefly eating space) by
//  fitting a robust median (Theil–Sen) slope rather than least-squares, which
//  one outlier can drag arbitrarily far.
//

import Foundation

enum DiskForecast {
    struct Projection: Equatable {
        /// Estimated days until free space reaches zero, or nil when not
        /// forecastable — the UI shows the basis instead of a bare date.
        let daysUntilFull: Double?
        /// Trend in bytes/day (negative = filling up). Always present.
        let slopeBytesPerDay: Double
        /// Span of history the fit used, in days — surfaced so the UI can say
        /// "based on N days" and never present precision it doesn't have.
        let basisDays: Double
    }

    /// Below this much history, a date is noise dressed as precision.
    static let minBasisDays = 7.0
    /// Forecasts past this horizon mean the slope is effectively flat; we
    /// suppress the date rather than tell someone their disk fills in 80 years.
    static let maxHorizonDays = 365.0 * 5
    /// Pairwise Theil–Sen is O(n²); bound the input so a pathological caller
    /// can't stall. Snapshots already arrive ≤720, so this rarely bites.
    static let maxSamples = 1500

    static func forecast(_ samples: [(ts: Int, freeBytes: Double)], now: Int) -> Projection {
        let sorted = samples.sorted { $0.ts < $1.ts }
        let pts = sorted.count > maxSamples ? stride(from: 0, to: sorted.count,
                        by: sorted.count / maxSamples + 1).map { sorted[$0] } : sorted
        guard pts.count >= 2, let first = pts.first, let last = pts.last,
              last.ts > first.ts else {
            return Projection(daysUntilFull: nil, slopeBytesPerDay: 0, basisDays: 0)
        }
        let basisDays = Double(last.ts - first.ts) / 86_400.0

        // Theil–Sen slope: median of all pairwise slopes (bytes/day).
        var slopes: [Double] = []
        slopes.reserveCapacity(pts.count * (pts.count - 1) / 2)
        for i in 0..<pts.count {
            for j in (i + 1)..<pts.count {
                let dtDays = Double(pts[j].ts - pts[i].ts) / 86_400.0
                if dtDays > 0 {
                    slopes.append((pts[j].freeBytes - pts[i].freeBytes) / dtDays)
                }
            }
        }
        let slope = median(slopes)
        // Robust "free right now": the Theil–Sen line (median intercept +
        // slope) evaluated at `now`, so one cliff sample can't move the start.
        let intercepts = pts.map { $0.freeBytes - slope * (Double($0.ts) / 86_400.0) }
        let currentFree = slope * (Double(now) / 86_400.0) + median(intercepts)

        guard basisDays >= minBasisDays else {
            return Projection(daysUntilFull: nil, slopeBytesPerDay: slope, basisDays: basisDays)
        }
        guard slope < 0 else {  // flat or growing → it never fills
            return Projection(daysUntilFull: nil, slopeBytesPerDay: slope, basisDays: basisDays)
        }
        let days = max(0, currentFree) / (-slope)
        return Projection(daysUntilFull: days <= maxHorizonDays ? days : nil,
                          slopeBytesPerDay: slope, basisDays: basisDays)
    }

    private static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}
