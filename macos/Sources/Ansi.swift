//
//  Ansi.swift
//  Burrow
//
//  The one ANSI/CSI escape-stripper. Mole's TUI and streamed commands wrap
//  output in colour and cursor-movement codes; everything that parses or
//  displays that output cleans it through here. (Previously three near-identical
//  copies lived in the TUI parser, the stream runner, and the MCP server.)
//

import Foundation

enum Ansi {
    /// Remove CSI escape sequences (`ESC [ … <final>`) — colours, cursor moves,
    /// screen clears — leaving the printable text. Character-scanning rather than
    /// regex so it's allocation-light on the hot streaming path.
    static func strip(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        var out = String(); out.reserveCapacity(s.count)
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\u{1B}", s.index(after: i) < s.endIndex, s[s.index(after: i)] == "[" {
                var j = s.index(i, offsetBy: 2)
                while j < s.endIndex {
                    if let a = s[j].asciiValue, a >= 0x40, a <= 0x7E { j = s.index(after: j); break }
                    j = s.index(after: j)
                }
                i = j; continue
            }
            out.append(s[i]); i = s.index(after: i)
        }
        return out
    }
}
