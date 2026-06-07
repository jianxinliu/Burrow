//
//  StreamingToolView.swift
//  Burrow
//
//  Generic "preview, then run for real" tool surface for Mole subcommands
//  that stream a TaskReport — the same shape as Clean/Optimize, factored
//  so new cleanup tools are config, not copy-paste. Drives `mo <cmd>
//  --dry-run` for the no-risk preview and a confirm-gated `mo <cmd>` for
//  the real run, rendering both through the shared TaskReportView.
//
//  Used for Purge (`mo purge` — project build/dependency artifacts) and
//  Installers (`mo installer` — leftover .dmg/.pkg). Both operate on the
//  user's own files, so neither needs elevation (unlike Clean).
//

import SwiftUI
import AppKit

/// Static description of one streamed cleanup tool.
struct CleanupAction {
    let tool: Tool
    let subcommand: String       // mo subcommand, e.g. "purge"
    let runButton: String        // hero CTA, e.g. "Purge Now"
    let previewLabel: String     // OperationCenter label for the dry run
    let runLabel: String         // OperationCenter label for the real run
    let confirmTitle: String
    let confirmBody: String
    let confirmCTA: String
    let doneTitle: String        // done-banner title, e.g. "Purged"
    var elevated: Bool = false

    static let purge = CleanupAction(
        tool: .purge,
        subcommand: "purge",
        runButton: "Purge Now",
        previewLabel: "Scanning project artifacts",
        runLabel: "Purging artifacts",
        confirmTitle: "Remove old project artifacts?",
        confirmBody: "Burrow will run `mo purge` to delete reclaimable build and dependency artifacts (node_modules, build, dist, target…). Mole's whitelist and safety rules still apply.",
        confirmCTA: "Purge",
        doneTitle: "Purged")

    static let installer = CleanupAction(
        tool: .installer,
        subcommand: "installer",
        runButton: "Remove",
        previewLabel: "Scanning for installers",
        runLabel: "Removing installers",
        confirmTitle: "Remove leftover installer files?",
        confirmBody: "Burrow will run `mo installer` to remove leftover installer files (.dmg, .pkg) it found. Mole's whitelist and safety rules still apply.",
        confirmCTA: "Remove",
        doneTitle: "Removed")
}

struct StreamingToolView: View {
    let action: CleanupAction

    @StateObject private var runner = CommandRunner()
    @State private var mode: Mode = .dry
    @State private var pendingRun: ((Bool) -> Void)? = nil

    enum Mode { case dry, real }

    var body: some View {
        if runner.phase == .idle {
            if pendingRun != nil {
                FullDiskAccessRequired(
                    accent: action.tool.accent,
                    onRecheck: { if Privacy.hasFullDiskAccess() { runPending(elevate: false) } },
                    onRunAnyway: { runPending(elevate: true) },
                    onCancel: { pendingRun = nil })
            } else {
                ToolHero(tool: action.tool, title: action.tool.title, subtitle: action.tool.tagline) {
                    PillButton(title: action.runButton) { confirmReal() }
                    PillButton(title: "Preview", filled: false) { startDry() }
                }
            }
        } else {
            VStack(spacing: 0) {
                statusBar.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 12)
                Rectangle().fill(Brand.hairline).frame(height: 1)
                if isDone, mode == .real {
                    DoneBanner(accent: action.tool.accent, title: action.doneTitle,
                               detail: runner.summary.map(doneDetail))
                } else if mode == .dry, let s = runner.summary {
                    summaryBanner(s)
                }
                TaskReportView(groups: runner.groups, accent: action.tool.accent)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if isRunning { ProgressView().controlSize(.small).tint(action.tool.accent) }
            Text(statusText).font(Brand.mono(12)).foregroundStyle(Brand.textSecondary)
            Spacer()
            if isRunning {
                Button { runner.cancel() } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(Brand.mono(11)).foregroundStyle(Brand.red)
                }.buttonStyle(.plain)
            }
            if isDone {
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
                .font(Brand.mono(24, .semibold)).foregroundStyle(action.tool.accent)
            Text("to reclaim").font(Brand.sans(13)).foregroundStyle(Brand.textSecondary)
            if !s.items.isEmpty {
                Text("· \(s.items) items · \(s.categories) categories")
                    .font(Brand.mono(11)).foregroundStyle(Brand.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func doneDetail(_ s: TaskSummary) -> String {
        var parts: [String] = []
        if !s.space.isEmpty { parts.append("\(s.space) reclaimed") }
        if !s.items.isEmpty { parts.append("\(s.items) items") }
        return parts.isEmpty ? "Done" : parts.joined(separator: " · ")
    }

    private var isRunning: Bool { runner.phase == .running }
    private var isDone: Bool { if case .done = runner.phase { return true }; return false }

    private var statusText: String {
        switch runner.phase {
        case .running: return mode == .dry ? "Scanning…" : "Working… don't quit."
        case .done:    return runner.wasCancelled ? "Stopped."
            : (mode == .dry ? "Preview — review, then run for real." : "Done.")
        case .failed(let m): return "Failed: \(m)"
        case .idle:    return ""
        }
    }

    // MARK: - Full Disk Access gate

    /// With Full Disk Access, run directly. Without, divert to the gate; the
    /// user grants FDA (then we run normally) or picks "Scan with admin",
    /// which runs the same command elevated — root bypasses TCC, so one
    /// password replaces the per-folder flood. `work(elevate)` decides.
    private func guarded(_ work: @escaping (Bool) -> Void) {
        if Privacy.hasFullDiskAccess() { work(false) } else { pendingRun = work }
    }
    private func runPending(elevate: Bool) { let r = pendingRun; pendingRun = nil; r?(elevate) }

    private func startDry() {
        guarded { elevate in
            mode = .dry
            runner.run([action.subcommand, "--dry-run"], elevated: elevate, label: action.previewLabel)
        }
    }

    private func confirmReal() {
        guarded { elevate in
            let alert = NSAlert()
            alert.messageText = action.confirmTitle
            alert.informativeText = action.confirmBody
            alert.alertStyle = .warning
            alert.addButton(withTitle: action.confirmCTA)
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            mode = .real
            runner.run([action.subcommand], elevated: elevate || action.elevated, label: action.runLabel)
        }
    }
}
