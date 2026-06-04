//
//  TopNav.swift
//  Burrow
//
//  The floating top-centre pill: Burrow mark + five lowercase tabs. The
//  active tab is a solid white capsule with near-black text; the rest
//  are quiet. This replaces the old left sidebar entirely — the whole
//  navigation model is "one pill, five tools".
//

import SwiftUI

struct TopNav: View {
    @Binding var selected: Tool

    var body: some View {
        HStack(spacing: 2) {
            BurrowMark()
                .frame(width: 24, height: 24)
                .padding(.leading, 6)
                .padding(.trailing, 4)

            ForEach(Tool.navOrder) { tool in
                tab(tool)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous).fill(Color.black.opacity(0.24))
        )
        .overlay(
            Capsule(style: .continuous).strokeBorder(Brand.hairline, lineWidth: 1)
        )
    }

    private func tab(_ tool: Tool) -> some View {
        let isOn = selected == tool
        return Button {
            withAnimation(.easeOut(duration: 0.16)) { selected = tool }
        } label: {
            Text(tool.label)
                .font(Brand.mono(12, isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Color.black : Brand.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    if isOn {
                        Capsule(style: .continuous).fill(Color.white)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Burrow's mark: a cream disc with a dark burrow mouth (a tunnel arch).
/// Original to us — not the mole silhouette.
struct BurrowMark: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Circle().fill(Brand.cream)
                Path { p in
                    let cx = s * 0.5
                    let baseY = s * 0.70
                    let r = s * 0.27
                    p.move(to: CGPoint(x: cx - r, y: baseY))
                    p.addArc(center: CGPoint(x: cx, y: baseY), radius: r,
                             startAngle: .degrees(180), endAngle: .degrees(360),
                             clockwise: false)
                    p.closeSubpath()
                }
                .fill(Brand.espresso)
            }
            .frame(width: s, height: s)
        }
    }
}
