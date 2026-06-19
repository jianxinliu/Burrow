//
//  GitSweep.swift
//  Burrow
//
//  Purge-safety git runner (roadmap C.11): find the repo containing a purge
//  candidate and ask `git status` whether deleting it would lose work. The
//  parse + verdict live in GitRepoStatus (tested); this is the filesystem
//  walk-up (testable) and the bounded subprocess. Badging the purge checklist
//  is the GUI integration.
//

import Foundation

enum GitSweep {
    /// Walk up from `path` to the nearest directory containing a `.git`.
    static func repoRoot(for path: String) -> String? {
        var url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        for _ in 0..<64 {
            if fm.fileExists(atPath: url.appendingPathComponent(".git").path) { return url.path }
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path { break }
            url = parent
        }
        return nil
    }

    /// `git -C <repo> status --porcelain=v1 -b`, bounded by `timeout`, parsed
    /// into a verdict. nil when git is unavailable, times out, or errors.
    static func status(repo: String, timeout: TimeInterval = 3) -> GitRepoStatus.Status? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repo, "status", "--porcelain=v1", "-b"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }

        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async { p.waitUntilExit(); sem.signal() }
        if sem.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            return nil
        }
        guard p.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return GitRepoStatus.parse(String(decoding: data, as: UTF8.self))
    }
}
