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
    @State private var showFDAGate = false

    var body: some View {
        Group {
            if showFDAGate {
                fdaGate
            } else {
                HStack(spacing: 0) {
                    sidebar.frame(width: 232)
                    Rectangle().fill(Brand.hairline).frame(width: 1)
                    mainArea
                }
            }
        }
        .onAppear { evaluateStart() }
        .onChange(of: isActive) { _, now in if now { evaluateStart() } }
    }

    /// Analyze auto-scans the home folder on first open — exactly when
    /// the macOS "access data from other apps" flood hits (issue #3). If
    /// we lack Full Disk Access and the user hasn't dismissed the notice,
    /// gate the scan behind it rather than walking protected dirs
    /// unannounced.
    private func evaluateStart() {
        guard isActive, !model.started else { return }
        if Privacy.shouldOfferFullDiskAccessNow() {
            showFDAGate = true
        } else {
            // FDA may have just been granted (or the notice dismissed) while
            // the gate was up — make sure it doesn't keep covering the view.
            showFDAGate = false
            model.startIfNeeded()
        }
    }

    private var fdaGate: some View {
        VStack(spacing: 16) {
            Spacer()
            FullDiskAccessNotice(
                accent: Tool.analyze.accent,
                continueLabel: "Scan anyway",
                onContinue: { showFDAGate = false; model.startIfNeeded() },
                onDontAskAgain: {
                    Store.fullDiskAccessNoticeDismissed = true
                    showFDAGate = false
                    model.startIfNeeded()
                })
            .frame(maxWidth: 460)
            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
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
        .contextMenu {
            Button(NSLocalizedString("Reveal in Finder", comment: "")) { AnalyzeIcons.reveal(e.path) }
            Divider()
            Button(NSLocalizedString("Move to Trash", comment: ""), role: .destructive) { model.trash(e) }
        }
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
                    TreemapView(entries: model.entries,
                                onOpen: { e in model.drill(into: e) },
                                onTrash: { e in model.trash(e) })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button { model.goUp() } label: {
                Image(systemName: "arrow.up").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(model.canGoUp ? Brand.textSecondary : Brand.textTertiary.opacity(0.35))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!model.canGoUp)
            .help(NSLocalizedString("Go up", comment: ""))
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
    var onTrash: (DiskScanEntry) -> Void = { _ in }
    @State private var hoveredID: String?

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
            // One immediate-mode draw pass, not 120 nested SwiftUI cells. The
            // old ZStack-of-views version re-ran the layout engine over the
            // whole cell tree on every hover tick (onContinuousHover →
            // hoveredID → body re-eval), which froze the main thread ≥2 s on
            // large maps — a real, escalating app-hang on both Intel and
            // Apple Silicon (Sentry BURROW-1/2). A Canvas redraw is a single
            // cheap pass, and hit-testing already runs off the `rects` array,
            // so the cells never needed to be real views.
            Canvas { ctx, _ in
                for (i, e) in shown.enumerated() where i < rects.count {
                    drawCell(e, rects[i], color: Self.palette[i % Self.palette.count],
                             isHover: hoveredID == e.id, into: ctx)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            // One hover hit-test over the laid-out rects — per-cell `.onHover`
            // tracking areas can stick or misfire, a single region can't, and
            // `.ended` reliably clears the highlight when the mouse leaves.
            .onContinuousHover { phase in
                switch phase {
                case .active(let pt): hoveredID = zip(shown, rects).first { _, r in r.contains(pt) }?.0.id
                case .ended:          hoveredID = nil
                }
            }
            // Click-to-drill maps the tap point back to a cell via the same
            // rects; the context menu acts on whatever the cursor hovers
            // (a right-click hovers the cell first), so both behaviors survive
            // the move off per-cell views.
            .gesture(SpatialTapGesture().onEnded { v in
                if let e = zip(shown, rects).first(where: { $0.1.contains(v.location) })?.0 { onOpen(e) }
            })
            .contextMenu {
                if let id = hoveredID, let e = shown.first(where: { $0.id == id }) {
                    Button(NSLocalizedString("Reveal in Finder", comment: "")) { AnalyzeIcons.reveal(e.path) }
                    if e.isDir { Button(NSLocalizedString("Open here", comment: "")) { onOpen(e) } }
                    Divider()
                    Button(NSLocalizedString("Move to Trash", comment: ""), role: .destructive) { onTrash(e) }
                }
            }
        }
    }

    /// Draw one treemap cell into the shared Canvas context: rounded gradient
    /// fill, border, and — if the cell is large enough — an icon + name + size
    /// label clipped to the cell. Mirrors the old per-cell view 1:1.
    private func drawCell(_ e: DiskScanEntry, _ r: CGRect, color: Color, isHover: Bool, into ctx: GraphicsContext) {
        let cell = r.insetBy(dx: 1, dy: 1)   // 2px gutter between cells
        guard cell.width > 1, cell.height > 1 else { return }
        let path = Path(roundedRect: cell, cornerRadius: 4, style: .continuous)
        ctx.fill(path, with: .linearGradient(
            Gradient(colors: [color.opacity(isHover ? 0.95 : 0.8),
                              color.opacity(isHover ? 0.7 : 0.55)]),
            startPoint: CGPoint(x: cell.midX, y: cell.minY),
            endPoint: CGPoint(x: cell.midX, y: cell.maxY)))
        ctx.stroke(path, with: .color(isHover ? .white.opacity(0.6) : .black.opacity(0.25)), lineWidth: 1)

        guard cell.width > 66, cell.height > 28 else { return }
        var label = ctx
        label.clip(to: path)
        label.addFilter(.shadow(color: .black.opacity(0.4), radius: 2))

        var lines: [GraphicsContext.ResolvedText] = []
        if cell.width > 96, cell.height > 52 {
            lines.append(label.resolve(Text(Image(systemName: e.isDir ? "folder.fill" : "doc.fill"))
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))))
        }
        lines.append(label.resolve(Text(e.name).font(Brand.sans(11, .medium)).foregroundStyle(.white)))
        lines.append(label.resolve(Text(Fmt.bytes(e.size)).font(Brand.mono(9)).foregroundStyle(.white.opacity(0.85))))

        // Measure single-line (generous width) and stack centered; the clip
        // above trims any overflow, matching the old `.lineLimit(1)` cell.
        let probe = CGSize(width: 4000, height: cell.height)
        let sizes = lines.map { $0.measure(in: probe) }
        let gap: CGFloat = 2
        let totalH = sizes.reduce(0) { $0 + $1.height } + gap * CGFloat(max(0, lines.count - 1))
        var y = cell.midY - totalH / 2
        for (line, sz) in zip(lines, sizes) {
            label.draw(line, at: CGPoint(x: cell.midX, y: y + sz.height / 2), anchor: .center)
            y += sz.height + gap
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
    private(set) var started = false
    private let opId = UUID()
    /// Cache scan results by path so navigating back/into already-seen
    /// folders is instant instead of re-running `mo analyze` (~4 CPU-s)
    /// each time. Refresh clears the current path to force a fresh walk.
    private var cache: [String: (entries: [DiskScanEntry], total: Int64)] = [:]

    var summaryLine: String {
        entries.isEmpty ? "—" : String(format: NSLocalizedString("%d items · %@", comment: ""), entries.count, Fmt.bytes(total))
    }
    var usageLine: String { String(format: NSLocalizedString("%@ in %d items", comment: ""), Fmt.bytes(total), entries.count) }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        crumbs = []
        scan(NSHomeDirectory(), name: NSLocalizedString("Home", comment: ""), push: true)
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
        cache[last.path] = nil   // drop the cached walk so we re-scan
        scan(last.path, name: last.name, push: false, force: true)
    }

    /// Whether there's a parent to climb to (Home isn't the ceiling — you can
    /// go up to /Users, /, external volumes, …). False only at the filesystem root.
    var canGoUp: Bool {
        guard let p = crumbs.first?.path, !p.isEmpty else { return false }
        return p != "/"
    }

    /// Climb to the parent of the current root, making it the new breadcrumb root.
    func goUp() {
        guard let root = crumbs.first else { return }
        let parent = (root.path as NSString).deletingLastPathComponent
        guard !parent.isEmpty, parent != root.path else { return }
        let name = parent == "/" ? "/" : (parent as NSString).lastPathComponent
        crumbs = []
        scan(parent, name: name.isEmpty ? "/" : name, push: true)
    }

    /// Move an item to the Trash (recoverable), after an explicit confirm. The
    /// treemap is exactly where you spot a forgotten 8 GB folder, so removing it
    /// shouldn't mean leaving for Finder. Updates the view in place and drops the
    /// current folder's cached walk so a later refresh recomputes honestly.
    func trash(_ e: DiskScanEntry) {
        let alert = NSAlert()
        alert.messageText = String(format: NSLocalizedString("Move \u{201C}%@\u{201D} to Trash?", comment: ""), e.name)
        alert.informativeText = String(format: NSLocalizedString("This moves %@ (%@) to the Trash, where you can restore it.", comment: ""),
                                       e.isDir ? NSLocalizedString("this folder", comment: "") : NSLocalizedString("this file", comment: ""),
                                       Fmt.bytes(e.size))
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("Move to Trash", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try FileManager.default.trashItem(at: URL(fileURLWithPath: e.path), resultingItemURL: nil)
            entries.removeAll { $0.id == e.id }
            total = max(0, total - e.size)
            if let last = crumbs.last { cache[last.path] = nil }
        } catch {
            let err = NSAlert()
            err.messageText = NSLocalizedString("Couldn't move to Trash", comment: "")
            err.informativeText = error.localizedDescription
            err.alertStyle = .warning
            err.runModal()
        }
    }

    /// Monotonic token: every navigation (scan start OR instant cache hit)
    /// bumps it, and a finishing background scan applies its result only if
    /// it is still the newest — a slow walk must not clobber the folder the
    /// breadcrumbs have since moved to. (Same pattern as HistoryView's
    /// `loadGen`.)
    private var scanGen = 0

    private func scan(_ path: String, name: String, push: Bool, force: Bool = false) {
        if push { crumbs.append((name, path)) }
        scanGen += 1
        let gen = scanGen
        // Cache hit → show instantly; don't re-run `mo analyze` for a
        // folder we already walked (back/drill is the common navigation).
        if !force, let cached = cache[path] {
            entries = cached.entries; total = cached.total; loading = false; error = nil
            return
        }
        loading = true
        error = nil
        OperationCenter.shared.begin(opId, label: String(format: NSLocalizedString("Analyzing %@", comment: ""), name))
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let r = try DiskScanner.scan(path)
                let sum = r.totalSize > 0 ? r.totalSize : r.entries.reduce(0) { $0 + $1.size }
                Task { @MainActor in
                    self.cache[path] = (r.entries, sum)   // cache stays warm either way
                    guard gen == self.scanGen else { return }
                    self.entries = r.entries
                    self.total = sum
                    self.loading = false
                    OperationCenter.shared.end(self.opId, success: true,
                                               detail: String(format: NSLocalizedString("%d items · %@", comment: ""), r.entries.count, Fmt.bytes(sum)))
                }
            } catch {
                Task { @MainActor in
                    guard gen == self.scanGen else { return }
                    self.error = error.localizedDescription
                    self.loading = false
                    OperationCenter.shared.end(self.opId, success: false, detail: NSLocalizedString("scan failed", comment: ""))
                }
            }
        }
    }
}
