//
//  MoleCLITests.swift
//  BurrowTests
//
//  parseVersion is the only pure piece of the Mole-engine lifecycle
//  (install/version/update); the rest spawns `mo`. It must pull a semver
//  out of whatever `mo --version` decorates it with.
//

import XCTest
@testable import Burrow

final class MoleCLITests: XCTestCase {
    func testParseVersion_extractsSemverFromDecoratedOutput() {
        XCTAssertEqual(MoleCLI.parseVersion("mole 1.41.0"), "1.41.0")
        XCTAssertEqual(MoleCLI.parseVersion("v1.41.0\n"), "1.41.0")
        XCTAssertEqual(MoleCLI.parseVersion("mole version 2.0.10 (build 7)"), "2.0.10")
    }

    func testParseVersion_nilWhenNoVersion() {
        XCTAssertNil(MoleCLI.parseVersion("no version here"))
        XCTAssertNil(MoleCLI.parseVersion(""))
    }

    func testParseVersion_ignoresLoneNumbers() {
        // A bare integer isn't a version; needs at least major.minor.
        XCTAssertNil(MoleCLI.parseVersion("built for macOS 14"))
    }

    // MARK: - Capture runner (MoleCLI.run)
    //
    // The subprocess boundary is exercised with real tiny system binaries
    // (echo / cat / false / sleep) rather than a mock — the local-substitutable
    // way to test a process runner: actual plumbing, deterministic, fast.

    func testRun_capturesStdoutAndExitZero() throws {
        let r = try MoleCLI.run(args: ["hello world"], executable: "/bin/echo")
        XCTAssertEqual(r.exitCode, 0)
        XCTAssertEqual(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello world")
    }

    func testRun_feedsStdinToChild() throws {
        // `cat` echoes whatever it reads on stdin — proves the stdin feed lands.
        let r = try MoleCLI.run(args: [], executable: "/bin/cat", stdin: "piped input\n")
        XCTAssertEqual(r.exitCode, 0)
        XCTAssertTrue(r.stdout.contains("piped input"))
    }

    func testRun_reportsNonZeroExit() throws {
        let r = try MoleCLI.run(args: [], executable: "/usr/bin/false")
        XCTAssertNotEqual(r.exitCode, 0)
    }

    func testRun_timesOutInsteadOfHanging() throws {
        let start = Date()
        let r = try MoleCLI.run(args: ["5"], executable: "/bin/sleep", timeout: 0.4)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 3.0, "the 5s sleep must be killed by the 0.4s timeout")
        XCTAssertNotEqual(r.exitCode, 0, "a terminated process is non-zero")
    }
}
