//
//  DevHygiene.swift
//  Burrow
//
//  Dev hygiene page (roadmap C.9): break out what generic cleaners lump
//  together — Xcode, containers, package-manager caches, toolchains — each
//  with size and a per-item action. This is the catalog (which ecosystem owns
//  which paths) plus aggregation. The on-disk size scan, the "hide what isn't
//  installed" existence check, and the confirm-gated actions are integration.
//

import Foundation

enum DevHygiene {
    struct Ecosystem: Equatable {
        let name: String
        /// Absolute paths this ecosystem's reclaimable data lives in.
        let paths: [String]
    }

    /// The known ecosystems and their cache/artifact roots, resolved under
    /// `home`. Stage 1 surfaces these read-only; integration hides any whose
    /// paths don't exist and attaches sizes.
    static func catalog(home: String) -> [Ecosystem] {
        func p(_ suffix: String) -> String { home + "/" + suffix }
        return [
            Ecosystem(name: "Xcode", paths: [
                p("Library/Developer/Xcode/DerivedData"),
                p("Library/Developer/Xcode/iOS DeviceSupport"),
                p("Library/Developer/CoreSimulator/Caches"),
            ]),
            Ecosystem(name: "Homebrew", paths: [p("Library/Caches/Homebrew")]),
            Ecosystem(name: "npm", paths: [p(".npm")]),
            Ecosystem(name: "pnpm", paths: [p("Library/pnpm/store"), p(".local/share/pnpm")]),
            Ecosystem(name: "Yarn", paths: [p("Library/Caches/Yarn")]),
            Ecosystem(name: "Cargo", paths: [p(".cargo/registry")]),
            Ecosystem(name: "Go", paths: [p("go/pkg/mod"), p("Library/Caches/go-build")]),
            Ecosystem(name: "pip", paths: [p("Library/Caches/pip")]),
            Ecosystem(name: "Gradle", paths: [p(".gradle/caches")]),
            Ecosystem(name: "Docker", paths: [p("Library/Containers/com.docker.docker/Data/vms")]),
        ]
    }

    static func total(_ sizes: [Int64]) -> Int64 { sizes.reduce(0, +) }
}
