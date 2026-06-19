//
//  WindowDragBlocker.swift
//  Burrow / Components
//
//  A transparent AppKit view that refuses to let the window be dragged by its
//  background. The main window sets `isMovableByWindowBackground = true`, so on
//  mouse-down over non-interactive SwiftUI content AppKit starts moving the
//  WINDOW before any SwiftUI `DragGesture` (with its minimumDistance) can
//  engage — and `.highPriorityGesture` only outranks other *SwiftUI* gestures,
//  never AppKit's window drag. Layering a real NSView whose
//  `mouseDownCanMoveWindow` is false at the hit point stops AppKit from
//  claiming the drag, so a SwiftUI gesture attached alongside actually fires.
//
//  Usage: put it where the drag should win (e.g. a chart's plot overlay) and
//  attach the gesture to it:
//
//      WindowDragBlocker()
//          .highPriorityGesture(DragGesture(minimumDistance: 2) ... )
//

import SwiftUI
import AppKit

struct WindowDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Blocker() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    /// Visually empty but hit-testable (default `hitTest` returns self inside
    /// bounds), so it's the view AppKit queries for `mouseDownCanMoveWindow`
    /// — and it answers "no". It doesn't override the mouse events, so the
    /// SwiftUI gesture recognizer installed on top still receives them.
    private final class Blocker: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}
