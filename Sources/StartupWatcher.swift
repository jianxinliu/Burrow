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
}
