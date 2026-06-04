//
//  Treemap.swift
//  Burrow
//
//  Pure squarified treemap layout. Given a list of positive weights and
//  a target rectangle, returns a CGRect for each weight that:
//    1. Sums to the target rect with no overlap and no gaps.
//    2. Keeps rectangles as close to square as possible (low aspect
//       ratios are easier to compare visually).
//
//  Algorithm: Bruls, Huijsen & van Wijk (2000), "Squarified Treemaps".
//  Greedy row-packing — walk inputs largest-first, accumulate into the
//  current row, finalize when the next addition would make the worst
//  aspect ratio worse than the current row's. Rotate orientation when
//  the remaining strip becomes wider than tall (and vice versa).
//
//  Pure module — no SwiftUI, no AppKit, no IO. Drives DiskMapView's
//  rendering but is testable in isolation.
//

import CoreGraphics

enum Treemap {
    /// Layout `weights` (positive doubles) into `bounds`. Returns one
    /// CGRect per weight, in the same order. Sum of areas == bounds.area
    /// to within floating-point noise.
    ///
    /// Weights of 0 produce zero-area rectangles, anchored at the
    /// current cursor — callers should filter them out before layout
    /// if that matters (DiskMapView does).
    static func layout(weights: [Double], in bounds: CGRect) -> [CGRect] {
        guard !weights.isEmpty, bounds.width > 0, bounds.height > 0 else {
            return Array(repeating: .zero, count: weights.count)
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return Array(repeating: .zero, count: weights.count) }

        // Sort descending while remembering the original index — the
        // output rectangle for input i needs to land at index i in the
        // returned array, but the algorithm walks largest-first.
        let indexed = weights.enumerated().map { (idx: $0.offset, w: $0.element) }
            .sorted { $0.w > $1.w }

        // Scale weights to area so we can do all the math in pixel
        // coordinates. Doing it the other way (areas in weight units)
        // would lose precision on a 1px-wide leftover strip.
        let scale = Double(bounds.width * bounds.height) / total
        let scaledWeights = indexed.map { $0.w * scale }

        var output = Array(repeating: CGRect.zero, count: weights.count)
        var remaining = bounds  // shrinking rectangle as rows are placed
        var i = 0

        while i < scaledWeights.count {
            // Start a new row with the first un-placed weight, then
            // greedily add subsequent weights as long as the worst
            // aspect ratio improves (or stays the same).
            let shorter = min(remaining.width, remaining.height)
            var row: [Double] = [scaledWeights[i]]
            var j = i + 1
            while j < scaledWeights.count {
                let candidate = row + [scaledWeights[j]]
                if Self.worstAspect(of: candidate, alongLength: Double(shorter))
                    <= Self.worstAspect(of: row, alongLength: Double(shorter)) {
                    row = candidate
                    j += 1
                } else {
                    break
                }
            }
            // Place this row.
            let rowRects = Self.placeRow(row, in: remaining)
            for (k, rect) in rowRects.enumerated() {
                let origIdx = indexed[i + k].idx
                output[origIdx] = rect
            }
            // Trim the remaining rectangle on the side we just used.
            remaining = Self.trimRemaining(after: rowRects, from: remaining)
            i += row.count
        }

        return output
    }

    /// Worst aspect ratio in a row, i.e. max(longer/shorter) across all
    /// rectangles in the row if it were placed against a side of length
    /// `length`. Used as the greedy comparison metric — adding to the
    /// row continues while this stays ≤ the previous step's worst.
    private static func worstAspect(of row: [Double], alongLength length: Double) -> Double {
        guard !row.isEmpty, length > 0 else { return .infinity }
        let s = row.reduce(0, +)
        let rmax = row.max() ?? 0
        let rmin = row.min() ?? 0
        guard s > 0, rmin > 0 else { return .infinity }
        // Two candidate worst-cases — the squarified paper's formula.
        let a = (length * length * rmax) / (s * s)
        let b = (s * s) / (length * length * rmin)
        return max(a, b)
    }

    /// Place `row`'s rectangles along the SHORTER side of `bounds` — the
    /// squarified convention, and what `worstAspect` above assumes. The
    /// strip's thickness (perpendicular to the shorter side) is
    /// rowArea / shorterSide; each item's extent along the shorter side
    /// is proportional to its weight, so the row's items sum to the full
    /// shorter side.
    ///
    /// (The earlier version laid rows along the *longer* side, which is
    /// inconsistent with the aspect metric and degenerates into
    /// full-width horizontal strips for steeply-skewed inputs — i.e. a
    /// real folder tree. This is the fix for that.)
    private static func placeRow(_ row: [Double], in bounds: CGRect) -> [CGRect] {
        let shorter = min(bounds.width, bounds.height)
        let s = row.reduce(0, +)
        guard shorter > 0, s > 0 else {
            return Array(repeating: .zero, count: row.count)
        }
        let thickness = CGFloat(s) / shorter
        var rects: [CGRect] = []
        rects.reserveCapacity(row.count)

        if bounds.width >= bounds.height {
            // Shorter side is the height → vertical column on the left
            // edge, items stacked top→bottom, column width = thickness.
            let x = bounds.minX
            var y = bounds.minY
            for w in row {
                let h = CGFloat(w) / thickness   // == w * height / s
                rects.append(CGRect(x: x, y: y, width: thickness, height: h))
                y += h
            }
        } else {
            // Shorter side is the width → horizontal band on the top
            // edge, items left→right, band height = thickness.
            var x = bounds.minX
            let y = bounds.minY
            for w in row {
                let wd = CGFloat(w) / thickness  // == w * width / s
                rects.append(CGRect(x: x, y: y, width: wd, height: thickness))
                x += wd
            }
        }
        return rects
    }

    /// Trim the strip the row just consumed off the shorter side.
    private static func trimRemaining(after rowRects: [CGRect], from bounds: CGRect) -> CGRect {
        guard let first = rowRects.first else { return bounds }
        if bounds.width >= bounds.height {
            // Consumed a vertical column of `thickness` width on the left.
            let consumed = first.width
            return CGRect(x: bounds.minX + consumed,
                          y: bounds.minY,
                          width: max(0, bounds.width - consumed),
                          height: bounds.height)
        } else {
            // Consumed a horizontal band of `thickness` height on top.
            let consumed = first.height
            return CGRect(x: bounds.minX,
                          y: bounds.minY + consumed,
                          width: bounds.width,
                          height: max(0, bounds.height - consumed))
        }
    }
}
