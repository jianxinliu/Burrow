//
//  BurrowIcons.swift
//  Burrow
//
//  Programmatic icons that aren't asset-catalog material: the menu-bar
//  template glyph (a single-colour silhouette that adapts to light/dark
//  menu bars). The Dock / Finder icon comes from Assets.xcassets/AppIcon.
//

import AppKit

enum BurrowIcons {
    /// Template (mask) menu-bar glyph: a disc with the burrow mouth
    /// punched out, so it reads as the mark in monochrome and tints with
    /// the menu bar.
    static let menuBar: NSImage = {
        let size = NSSize(width: 16, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            let disc = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            let cx = rect.midX
            let baseY = rect.height * 0.40
            let r = rect.width * 0.27
            let dome = NSBezierPath()
            dome.move(to: NSPoint(x: cx - r, y: baseY))
            dome.appendArc(withCenter: NSPoint(x: cx, y: baseY), radius: r,
                           startAngle: 180, endAngle: 0, clockwise: true)
            dome.close()
            disc.append(dome)
            disc.windingRule = .evenOdd
            NSColor.black.setFill()
            disc.fill()
            return true
        }
        img.isTemplate = true
        return img
    }()
}
