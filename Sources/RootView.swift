//
//  RootView.swift
//  Burrow
//
//  The window shell: behind-window vibrancy → per-tool tint scrim →
//  top pill nav → tool content. Replaces the old NavigationSplitView /
//  sidebar MainView entirely. Only Status is real today; the other four
//  tools render the themed ComingSoonView so navigation already feels
//  whole.
//

import SwiftUI

struct RootView: View {
    let db: DB
    let sampler: Sampler
    weak var delegate: AppDelegate?

    @State private var tool: Tool

    init(db: DB, sampler: Sampler, delegate: AppDelegate?, initialTool: Tool = .status) {
        self.db = db
        self.sampler = sampler
        self.delegate = delegate
        self._tool = State(initialValue: initialTool)
    }

    var body: some View {
        ZStack {
            VisualEffectBackground().ignoresSafeArea()
            tool.scrim.ignoresSafeArea()

            VStack(spacing: 0) {
                TopNav(selected: $tool)
                    .padding(.top, 13)
                    .padding(.bottom, 10)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 940, minHeight: 640)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.25), value: tool)
    }

    // All five tabs stay alive in a ZStack — switching just changes which
    // is visible/interactive. This preserves each tab's state and any
    // in-flight `mo` job across tab switches (the bug where switching tabs
    // killed the previous tab's session). Heavy tabs lazy-start via
    // `isActive` so we don't scan the disk / list apps at launch.
    private var content: some View {
        ZStack {
            StatusView(db: db, sampler: sampler).tabVisible(tool == .status)
            AnalyzeView(isActive: tool == .analyze).tabVisible(tool == .analyze)
            SoftwareView(isActive: tool == .apps).tabVisible(tool == .apps)
            CleanView().tabVisible(tool == .clean)
            OptimizeView().tabVisible(tool == .optimize)
        }
    }
}

private extension View {
    /// Keep a view in the hierarchy (so its @StateObject + work survive)
    /// while hiding it and disabling interaction when not the active tab.
    @ViewBuilder
    func tabVisible(_ visible: Bool) -> some View {
        self.opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
    }
}
