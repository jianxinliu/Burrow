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

    enum Mode { case dry, real }

    var body: some View {
        if runner.phase == .idle {
            ToolHero(tool: .clean, title: "Clean", subtitle: Tool.clean.tagline) {
                PillButton(title: "Clean Now") { confirmReal() }
                PillButton(title: "Preview", filled: false) { startDry() }
            }
        } else {
            let report = parseTaskReport(runner.lines)
            VStack(spacing: 0) {
                statusBar.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 12)
                Rectangle().fill(Brand.hairline).frame(height: 1)
                if isDone, mode == .real {
                    DoneBanner(accent: Tool.clean.accent, title: "Cleaned",
                               detail: report.summary.map {
                                   String(format: NSLocalizedString("Freed up to %@ · %@ items", comment: ""),
                                          $0.space, $0.items)
                               })
                } else if mode == .dry, let s = report.summary {
                    summaryBanner(s)
                }
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

    private var statusText: String {
        switch runner.phase {
        case .running: return mode == .dry ? NSLocalizedString("Scanning your Mac…", comment: "") : NSLocalizedString("Cleaning… don't quit.", comment: "")
        case .done:    return mode == .dry ? NSLocalizedString("Preview — review, then clean for real.", comment: "") : NSLocalizedString("Done — caches cleared.", comment: "")
        case .failed(let m): return String(format: NSLocalizedString("Failed: %@", comment: ""), m)
        case .idle:    return ""
        }
    }

    private func startDry() {
        mode = .dry
        runner.run(["clean", "--dry-run"], label: NSLocalizedString("Scanning caches", comment: ""))
    }

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
