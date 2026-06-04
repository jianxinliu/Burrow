//
//  ComingSoonView.swift
//  Burrow
//
//  Placeholder for the four tools not yet rebuilt (Clean / Software /
//  Optimize / Analyze). It's not a dead grey screen — it carries the
//  tool's accent, a soft hero orb (our abstract stand-in for mole's
//  planets), the title, and our tagline — so the per-tool theming and
//  navigation already feel finished while the real content lands.
//

import SwiftUI

struct ComingSoonView: View {
    let tool: Tool

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            heroOrb
            VStack(spacing: 8) {
                Text(tool.title)
                    .font(Brand.serif(28, .medium))
                    .foregroundStyle(Brand.textPrimary)
                Text(tool.tagline)
                    .font(Brand.serif(15))
                    .italic()
                    .foregroundStyle(Brand.textSecondary)
            }
            Text("Coming soon")
                .font(Brand.mono(11, .medium))
                .foregroundStyle(Brand.textTertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().strokeBorder(Brand.hairline, lineWidth: 1))
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var heroOrb: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    colors: [tool.accent.opacity(0.85), tool.accent.opacity(0.12)],
                    center: .init(x: 0.4, y: 0.35), startRadius: 4, endRadius: 130))
            Circle()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        }
        .frame(width: 150, height: 150)
        .shadow(color: tool.accent.opacity(0.35), radius: 40)
    }
}
