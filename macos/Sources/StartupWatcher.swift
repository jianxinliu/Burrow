//
//  StartupWatcher.swift
//  Burrow
//
//  New-persistence-item detection (roadmap D.12, the differentiating alert).
//  Pure: a previous inventory (identifiers) + the current StartupInventory
//  scan → the items that just appeared. Reuses InventoryDiff so "what changed"
//  is computed one way everywhere. Persisting the baseline (Maintenance tick),
//  firing the notification, and the reveal-in-Finder action are integration.
//
//  First run has no baseline; callers must NOT alert on the first scan (an
//  empty `previousIDs` makes everything "new"), only on subsequent deltas.
//

import Foundation

enum StartupWatcher {
    /// Items whose identifier wasn't in the previous inventory — the
    /// "a new LaunchAgent/login item appeared" signal.
    static func newlyAppeared(previousIDs: [String], current: [StartupItem]) -> [StartupItem] {
        let added = Set(InventoryDiff.diff(old: previousIDs, new: current.map(\.id)).added)
        return current.filter { added.contains($0.id) }
    }

    /// Fold a fresh scan against the persisted baseline JSON (a `[String]` of
    /// ids). First run — no baseline, or an empty one — alerts on nothing and
    /// just establishes the baseline; only later scans report appearances.
    /// Returns what to alert on plus the baseline JSON to persist.
    static func check(previousBaselineJSON: String?,
                      current: [StartupItem]) -> (newItems: [StartupItem], baselineJSON: String) {
        let baseline = encode(current.map(\.id))
        guard let prev = previousBaselineJSON,
              let prevIDs = try? JSONDecoder().decode([String].self, from: Data(prev.utf8)),
              !prevIDs.isEmpty else {
            return ([], baseline)
        }
        return (newlyAppeared(previousIDs: prevIDs, current: current), baseline)
    }

    private static func encode(_ ids: [String]) -> String {
        (try? JSONEncoder().encode(ids)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}
