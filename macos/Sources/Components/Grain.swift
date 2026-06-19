//
//  Grain.swift
//  Burrow / Components
//
//  A faint film-grain texture, generated once with Core Image and tiled
//  over the window ground (below the content) so the warm gradient reads as
//  a tactile surface instead of a flat fill. Cheap: one 256² noise tile,
//  drawn at low opacity, no per-frame work.
//

import CoreImage
import SwiftUI

enum Grain {
    /// One desaturated noise tile, generated lazily and reused.
    static let tile: Image? = {
        guard let filter = CIFilter(name: "CIRandomGenerator"),
              let noise = filter.outputImage else { return nil }
        let rect = CGRect(x: 0, y: 0, width: 256, height: 256)
        let mono = noise.cropped(to: rect)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0,
                kCIInputContrastKey: 1.0,
            ])
        guard let cg = CIContext(options: nil).createCGImage(mono, from: rect) else { return nil }
        return Image(decorative: cg, scale: 1, orientation: .up).resizable(resizingMode: .tile)
    }()
}

/// Tiled grain, low opacity, non-interactive — drop into a background ZStack.
struct GrainOverlay: View {
    /// Explicit override; when nil the opacity adapts to the colour scheme —
    /// dark mode shows the grain louder, so it's dialed back there.
    var opacity: Double? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if let tile = Grain.tile {
            tile
                .opacity(opacity ?? (scheme == .dark ? 0.04 : 0.06))
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
    }
}
