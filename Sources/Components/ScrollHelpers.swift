//
//  ScrollHelpers.swift
//  Burrow / Components
//
//  SwiftUI exposes no scroller styling, so we reach the enclosing
//  NSScrollView and switch it to the overlay style — thin, auto-hiding,
//  theme-aware. A no-op if the backing view isn't an NSScrollView, so it's
//  safe to attach to any scroll content.
//

import AppKit
import SwiftUI

private struct OverlayScrollers: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            var v: NSView? = nsView.superview
            while let cur = v, !(cur is NSScrollView) { v = cur.superview }
            guard let sv = v as? NSScrollView else { return }
            sv.scrollerStyle = .overlay
            sv.verticalScroller?.controlSize = .small
            sv.horizontalScroller?.controlSize = .small
        }
    }
}

extension View {
    /// Switch the enclosing scroll view to thin, auto-hiding overlay
    /// scrollers. Attach to content *inside* a ScrollView.
    func overlayScrollers() -> some View { background(OverlayScrollers()) }
}

/// Fades content to transparent at the top & bottom edges — the soft
/// "gradient" feel on scroll areas, so rows melt away instead of hard-cutting
/// at the viewport edge. Height-aware, so the fade band stays a roughly
/// constant pixel height at any size.
private struct EdgeFade: ViewModifier {
    var length: CGFloat
    func body(content: Content) -> some View {
        content.mask(
            GeometryReader { geo in
                let f = min(0.5, length / max(geo.size.height, 1))
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: f),
                    .init(color: .black, location: 1 - f),
                    .init(color: .clear, location: 1),
                ], startPoint: .top, endPoint: .bottom)
            }
        )
    }
}

extension View {
    /// Soft-fade the top & bottom edges of a scroll area.
    func fadeEdges(_ length: CGFloat = 24) -> some View { modifier(EdgeFade(length: length)) }
}
