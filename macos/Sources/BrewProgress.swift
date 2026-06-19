//
//  BrewProgress.swift
//  Burrow
//
//  Brew-upgrade progress parsing (roadmap H deferral). Pure: a line of
//  `brew upgrade` output → a human progress phrase, or nil for noise — so the
//  Updates flow can show live progress ("Pouring foo…") instead of a blocking
//  spinner. Wiring this into the streaming upgrade run is integration.
//

import Foundation

enum BrewProgress {
    /// Brew prints its step headers as `==> <phrase>`. Those are exactly the
    /// progress beats worth surfacing; everything else (download bars, blank
    /// lines, bottle hashes) is noise.
    static func phrase(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("==> ") else { return nil }
        let phrase = String(t.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        return phrase.isEmpty ? nil : phrase
    }
}
