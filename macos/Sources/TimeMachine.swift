//
//  TimeMachine.swift
//  Burrow
//
//  Backup awareness (roadmap D.14). Pure parsing of `tmutil` output so the
//  Clean/Purge confirm sheets can show "Last backup: 26 days ago" and the
//  Analyze sidebar can note purgeable local snapshots. Running tmutil and
//  rendering the pre-flight line are integration; the SMART/disk-health half
//  of D.14 is native IOKit and lands separately.
//

import Foundation

enum TimeMachine {
    // Time Machine stamps every backup/snapshot with a yyyy-MM-dd-HHmmss token.
    private static let tokenRE = try! NSRegularExpression(pattern: "\\d{4}-\\d{2}-\\d{2}-\\d{6}")

    private static func tokens(in s: String) -> [String] {
        let ns = s as NSString
        return tokenRE.matches(in: s, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range) }
    }

    /// The newest date token in `tmutil latestbackup` output, or nil when
    /// there's no backup (empty output / no match).
    static func latestBackupToken(_ output: String) -> String? { tokens(in: output).last }

    /// Date tokens from `tmutil listlocalsnapshots /` — one per local APFS
    /// snapshot (the "where did my space go" purgeable answer).
    static func localSnapshotTokens(_ output: String) -> [String] {
        output.split(separator: "\n")
            .filter { $0.contains("com.apple.TimeMachine") }
            .flatMap { tokens(in: String($0)) }
    }

    /// Parse a backup token to a UTC Date, or nil if malformed.
    static func date(fromToken token: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: token)
    }
}
