//
//  AnalyzeView.swift
//  Burrow
//
//  The Analyze tab — Burrow's take on mole.fit's "Jupiter" disk map.
//  A squarified treemap of a directory (via `mo analyze --json`, the
//  existing DiskScanner + Treemap engine), a left rail of the biggest
//  children, a breadcrumb, and drill-in by click. Reveal / Trash live
//  in each block's context menu.
//

import SwiftUI
import AppKit

struct AnalyzeView: View {
    @StateObject private var model = AnalyzeModel()
    var isActive: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 232)
            Rectangle().fill(Brand.hairline).frame(width: 1)
            mainArea
        }
        .onAppear { if isActive { model.startIfNeeded() } }
        .onChange(of: isActive) { _, now in if now { model.startIfNeeded() } }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 8) {
                Circle()
                    .fill(RadialGradient(colors: [Tool.analyze.accent.opacity(0.9), Tool.analyze.accent.opacity(0.15)],
                                         center: .init(x: 0.4, y: 0.35), startRadius: 2, endRadius: 60))
                    .frame(width: 78, height: 78)
                    .shadow(color: Tool.analyze.accent.opacity(0.4), radius: 22)
                Text(model.summaryLine)
                    .font(Brand.mono(11)).foregroundStyle(Brand.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 18).padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 1) {
                    ForEach(model.entries.prefix(40)) { e in
                        sidebarRow(e)
                    }
                }
                .padding(.horizontal, 10)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func sidebarRow(_ e: DiskScanEntry) -> some View {
        Button { model.drill(into: e) } label: {
            HStack(spacing: 8) {
                Image(nsImage: AnalyzeIcons.icon(for: e))
                    .resizable().frame(width: 17, height: 17)
                VStack(alignment: .leading, spacing: 0) {
                    Text(e.name).font(Brand.sans(12)).foregroundStyle(Brand.textPrimary).lineLimit(1)
                    Text(Fmt.bytes(e.size)).font(Brand.mono(10)).foregroundStyle(Brand.textTertiary)
                }
                Spacer(minLength: 2)
                if e.isDir {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Brand.textTertiary)
                }
            }
            .padding(.vertical, 5).padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!e.isDir)
    }

    // MARK: Main

    private var mainArea: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 16).padding(.vertical, 11)
            Rectangle().fill(Brand.hairline).frame(height: 1)
            ZStack {
                if model.loading {
                    ProgressView("Scanning…").controlSize(.large)
                        .font(Brand.mono(11)).tint(Tool.analyze.accent)
                } else if let err = model.error {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 22)).foregroundStyle(Brand.orange)
                        Text(err).font(Brand.mono(11)).foregroundStyle(Brand.textSecondary)
                            .multilineTextAlignment(.center).frame(maxWidth: 340)
                    }
                } else {
                    TreemapView(entries: model.entries) { e in model.drill(into: e) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.crumbs.enumerated()), id: \.offset) { idx, crumb in
                if idx > 0 {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Brand.textTertiary)
                }
                Button { model.goToCrumb(idx) } label: {
                    Text(crumb.name)
                        .font(Brand.mono(12, idx == model.crumbs.count - 1 ? .semibold : .regular))
                        .foregroundStyle(idx == model.crumbs.count - 1 ? Brand.textPrimary : Brand.textSecondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(model.usageLine).font(Brand.mono(10)).foregroundStyle(Brand.textTertiary)
            Button { model.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Brand.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Treemap rendering

struct TreemapView: View {
    let entries: [DiskScanEntry]
    let onOpen: (DiskScanEntry) -> Void
    @State private var hovered: String?

    private static let palette: [Color] = [
        Color(hex: 0x4FA3E3), Color(hex: 0x57C2A5), Color(hex: 0xE6A93C),
        Color(hex: 0xF0884E), Color(hex: 0x8E84F0), Color(hex: 0x5AA8F0),
        Color(hex: 0xE0667E), Color(hex: 0x6FB06A),
    ]

    var body: some View {
        GeometryReader { geo in
            let shown = Array(entries.filter { $0.size > 0 }.prefix(120))
            let rects = Treemap.layout(weights: shown.map { Double($0.size) },
                                       in: CGRect(x: 0, y: 0, width: geo.size.width, height: geo.size.height))
            ZStack(alignment: .topLeading) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, e in
                    block(e, rects[i], color: Self.palette[i % Self.palette.count])
                }
            }
        }
    }

    @ViewBuilder
    private func block(_ e: DiskScanEntry, _ r: CGRect, color: Color) -> some View {
        let w = max(0, r.width - 2)
        let h = max(0, r.height - 2)
        let isHover = hovered == e.id
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(isHover ? 0.95 : 0.8), color.opacity(isHover ? 0.7 : 0.55)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
            .overlay(label(e, w: w, h: h))
            .frame(width: w, height: h)
            .offset(x: r.minX + 1, y: r.minY + 1)
            .onHover { hovered = $0 ? e.id : (hovered == e.id ? nil : hovered) }
            .onTapGesture { onOpen(e) }
            .contextMenu {
                Button("Reveal in Finder") { AnalyzeIcons.reveal(e.path) }
                if e.isDir { Button("Open here") { onOpen(e) } }
            }
    }

    @ViewBuilder
    private func label(_ e: DiskScanEntry, w: CGFloat, h: CGFloat) -> some View {
        if w > 66, h > 28 {
            VStack(spacing: 2) {
                if w > 96, h > 52 {
                    Image(systemName: e.isDir ? "folder.fill" : "doc.fill")
                        .font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))
                }
                Text(e.name).font(Brand.sans(11, .medium)).foregroundStyle(.white).lineLimit(1)
                Text(Fmt.bytes(e.size)).font(Brand.mono(9)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(4).shadow(color: .black.opacity(0.4), radius: 2)
        }
    }
}

// MARK: - Icons / Finder helpers

enum AnalyzeIcons {
    private static var cache: [String: NSImage] = [:]
    static func icon(for e: DiskScanEntry) -> NSImage {
        if let c = cache[e.path] { return c }
        let img = NSWorkspace.shared.icon(forFile: e.path)
        cache[e.path] = img
        return img
    }
    static func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}

// MARK: - Model

@MainActor
final class AnalyzeModel: ObservableObject {
    @Published var entries: [DiskScanEntry] = []
    @Published var crumbs: [(name: String, path: String)] = []
    @Published var loading = false
    @Published var error: String?
    private var total: Int64 = 0
    private var started = false

    var summaryLine: String {
        entries.isEmpty ? "—" : "\(entries.count) items · \(Fmt.bytes(total))"
    }
    var usageLine: String { "\(Fmt.bytes(total)) in \(entries.count) items" }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        crumbs = []
        scan(NSHomeDirectory(), name: "Home", push: true)
    }

    func drill(into e: DiskScanEntry) {
        guard e.isDir else { return }
        scan(e.path, name: e.name, push: true)
    }

    func goToCrumb(_ idx: Int) {
        guard idx < crumbs.count else { return }
        let c = crumbs[idx]
        crumbs = Array(crumbs.prefix(idx + 1))
        scan(c.path, name: c.name, push: false)
    }

    func refresh() {
        guard let last = crumbs.last else { return }
        scan(last.path, name: last.name, push: false)
    }

    private func scan(_ path: String, name: String, push: Bool) {
        loading = true
        error = nil
        if push { crumbs.append((name, path)) }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let r = try DiskScanner.scan(path)
                let sum = r.totalSize > 0 ? r.totalSize : r.entries.reduce(0) { $0 + $1.size }
                Task { @MainActor in
                    self.entries = r.entries
                    self.total = sum
                    self.loading = false
                }
            } catch {
                Task { @MainActor in
                    self.error = error.localizedDescription
                    self.loading = false
                }
            }
        }
    }
}
