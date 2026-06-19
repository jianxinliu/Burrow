//
//  GitRepoStatus.swift
//  Burrow
//
//  Purge-safety check for project folders (roadmap C.11): before Burrow
//  offers to delete a directory, it walks up to the containing repo and asks
//  "would this lose work?" This is the pure half — parsing
//  `git status --porcelain=v1 -b` into a verdict. Running `git` (with a short
//  timeout + concurrency cap) and badging the purge checklist is the
//  integration half. Conservative on purpose: untracked files count as work,
//  and a branch that was never pushed is treated as unpushed — the whole
//  point is to be safer than deleting by hand.
//

import Foundation

enum GitRepoStatus {
    struct Status: Equatable {
        /// Any working-tree change, including untracked files.
        let dirty: Bool
        /// Commits ahead of the upstream (0 when synced or no upstream).
        let ahead: Int
        let hasUpstream: Bool
        let detached: Bool

        /// Work that exists only locally: commits ahead of upstream, or a
        /// real branch with no upstream at all (never pushed anywhere).
        var unpushed: Bool { ahead > 0 || (!hasUpstream && !detached) }
        /// The badge condition — purging this would risk losing something.
        var needsAttention: Bool { dirty || unpushed }
    }

    static func parse(_ porcelain: String) -> Status {
        var dirty = false, ahead = 0, hasUpstream = false, detached = false
        for raw in porcelain.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.hasPrefix("## ") {
                let branch = String(line.dropFirst(3))
                detached = branch.hasPrefix("HEAD (no branch)")
                hasUpstream = branch.contains("...")
                if let r = branch.range(of: "[ahead "),
                   let end = branch[r.upperBound...].firstIndex(where: { $0 == "," || $0 == "]" }) {
                    ahead = Int(branch[r.upperBound..<end]) ?? 0
                }
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                dirty = true  // any porcelain entry (modified, staged, untracked)
            }
        }
        return Status(dirty: dirty, ahead: ahead, hasUpstream: hasUpstream, detached: detached)
    }
}
