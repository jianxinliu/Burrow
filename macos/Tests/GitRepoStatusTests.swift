//
//  GitRepoStatusTests.swift
//  BurrowTests
//
//  The `git status --porcelain -b` parser (roadmap C.11), tested through
//  `parse` with real porcelain fixtures.
//

import XCTest
@testable import Burrow

final class GitRepoStatusTests: XCTestCase {
    func testParse_cleanSynced_needsNoAttention() {
        let s = GitRepoStatus.parse("## main...origin/main")
        XCTAssertFalse(s.dirty)
        XCTAssertEqual(s.ahead, 0)
        XCTAssertFalse(s.needsAttention, "clean + synced is safe to purge")
    }

    func testParse_modifiedFile_isDirty() {
        let s = GitRepoStatus.parse("## main...origin/main\n M Sources/App.swift")
        XCTAssertTrue(s.dirty)
        XCTAssertTrue(s.needsAttention)
    }

    func testParse_untrackedFile_isDirty() {
        let s = GitRepoStatus.parse("## main...origin/main\n?? notes.txt")
        XCTAssertTrue(s.dirty, "untracked files are unsaved work too")
    }

    func testParse_aheadOfUpstream_isUnpushed() {
        let s = GitRepoStatus.parse("## main...origin/main [ahead 3]")
        XCTAssertEqual(s.ahead, 3)
        XCTAssertTrue(s.unpushed)
        XCTAssertTrue(s.needsAttention)
    }

    func testParse_aheadAndBehind_countsAheadOnly() {
        let s = GitRepoStatus.parse("## main...origin/main [ahead 2, behind 5]")
        XCTAssertEqual(s.ahead, 2)
        XCTAssertTrue(s.unpushed)
    }

    func testParse_branchWithNoUpstream_isUnpushed() {
        let s = GitRepoStatus.parse("## experiment")
        XCTAssertFalse(s.hasUpstream)
        XCTAssertTrue(s.unpushed, "a branch that was never pushed is unpushed work")
    }

    func testParse_detachedHeadClean_needsNoAttention() {
        let s = GitRepoStatus.parse("## HEAD (no branch)")
        XCTAssertTrue(s.detached)
        XCTAssertFalse(s.needsAttention, "a clean detached checkout isn't a stranded branch")
    }
}
