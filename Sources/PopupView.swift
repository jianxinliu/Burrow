//
//  PopupView.swift
//  Burrow
//
//  Menu-bar popover. Replaced in v0.3 — used to be the *primary*
//  surface (the only place you'd ever see current values) but the
//  Overview tab inside the main window now does that job at full
//  fidelity. The popover's job is now narrower:
//
//    * Tell you instantly whether Burrow is collecting (freshness
//      label, four-metric compact readout).
//    * One click into the main window, pre-selecting the section you
//      probably wanted.
//
//  No sparklines here — they'd compete with the dashboard inside the
//  main window. Quick glance, dive in.
//

import SwiftUI

struct PopupView: View {
    @ObservedObject private var model: PopupModel
    private weak var delegate: AppDelegate?

    init(sampler: Sampler, delegate: AppDelegate) {
        self.model = PopupModel(sampler: sampler)
        self.delegate = delegate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            header
            Divider()
            if let snap = model.snapshot {
                summary(snap)
            } else {
                waitingState
            }
            Divider()
            actions
            footer
        }
        .padding(Theme.Spacing.md)
        .frame(width: 320)
        .onReceive(model.tick) { _ in model.refresh() }
    }

    // MARK: - Slices

    private var header: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(Theme.Colour.accent)
            Text("Burrow").font(Theme.Font.cardTitle)
            Spacer()
            Text(model.freshnessLabel)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colour.textSecondary)
                .monospacedDigit()
        }
    }

    private var waitingState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                ProgressView().controlSize(.small)
                Text("Waiting for first sample…").font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colour.textSecondary)
            }
            Text("Burrow spawns `mo status --json` at the configured cadence. The first row appears within one tick of launch.")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colour.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func summary(_ s: MoleStatus) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            row(symbol: "cpu",
                tint: Theme.Colour.cpu,
                label: "CPU",
                value: String(format: "%.1f %%", s.cpu.usage),
                detail: String(format: "load %.2f", s.cpu.load1))
            row(symbol: "memorychip",
                tint: Theme.Colour.memory,
                label: "Memory",
                value: String(format: "%.1f %%", s.memory.usedPercent),
                detail: s.memory.pressure)
            row(symbol: "internaldrive",
                tint: Theme.Colour.disk,
                label: "Disk",
                value: String(format: "%.1f MB/s", s.diskIO.readRate + s.diskIO.writeRate),
                detail: "r+w")
            row(symbol: "heart.text.square",
                tint: Theme.Colour.health,
                label: "Health",
                value: "\(s.healthScore)",
                detail: s.healthScoreMsg.isEmpty ? nil : s.healthScoreMsg)
        }
    }

    private func row(symbol: String, tint: Color, label: String,
                     value: String, detail: String?) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 16, alignment: .center)
            Text(label)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colour.textSecondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(Theme.Font.mono)
                .foregroundStyle(Theme.Colour.textPrimary)
            Spacer()
            if let d = detail {
                Text(d)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colour.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var actions: some View {
        // Primary action sits alone for emphasis; the four deep-link
        // buttons below let advanced users jump straight to a tab.
        VStack(spacing: Theme.Spacing.xs) {
            Button {
                if #available(macOS 14, *) {
                    self.delegate?.openMainWindow(initial: .status)
                }
            } label: {
                HStack {
                    Image(systemName: "rectangle.expand.vertical")
                    Text("Open Burrow")
                    Spacer()
                    Image(systemName: "arrow.up.right.square")
                        .imageScale(.small)
                        .foregroundStyle(Theme.Colour.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return)

            HStack(spacing: Theme.Spacing.xs) {
                deepLink(title: "Status",   symbol: "waveform.path.ecg", tool: .status)
                deepLink(title: "Analyze",  symbol: "square.grid.2x2",   tool: .analyze)
                deepLink(title: "Clean",    symbol: "sparkles",          tool: .clean)
                deepLink(title: "Software", symbol: "shippingbox",       tool: .apps)
            }
        }
    }

    @available(macOS 14.0, *)
    private func deepLink(title: String, symbol: String, tool: Tool) -> some View {
        Button {
            self.delegate?.openMainWindow(initial: tool)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol).imageScale(.small)
                Text(title).font(Theme.Font.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
    }

    private var footer: some View {
        HStack {
            Text("MCP @ 127.0.0.1:\(Store.queryServerPort)")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colour.textTertiary)
            Spacer()
            Button("Quit", action: { NSApp.terminate(nil) })
                .keyboardShortcut("q", modifiers: .command)
                .buttonStyle(.borderless)
                .controlSize(.small)
        }
    }
}

// MARK: - Tick driver

private final class PopupModel: ObservableObject {
    @Published var snapshot: MoleStatus?
    @Published var freshnessLabel: String = "—"

    let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let sampler: Sampler

    init(sampler: Sampler) {
        self.sampler = sampler
        self.refresh()
    }

    func refresh() {
        self.snapshot = self.sampler.lastSnapshot
        if let last = self.sampler.lastSampleAt {
            let elapsed = Int(Date().timeIntervalSince(last))
            self.freshnessLabel = "\(elapsed) s ago"
        } else {
            self.freshnessLabel = "—"
        }
    }
}
