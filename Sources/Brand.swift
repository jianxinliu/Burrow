//
//  Brand.swift
//  Burrow
//
//  Burrow's own visual language — built to match mole.fit's *experience*
//  (translucent window, glass cards, monospaced numerics, per-tool
//  colour) while staying our own brand: our palette, our marks, our
//  copy. This is deliberately separate from the legacy `Theme` enum so
//  the redesign can land without disturbing the older views that still
//  reference `Theme.*`.
//
//  Three font roles:
//    * mono    — labels, numerics, the tab bar. The "instrument" voice.
//    * rounded — friendly UI chrome where mono feels too rigid.
//    * serif   — the one expressive voice: taglines / hero copy.
//

import SwiftUI

extension Color {
    /// 0xRRGGBB literal → sRGB Color. Cheaper to read than three
    /// Double divisions at every call site.
    init(hex: UInt, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

enum Brand {
    // MARK: Surfaces & text (everything reads over a dark, tinted glass)
    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary  = Color.white.opacity(0.40)

    static let hairline      = Color.white.opacity(0.085)
    static let cardFill      = Color.white.opacity(0.055)
    static let cardFillHover = Color.white.opacity(0.10)
    static let chipFill      = Color.white.opacity(0.09)
    static let trackFill     = Color.white.opacity(0.10)
    static let nearBlack     = Color(hex: 0x0B0B0D)

    // MARK: Metric accents (conventional monitor colour-coding)
    static let green  = Color(hex: 0x57D58E)
    static let gold   = Color(hex: 0xE6A93C)
    static let amber  = Color(hex: 0xF0B24A)
    static let orange = Color(hex: 0xF2894E)
    static let blue   = Color(hex: 0x5AA8F0)
    static let red    = Color(hex: 0xF0604E)

    // MARK: Brand creams (the mark)
    static let cream  = Color(hex: 0xF3ECDD)
    static let espresso = Color(hex: 0x241B12)

    // MARK: Type
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}
