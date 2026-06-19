//
//  VisualEffectBackground.swift
//  Burrow / Components
//
//  Bridges NSVisualEffectView into SwiftUI so the window can sample and
//  blur whatever is behind it (the desktop wallpaper, other windows).
//  This is what gives the app its "floating glass over the wallpaper"
//  silhouette — the single biggest thing the old opaque-sidebar build
//  was missing. Paired with a non-opaque, clear-background NSWindow
//  (see AppDelegate) and a per-tool tint scrim on top.
//

import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
        v.state = .active
    }
}
