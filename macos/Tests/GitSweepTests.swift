//
//  GitSweepTests.swift
//  BurrowTests
//
//  Repo-root walk-up (roadmap C.11). The git subprocess needs a real repo, so
//  it's compile-verified, not unit-tested here.
//

import XCTest
@testable import Burrow

final class GitSweepTests: XCTestCase {
    func testRepoRoot_findsContainingDotGit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("gs-\(UUID().uuidString)")
        let deep = root.appendingPathComponent("a/b/c")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(GitSweep.repoRoot(for: deep.path), root.path)
    }

    func testRepoRoot_noRepoBelowTemp_isNil() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nogit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(GitSweep.repoRoot(for: dir.path))
    }
}
