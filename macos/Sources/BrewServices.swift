//
//  BrewServices.swift
//  Burrow
//
//  Homebrew background services (plan §P3): list what `brew services` manages
//  and start / stop / restart them without the terminal. The parser is pure and
//  unit-tested; the model shells through the shared BrewClient.
//

import SwiftUI

struct BrewService: Identifiable, Equatable {
    let name: String
    let status: String     // started · stopped · none · error · scheduled · …
    let user: String?
    var id: String { name }
    var running: Bool { status == "started" || status == "scheduled" }
}

enum BrewServices {
    /// Pure parser for `brew services list --json` — running first, then by name.
    static func parse(_ json: String) -> [BrewService] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { d -> BrewService? in
            guard let name = d["name"] as? String, let status = d["status"] as? String else { return nil }
            return BrewService(name: name, status: status, user: d["user"] as? String)
        }.sorted {
            if $0.running != $1.running { return $0.running }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

@MainActor
final class BrewServicesModel: ObservableObject {
    @Published var services: [BrewService] = []
    @Published var loading = false
    @Published var brewInstalled = BrewClient.isInstalled
    /// Names with an in-flight start/stop/restart.
    @Published var busy: Set<String> = []
    private var started = false

    func startIfNeeded() {
        guard !started else { return }
        started = true
        reload()
    }

    func reload() {
        guard BrewClient.isInstalled else { brewInstalled = false; return }
        loading = true
        Task {
            let out = await Task.detached(priority: .userInitiated) {
                BrewClient.run(["services", "list", "--json"]).out
            }.value
            services = BrewServices.parse(out)
            loading = false
        }
    }

    func setRunning(_ run: Bool, _ name: String) {
        guard !busy.contains(name) else { return }
        busy.insert(name)
        Task {
            _ = await Task.detached(priority: .userInitiated) {
                BrewClient.run(["services", run ? "start" : "stop", name])
            }.value
            busy.remove(name)
            reload()
        }
    }

    func restart(_ name: String) {
        guard !busy.contains(name) else { return }
        busy.insert(name)
        Task {
            _ = await Task.detached(priority: .userInitiated) {
                BrewClient.run(["services", "restart", name])
            }.value
            busy.remove(name)
            reload()
        }
    }
}
