//
//  GlassCard.swift
//  Burrow / Components
//
//  The translucent card + the two small atoms that sit inside it
//  everywhere: the uppercase eyebrow (small glyph + label) and the
//  pill chip. Kept tiny and dependency-free so the dashboard reads as
//  a flat list of `GlassCard { ... }` blocks.
//

import SwiftUI

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 14
    var corner: CGFloat = 16
    var minHeight: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Brand.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Brand.hairline, lineWidth: 1)
            )
    }
}

/// Tiny uppercase section label with a leading glyph — "☼ HEALTH".
struct Eyebrow: View {
    let text: String
    let glyph: String
    var color: Color = Brand.textSecondary

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: glyph)
                .font(.system(size: 9, weight: .bold))
            Text(text.uppercased())
                .font(Brand.mono(10, .bold))
                .tracking(0.8)
        }
        .foregroundStyle(color)
    }
}

/// Small rounded pill used for inline status ("normal", "HTTP", "Good").
struct Chip: View {
    let text: String
    var color: Color = Brand.textSecondary

    var body: some View {
        Text(text)
            .font(Brand.mono(10, .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}
