//
//  CleanView.swift
//  Burrow
//
//  The Clean tab — mole.fit's "Earth" flow, our brand. Hero with a
//  "Scan your Mac" button → runs `mo clean --dry-run` → a themed report
//  of what would be freed, headlined by the reclaimable total. The
//  "Clean for real" button is gated on a finished dry run and a confirm
//  dialog, because real cleaning deletes caches permanently.
//

import SwiftUI
import AppKit

struct CleanView: View {
    @StateObject private var runner = CommandRunner()
    @State private var mode: Mode = .dry

    enum Mode { case dry, real }

    var body: some View {
        if runner.phase == .idle {
            ToolHero(tool: .clean, title: "Clean", subtitle: Tool.clean.tagline) {
                PillButton(title: "Scan your Mac") { startDry() }
            }
        } else {
            VStack(spacing: 0) {
                statusBar.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 12)
                Rectangle().fill(Brand.hairline).frame(height: 1)
                let report = parseTaskReport(runner.lines)
                if mode == .dry, let s = report.summary { summaryBanner(s) }
                TaskReportView(groups: report.groups, accent: Tool.clean.accent)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 10) {
            if isRunning { ProgressView().controlSize(.small).tint(Tool.clean.accent) }
            Text(statusText).font(Brand.mono(12)).foregroundStyle(Brand.textSecondary)
            Spacer()
            if isDone {
                Button { startDry() } label: {
                    Label("Re-scan", systemImage: "arrow.clockwise")
                        .font(Brand.mono(11)).foregroundStyle(Brand.textSecondary)
                }.buttonStyle(.plain)
            }
            if mode == .dry, isDone {
                PillButton(title: "Clean for real") { confirmReal() }
            }
        }
    }

    private func summaryBanner(_ s: TaskSummary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(s.space.isEmpty ? "—" : s.space)
                .font(Brand.mono(24, .semibold)).foregroundStyle(Tool.clean.accent)
            Text("to free").font(Brand.sans(13)).foregroundStyle(Brand.textSecondary)
            if !s.items.isEmpty {
                Text("· \(s.items) items · \(s.categories) categories")
                    .font(Brand.mono(11)).foregroundStyle(Brand.textTertiary)
            }
            Spacer()
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var isRunning: Bool { runner.phase == .running }
    private var isDone: Bool { if case .done = runner.phase { return true }; return false }

    private var statusText: String {
        switch runner.phase {
        case .running: return mode == .dry ? "Scanning your Mac…" : "Cleaning… don't quit."
        case .done:    return mode == .dry ? "Preview — review, then clean for real." : "Done — caches cleared."
        case .failed(let m): return "Failed: \(m)"
        case .idle:    return ""
        }
    }

    private func startDry() { mode = .dry; runner.run(["clean", "--dry-run"]) }

    private func confirmReal() {
        let alert = NSAlert()
        alert.messageText = "Clean caches for real?"
        alert.informativeText = "Burrow will run `mo clean`. Cache files are removed permanently (not sent to Trash). Mole's whitelist and safety rules still apply."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clean")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        mode = .real
        runner.run(["clean"])
    }
}
