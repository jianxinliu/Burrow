//
//  PrivacyTests.swift
//  BurrowTests
//
//  The permission-flood fix (issue #3) hinges on one decision: should
//  Burrow surface the Full Disk Access notice before a scan that walks
//  TCC-protected directories? The probe for whether we *have* access is
//  environment-dependent and not unit-testable, so the decision is split
//  into a pure function that these tests pin down.
//

import XCTest
@testable import Burrow

final class PrivacyTests: XCTestCase {
    // The rule: only nag when access is missing AND the user hasn't
    // already dismissed the notice. Granting access or dismissing both
    // silence it — we never want to flood the user with our own banner
    // any more than with the OS prompts.
    func testOffersAccessOnlyWhenMissingAndNotDismissed() {
        XCTAssertTrue(Privacy.shouldOfferFullDiskAccess(hasAccess: false, dismissed: false))
        XCTAssertFalse(Privacy.shouldOfferFullDiskAccess(hasAccess: true, dismissed: false),
                       "no notice when we already have access")
        XCTAssertFalse(Privacy.shouldOfferFullDiskAccess(hasAccess: false, dismissed: true),
                       "respect a prior dismissal")
        XCTAssertFalse(Privacy.shouldOfferFullDiskAccess(hasAccess: true, dismissed: true))
    }
}
