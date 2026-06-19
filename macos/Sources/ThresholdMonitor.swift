//
//  ThresholdMonitor.swift
//  Burrow
//
//  Drives ThresholdAlerts off the live snapshot stream (roadmap D.12): holds
//  per-rule AlertState across ticks and posts a notification on each fire.
//  Called from LiveFeed.applySnapshot on the main thread; inert under XCTest
//  and gated by an off-by-default toggle (threshold alerts are a taste thing,
//  unlike the default-on disk-low and new-login-item notices).
//

import Foundation

final class ThresholdMonitor {
    static let shared = ThresholdMonitor()

    private let inert = Foundation.ProcessInfo.processInfo
        .environment["XCTestConfigurationFilePath"] != nil
    private var states: [String: AlertState] = [:]

    private init() {}

    func evaluate(_ s: MoleStatus, at: Date) {
        guard !inert, Store.thresholdAlertsEnabled else { return }
        let r = ThresholdAlerts.evaluate(s, ts: Int(at.timeIntervalSince1970), states: states,
                                         cpuHigh: Double(Store.cpuAlertThreshold),
                                         memHigh: Double(Store.memAlertThreshold))
        states = r.states
        for fire in r.fires {
            // thresholdAlert is main-actor-isolated; hop to it (we're already
            // on main, but evaluate is statically nonisolated).
            Task { @MainActor in
                BurrowNotifier.shared.thresholdAlert(ruleID: fire.ruleID, value: fire.value)
            }
        }
    }
}
