//
//  SpikeView.swift
//  Burrow
//
//  Spike forensics (roadmap A.1): drag-select a window on any History chart and
//  see the top processes for that exact range. The selection is captured by a
//  chartOverlay drag in HistoryView; this sheet renders the result via the
//  already-tested MetricsStore.processWindow — GUI and MCP share one impl.
//
//  Ranks by the metric of the chart you dragged (Memory → RAM, everything else
//  → CPU — the two axes Mole's top_processes carries) and lets you flip between
//  them. Styled to the Brand glass system like the rest of the app.
//

import SwiftUI

/// A drag-selected window on a History chart, in unix seconds, plus the metric
/// the dragged chart maps to (so the sheet opens on the right ranking).
struct SpikeWindow: Identifiable {
    let id = UUID()
    let since: Int
    let until: Int
    var metric: ProcMetric = .cpu
}

struct SpikeSheet: View {
    let db: DB
    let window: SpikeWindow
    let onClose: () -> Void

    struct Row: Identifiable {
        let id = UUID()
        let name: String
        let peakCPU: Double
        let peakMem: Double
        let peakMemBytes: UInt64
    }

    @State private var rows: [Row] = []
    @State private var loaded = false
    @State private var metric: ProcMetric

    init(db: DB, window: SpikeWindow, onClose: @escaping () -> Void) {
        self.db = db
        self.window = window
        self.onClose = onClose
        _metric = State(initialValue: window.metric)
    }

    private var ranked: [Row] {
        switch metric {
        case .cpu: return rows.sorted { $0.peakCPU > $1.peakCPU }
        case .ram: return rows.sorted { ($0.peakMemBytes, $0.peakMem) > ($1.peakMemBytes, $1.peakMem) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(NSLocalizedString("Top processes in selection", comment: ""))
                        .font(Brand.serif(18, .medium)).foregroundStyle(Brand.textPrimary)
                    Text(rangeLabel).font(Brand.mono(11)).foregroundStyle(Brand.textSecondary)
                }
                Spacer()
                metricToggle
            }
            Rectangle().fill(Brand.hairline).frame(height: 1)

            if loaded && rows.isEmpty {
                Text(NSLocalizedString("No process samples in that window.", comment: ""))
                    .font(Brand.sans(13)).foregroundStyle(Brand.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                HStack {
                    Text("").frame(maxWidth: .infinity, alignment: .leading)
                    Text("CPU").font(Brand.mono(8, .bold)).tracking(0.5)
                        .foregroundStyle(metric == .cpu ? Brand.green : Brand.textTertiary)
                        .frame(width: 60, alignment: .trailing)
                    Text("RAM").font(Brand.mono(8, .bold)).tracking(0.5)
                        .foregroundStyle(metric == .ram ? Brand.amber : Brand.textTertiary)
                        .frame(width: 80, alignment: .trailing)
                }
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(ranked) { r in
                            HStack {
                                Text(r.name).font(Brand.sans(12)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(String(format: "%.0f%%", r.peakCPU)).font(Brand.mono(11))
                                    .foregroundStyle(metric == .cpu ? Brand.green : Brand.textTertiary)
                                    .frame(width: 60, alignment: .trailing)
                                Text(ramLabel(r)).font(Brand.mono(11))
                                    .foregroundStyle(metric == .ram ? Brand.amber : Brand.textTertiary)
                                    .frame(width: 80, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                PillButton(title: "Done") { onClose() }
            }
        }
        .padding(20)
        .frame(width: 440, height: 430)
        .background(Brand.nearBlack)
        .environment(\.colorScheme, .dark)
        .task { load() }
    }

    private var metricToggle: some View {
        HStack(spacing: 2) {
            ForEach(ProcMetric.allCases) { m in
                let on = m == metric
                Button { metric = m } label: {
                    Text(m.rawValue).font(Brand.mono(9, on ? .bold : .regular))
                        .foregroundStyle(on ? Color.black : Brand.textSecondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background { if on { Capsule().fill(.white) } }
                        .contentShape(Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.black.opacity(0.28)))
        .overlay(Capsule().strokeBorder(Brand.hairline, lineWidth: 1))
    }

    private func ramLabel(_ r: Row) -> String {
        r.peakMemBytes > 0 ? Fmt.bytes(Int64(r.peakMemBytes)) : String(format: "%.1f%%", r.peakMem)
    }

    private var rangeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, HH:mm"
        let a = f.string(from: Date(timeIntervalSince1970: TimeInterval(window.since)))
        let b = f.string(from: Date(timeIntervalSince1970: TimeInterval(window.until)))
        return "\(a) – \(b)"
    }

    private func load() {
        // Union of CPU + RAM leaders so both rankings are populated and the
        // toggle just re-sorts in place (same aggregation as the MCP tools).
        let pw = MetricsStore(db: db).processWindow(.init(since: window.since, until: window.until))
        let leaders = pw.ranked(by: .peakCPU, limit: 30) + pw.ranked(by: .peakMem, limit: 30)
        var seen = Set<String>()
        var out: [Row] = []
        for p in leaders where seen.insert(p.name).inserted {
            out.append(Row(name: p.name, peakCPU: p.peakCPU, peakMem: p.peakMem, peakMemBytes: p.peakMemBytes))
        }
        rows = out
        loaded = true
    }
}
