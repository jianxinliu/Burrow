//
//  ThresholdAlerts.swift
//  Burrow
//
//  The concrete threshold rules (roadmap D.12) folded over a snapshot through
//  the tested AlertEngine: CPU pegged / memory pressure high, with hysteresis
//  + cooldown so each fires once per episode. Pure — snapshot + prior states
//  in, next states + fires out. Disk-low already lives in ReminderRules; this
//  is the "high metric = bad" family. Evaluating per sample (Sampler), the
//  per-rule state persistence, and posting the notification are integration.
//

import Foundation

enum ThresholdAlerts {
    /// Rules built from the user's configured thresholds (Settings ▸
    /// Notifications). `low` is a hysteresis floor below `high` so a metric
    /// hovering at the line can't flap. The defaults (90/90, low = high−20/−15)
    /// reproduce the original hard-coded rules, so existing callers and tests
    /// are unchanged.
    static func rules(cpuHigh: Double = 90, memHigh: Double = 90,
                      cooldownSeconds: Int = 1800) -> [ThresholdRule] {
        [
            ThresholdRule(id: "cpu", high: cpuHigh, low: max(0, cpuHigh - 20), cooldownSeconds: cooldownSeconds),
            ThresholdRule(id: "memory", high: memHigh, low: max(0, memHigh - 15), cooldownSeconds: cooldownSeconds),
        ]
    }

    /// The metric a rule watches, read out of a snapshot.
    static func reading(_ ruleID: String, in s: MoleStatus) -> Double? {
        switch ruleID {
        case "cpu":    return s.cpu.usage
        case "memory": return s.memory.usedPercent
        default:       return nil
        }
    }

    struct Fire: Equatable {
        let ruleID: String
        let value: Double
    }

    /// Fold a snapshot through every rule given the prior per-rule states.
    static func evaluate(_ s: MoleStatus, ts: Int,
                         states: [String: AlertState],
                         cpuHigh: Double = 90, memHigh: Double = 90) -> (states: [String: AlertState], fires: [Fire]) {
        var next = states
        var fires: [Fire] = []
        for rule in rules(cpuHigh: cpuHigh, memHigh: memHigh) {
            guard let v = reading(rule.id, in: s) else { continue }
            let r = AlertEngine.step(rule: rule, value: v, ts: ts, state: states[rule.id] ?? AlertState())
            next[rule.id] = r.state
            if r.fired { fires.append(Fire(ruleID: rule.id, value: v)) }
        }
        return (next, fires)
    }
}
