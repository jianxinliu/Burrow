//
//  AlertEngine.swift
//  Burrow
//
//  Threshold-alert evaluation (roadmap D.12). Pure and stateful-by-value: a
//  rule + the latest reading + the prior state → the next state and whether
//  to fire. Hysteresis (fire on crossing `high`, don't re-arm until the value
//  recovers below `low`) plus a cooldown mean an alert fires once per
//  *episode*, not once per sample — the difference between a useful nudge and
//  alert fatigue. The same evaluator backs notifications (D.12), the SSE
//  stream (B.6), and the report (A.4); the rules' thresholds, the Sampler
//  wiring, and UserNotifications delivery are integration.
//

import Foundation

struct ThresholdRule: Equatable {
    let id: String
    /// Fire when the reading reaches `high`…
    let high: Double
    /// …and don't re-arm until it falls back below `low` (hysteresis).
    let low: Double
    /// Minimum seconds between fires, across episodes.
    let cooldownSeconds: Int
}

struct AlertState: Equatable {
    /// In an active episode: above `high` and not yet recovered below `low`.
    var firing = false
    var lastFiredTS: Int?
}

enum AlertEngine {
    /// Fold one reading into the alert state. Returns the next state and
    /// whether this tick should emit an alert.
    static func step(rule: ThresholdRule, value: Double, ts: Int,
                     state: AlertState) -> (state: AlertState, fired: Bool) {
        var s = state
        if s.firing {
            // Episode continues until the value recovers below `low`; dips
            // that stay above `low` do not re-fire.
            if value < rule.low { s.firing = false }
            return (s, false)
        }
        guard value >= rule.high else { return (s, false) }
        s.firing = true
        if let last = s.lastFiredTS, ts - last < rule.cooldownSeconds {
            return (s, false)  // armed, but still cooling down from the last fire
        }
        s.lastFiredTS = ts
        return (s, true)
    }
}
