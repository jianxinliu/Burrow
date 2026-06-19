//
//  SSE.swift
//  Burrow
//
//  Server-Sent Events encoding (roadmap B.6). Pure text framing for the
//  `GET /events` stream so agents can react to threshold alerts, new
//  LaunchAgents, and operation lifecycle instead of polling. The long-lived
//  Network.framework response, the AlertEngine source, and the off-by-default
//  + token + Origin/Host gating are integration; this is just the wire format,
//  which is fiddly enough (multi-line data, keep-alive comments) to deserve
//  its own tested unit.
//

import Foundation

enum SSEFrame {
    /// Encode one event. Multi-line `data` is split so each physical line
    /// gets its own `data:` field, per the SSE spec; the trailing blank line
    /// dispatches the event on the client.
    static func event(_ type: String, data: String, id: Int? = nil) -> String {
        var out = ""
        if let id { out += "id: \(id)\n" }
        out += "event: \(type)\n"
        for line in data.split(separator: "\n", omittingEmptySubsequences: false) {
            out += "data: \(line)\n"
        }
        out += "\n"
        return out
    }

    /// A comment line — used as a keep-alive so proxies don't drop an idle
    /// stream. Clients ignore comments.
    static func comment(_ text: String) -> String { ": \(text)\n\n" }
}
