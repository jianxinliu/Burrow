//
//  NetUsageTests.swift
//  BurrowTests
//
//  The pure nettop frame parser behind per-process bandwidth (plan §2.1).
//  Sampling + reverse-DNS are impure I/O and aren't covered here.
//

import XCTest
@testable import Burrow

final class NetUsageTests: XCTestCase {
    // Two frames like real `nettop -P -x -d -L 2`: frame 1 is cumulative
    // (big), frame 2 is the ~1s delta (the rate). We must take the last frame.
    private let sample = """
    ,bytes_in,bytes_out,
    mDNSResponder.626,84012163,56620842,
    io.tailscale.ip.1550,20406,31037875,
    launchd.1,0,0,
    ,bytes_in,bytes_out,
    mDNSResponder.626,627,426,
    io.tailscale.ip.1550,0,5,
    Spotify.1524,284,0,
    """

    func testParse_usesLastFrame_notCumulative() {
        let r = NetUsage.parse(sample)
        XCTAssertEqual(r[626], NetUsage.Rates(down: 627, up: 426), "last frame's delta, not the 84MB cumulative")
        XCTAssertEqual(r[1524], NetUsage.Rates(down: 284, up: 0))
    }

    func testParse_pidIsTrailingDotComponent_ofDottedNames() {
        let r = NetUsage.parse(sample)
        XCTAssertEqual(r[1550], NetUsage.Rates(down: 0, up: 5), "io.tailscale.ip.1550 → pid 1550")
    }

    func testParse_emptyOrGarbage() {
        XCTAssertTrue(NetUsage.parse("").isEmpty)
        XCTAssertTrue(NetUsage.parse("garbage\nno commas here").isEmpty)
        XCTAssertTrue(NetUsage.parse(",bytes_in,bytes_out,\n").isEmpty)
    }
}
