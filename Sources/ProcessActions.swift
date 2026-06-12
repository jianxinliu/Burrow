//
//  ProcessActions.swift
//  Burrow
//
//  Per-process actions + best-effort energy for the Status process
//  table (design 3.2) and the popover's rows (3.5):
//
//    * PWR — cumulative billed energy via proc_pid_rusage
//      (ri_energy_billed), shown in mWh; "—" where the kernel reports
//      nothing. Never estimated.
//    * Row menu — Pin, Reveal in Finder, Copy name / PID, Quit
//      (SIGTERM) and Force Kill (SIGKILL) for own-user processes only;
//      root-owned rows get reveal/copy alone.
//
//  Plus the pure aggregates the popover reads: CleanWatch lifetime
//  totals from `mo history`, and the top-drain pick from snapshot
//  process lists.
//

import Foundation
import AppKit
import Darwin

enum ProcessActions {
    /// Cumulative billed energy for a pid, in nanojoules. nil when the
    /// kernel won't say (permission, exited, or platform). Flavor 4 is
    /// the first rusage_info with ri_energy_billed — pinned numerically
    /// so the C macro doesn't need to import.
    static func energyNanojoules(pid: Int) -> UInt64? {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: (rusage_info_t?).self, capacity: 1) {
                proc_pid_rusage(Int32(pid), 4, $0)
            }
        }
        guard result == 0, usage.ri_billed_energy > 0 else { return nil }
        return usage.ri_billed_energy
    }

    /// "—" / "<1" / "25" — cumulative mWh, no invented precision.
    static func energyText(nanojoules: UInt64?) -> String {
        guard let nj = nanojoules, nj > 0 else { return "—" }
        let mWh = Double(nj) / 3_600_000_000
        if mWh < 1 { return "<1" }
        return String(format: "%.0f", mWh)
    }

    /// Whether this process belongs to the current user — the
    /// requirement for Quit / Force Kill. Root-owned rows are read-only.
    static func isOwnProcess(pid: Int) -> Bool {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let got = proc_pidinfo(Int32(pid), PROC_PIDTBSDINFO, 0, &info, size)
        guard got == size else { return false }
        return info.pbi_uid == getuid()
    }

    /// Executable path for reveal-in-Finder. nil for system stubs.
    static func executablePath(pid: Int) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let n = proc_pidpath(Int32(pid), &buffer, UInt32(buffer.count))
        guard n > 0 else { return nil }
        return String(cString: buffer)
    }

    /// SIGTERM — the polite ask. Caller confirms first.
    @discardableResult
    static func quit(pid: Int) -> Bool { kill(Int32(pid), SIGTERM) == 0 }

    /// SIGKILL — the hammer. Caller double-confirms first.
    @discardableResult
    static func forceKill(pid: Int) -> Bool { kill(Int32(pid), SIGKILL) == 0 }
}

/// Lifetime cleanup totals for the popover's "Clean Watch" footer.
enum CleanWatch {
    struct Totals: Equatable {
        let cleanedBytes: Int64
        let uninstalledApps: Int
        let optimizeRuns: Int

        var isEmpty: Bool { cleanedBytes == 0 && uninstalledApps == 0 && optimizeRuns == 0 }
    }

    static func totals(from sessions: [HistorySession]) -> Totals {
        var bytes: Int64 = 0
        var uninstalled = 0
        var optimizes = 0
        for s in sessions {
            switch s.command {
            case "clean", "purge", "installer":
                bytes += CleanList.parseSize(s.size)
            case "uninstall":
                uninstalled += max(s.items, 0)
            case "optimize":
                optimizes += 1
            default:
                break
            }
        }
        return Totals(cleanedBytes: bytes, uninstalledApps: uninstalled, optimizeRuns: optimizes)
    }
}

/// "⚡ Top drain" for the battery card: the process with the highest
/// average CPU across the sampled snapshots. Upgrades to true energy
/// ranking when per-process PWR history lands.
enum TopDrain {
    static func heaviest(_ processLists: [[ProcessInfo]]) -> (name: String, avgCPU: Double)? {
        var sums: [String: (total: Double, count: Int)] = [:]
        for list in processLists {
            for p in list {
                let acc = sums[p.name] ?? (0, 0)
                sums[p.name] = (acc.total + p.cpu, acc.count + 1)
            }
        }
        guard let best = sums.max(by: { ($0.value.total / Double($0.value.count)) < ($1.value.total / Double($1.value.count)) }),
              best.value.count > 0 else { return nil }
        return (best.key, best.value.total / Double(best.value.count))
    }
}
