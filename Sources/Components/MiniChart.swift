//
//  MiniChart.swift
//  Burrow / Components
//
//  Inline sparkline with two looks: `.area` (filled gradient under a
//  line — memory, network, fan) and `.bars` (discrete columns — CPU, GPU).
//  No axes, no labels: just the recent shape of a number. Pure `Path`
//  rendering so it stays crisp at ~30 px tall where SwiftUI Charts'
//  margins would eat everything.
//

import SwiftUI

struct MiniChart: View {
    enum Style { case area, bars }

    let values: [Double]
    var color: Color
    var style: Style = .area

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let (lo, hi) = bounds()
            let denom = max(hi - lo, 0.0001)

            if values.count < 2 {
                // Flat baseline so an empty card doesn't look broken.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h - 1))
                    p.addLine(to: CGPoint(x: w, y: h - 1))
                }
                .stroke(color.opacity(0.25), lineWidth: 1)
            } else {
                switch style {
                case .area: area(w: w, h: h, lo: lo, denom: denom)
                case .bars: bars(w: w, h: h, lo: lo, denom: denom)
                }
            }
        }
    }

    private func y(_ v: Double, _ h: CGFloat, _ lo: Double, _ denom: Double) -> CGFloat {
        (1.0 - CGFloat((v - lo) / denom)) * h
    }

    @ViewBuilder
    private func area(w: CGFloat, h: CGFloat, lo: Double, denom: Double) -> some View {
        let n = values.count
        let pts: [CGPoint] = values.enumerated().map { i, v in
            CGPoint(x: w * CGFloat(i) / CGFloat(n - 1), y: y(v, h, lo, denom))
        }
        ZStack {
            Path { p in
                guard let first = pts.first, let last = pts.last else { return }
                p.move(to: CGPoint(x: first.x, y: h))
                p.addLine(to: first)
                for pt in pts.dropFirst() { p.addLine(to: pt) }
                p.addLine(to: CGPoint(x: last.x, y: h))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [color.opacity(0.30), color.opacity(0.02)],
                                 startPoint: .top, endPoint: .bottom))
            Path { p in
                guard let first = pts.first else { return }
                p.move(to: first)
                for pt in pts.dropFirst() { p.addLine(to: pt) }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }

    @ViewBuilder
    private func bars(w: CGFloat, h: CGFloat, lo: Double, denom: Double) -> some View {
        let n = values.count
        let slot = w / CGFloat(n)
        let barW = max(1.5, slot * 0.62)
        ZStack(alignment: .bottomLeading) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                let bh = max(1.5, (1.0 - (1.0 - CGFloat((v - lo) / denom))) * h)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(color.opacity(0.85))
                    .frame(width: barW, height: bh)
                    .offset(x: CGFloat(i) * slot + (slot - barW) / 2)
            }
        }
        .frame(width: w, height: h, alignment: .bottomLeading)
    }

    /// Stable vertical scale: floor at 0 (these are non-negative metrics)
    /// and pad a flat series so it doesn't pin to the baseline.
    private func bounds() -> (lo: Double, hi: Double) {
        let lo = min(values.min() ?? 0, 0)
        let hi = values.max() ?? 1
        if hi - lo < 0.001 { return (lo, hi + 1) }
        return (lo, hi)
    }
}
