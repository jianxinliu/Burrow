//
//  CleanView.swift
//  Burrow
//
//  The Clean tab — mole.fit's "Earth" flow, our brand. The hero offers
//  both a no-risk "Scan your Mac" preview (`mo clean --dry-run`) and a
//  direct "Clean Now" run. The real clean runs elevated through ONE auth
//  prompt (CommandRunner.runElevated) so you don't get a stack of
//  password dialogs, and finishes on a proper done banner.
//

import SwiftUI
import AppKit

struct CleanView: View {
    @StateObject private var runner = CommandRunner()
    @State private var mode: Mode = .dry
    @State private var pendingRun: ((Bool) -> Void)? = nil

    enum Mode { case dry, real }

    var body: some View {
        if runner.phase == .idle {
            if pendingRun != nil {
                FullDiskAccessRequired(
                    accent: Tool.clean.accent,
                    onRecheck: { if Privacy.hasFullDiskAccess() { runPending(elevate: false); return true }; return false },
                    onRunAnyway: { runPending(elevate: true) },   // root bypasses TCC → no flood
                    onCancel: { pendingRun = nil })
            } else {
                ToolHero(tool: .clean, title: "Clean", subtitle: Tool.clean.tagline) {
                    PillButton(title: "Clean Now") { confirmReal() }
                    PillButton(title: "Preview", filled: false) { startDry() }
                }
            }
        } else {
            VStack(spacing: 0) {
                statusBar.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 12)
                Rectangle().fill(Brand.hairline).frame(height: 1)
                if isDone, mode == .real {
                    DoneBanner(accent: Tool.clean.accent, title: "Cleaned",
                               detail: runner.summary.map(cleanedDetail))
                } else if mode == .dry, let s = runner.summary {
                    summaryBanner(s)
                }
                TaskReportView(groups: runner.groups, accent: Tool.clean.accent)
            }
        }
    }

    /// Post-run detail line. Prefers the real freed-space numbers Mole
    /// prints after a live clean ("Free space change / now"), falling
    /// back to the tracked-cleanup size when those aren't present.
    private func cleanedDetail(_ s: TaskSummary) -> String {
        var parts: [String] = []
        if !s.freeChange.isEmpty { parts.append("Freed \(s.freeChange)") }
        else if !s.space.isEmpty { parts.append("Cleaned \(s.space)") }
        if !s.freeNow.isEmpty { parts.append("\(s.freeNow) free now") }
        if !s.items.isEmpty { parts.append("\(s.items) items") }
        return parts.isEmpty ? "Done" : parts.joined(separator: " · ")
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if isRunning { ProgressView().controlSize(.small).tint(Tool.clean.accent) }
            Text(statusText).font(Brand.mono(12)).foregroundStyle(Brand.textSecondary)
            Spacer()
            if isRunning {
                Button { runner.cancel() } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(Brand.mono(11)).foregroundStyle(Brand.red)
                }.buttonStyle(.plain)
            }
            if isDone || isFailed {
                Button { runner.reset() } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(Brand.mono(11)).foregroundStyle(Brand.textSecondary)
                }.buttonStyle(.plain)
            }
        }
    }

    private func summaryBanner(_ s: TaskSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(s.space.isEmpty ? "—" : s.space)
                .font(Brand.mono(24, .semibold)).foregroundStyle(Tool.clean.accent)
            Text("to free").font(Brand.sans(13)).foregroundStyle(Brand.textSecondary)
            if !s.items.isEmpty {
                Text(String(format: NSLocalizedString("· %@ items · %@ categories", comment: ""),
                            s.items, s.categories))
                    .font(Brand.mono(11)).foregroundStyle(Brand.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var isRunning: Bool { runner.phase == .running }
    private var isDone: Bool { if case .done = runner.phase { return true }; return false }
    private var isFailed: Bool { if case .failed = runner.phase { return true }; return false }

    private var statusText: String {
        switch runner.phase {
        case .running: return mode == .dry ? NSLocalizedString("Scanning your Mac…", comment: "") : NSLocalizedString("Cleaning… don't quit.", comment: "")
        case .done:    return runner.wasCancelled ? NSLocalizedString("Stopped.", comment: "")
            : (mode == .dry ? NSLocalizedString("Preview — review, then clean for real.", comment: "") : NSLocalizedString("Done — caches cleared.", comment: ""))
        case .failed(let m): return String(format: NSLocalizedString("Failed: %@", comment: ""), m)
        case .idle:    return ""
        }
    }

    // MARK: - Full Disk Access gate

    /// Run a flood-prone scan. With Full Disk Access we run it directly.
    /// Without, divert to the gate; the user either grants FDA (then we run
    /// normally) or picks "Scan with admin", which runs the same command
    /// elevated — root bypasses TCC, so one password replaces the flood.
    /// `work(elevate)` decides whether to run via sudo.
    private func guarded(_ work: @escaping (Bool) -> Void) {
        if Privacy.hasFullDiskAccess() { work(false) } else { pendingRun = work }
    }
    private func runPending(elevate: Bool) { let r = pendingRun; pendingRun = nil; r?(elevate) }

    private func startDry() {
        guarded { elevate in
            mode = .dry
            runner.run(["clean", "--dry-run"], elevated: elevate, label: "Scanning caches")
        }
    }

    /// The real clean already runs elevated (root), so it never triggers the
    /// flood — no gate needed here.
    private func confirmReal() {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Clean caches for real?", comment: "")
        alert.informativeText = NSLocalizedString("Burrow will run `mo clean` with administrator rights. Cache files are removed permanently; Mole's whitelist and safety rules still apply.", comment: "")
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Clean", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        mode = .real
        runner.run(["clean"], elevated: true, label: NSLocalizedString("Cleaning caches", comment: ""))
    }
}
