//
//  AgentAudit.swift
//  Burrow
//
//  Agent-action audit records (roadmap B.5): the trust feature that makes
//  "let agents act" adoptable — every MCP tool dispatch leaves a row humans
//  can read. This is the record shape + its stable JSON encoding (one DB row
//  under `prefix`). Writing rows from the MCP process through a serialized
//  writer, and the Activity-view pane, are integration.
//
//  Args are NOT redacted — they're local, and the whole point is to show
//  exactly what an agent asked for.
//

import Foundation

enum AgentAudit {
    static let prefix = "burrow.agent_audit"

    struct Entry: Codable, Equatable {
        var tool: String
        var client: String
        var dryRun: Bool
        var durationMs: Int
        var ok: Bool
        var summary: String
        /// The tool's arguments, pre-serialized to a JSON string by the caller.
        var argsJSON: String
    }

    /// Canonical, key-sorted JSON for one row — deterministic so tests and
    /// the GUI read the same bytes the MCP process wrote.
    static func encode(_ e: Entry) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        guard let d = try? enc.encode(e), let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    static func decode(_ json: String) -> Entry? {
        try? JSONDecoder().decode(Entry.self, from: Data(json.utf8))
    }
}
