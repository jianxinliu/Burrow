//
//  FolderGrowth.swift
//  Burrow
//
//  Growth attribution (roadmap A.3): diff two per-folder size scans to answer
//  "Downloads grew 11 GB this month." Pure — two {path: bytes} maps in, the
//  movers out, biggest growth first. The weekly `mo analyze` scan that
//  produces the maps, persisting them, and surfacing in the report are
//  integration.
//

import Foundation

enum FolderGrowth {
    struct Change: Equatable {
        let path: String
        let deltaBytes: Int64
    }

    /// Per-folder size delta (new − old). Folders only in `new` count their
    /// full size as growth; unchanged folders are dropped. Sorted by delta
    /// descending so the biggest growers lead (shrinkers sort last).
    static func diff(old: [String: Int64], new: [String: Int64]) -> [Change] {
        var out: [Change] = []
        for (path, size) in new {
            let delta = size - (old[path] ?? 0)
            if delta != 0 { out.append(Change(path: path, deltaBytes: delta)) }
        }
        return out.sorted { $0.deltaBytes > $1.deltaBytes }
    }
}
