import XCTest
import CoreGraphics
@testable import WinchDomain

final class HotkeyConfigTests: XCTestCase {
    func testExactMatchSucceeds() {
        let config = HotkeyConfig(modifierFlags: [.maskControl, .maskAlternate])
        XCTAssertTrue(config.matches([.maskControl, .maskAlternate]))
    }

    func testPartialFlagsFail() {
        let config = HotkeyConfig(modifierFlags: [.maskControl, .maskAlternate])
        XCTAssertFalse(config.matches([.maskControl]))
    }

    func testSupersetFails() {
        // Ctrl+Option config must NOT match Ctrl+Option+Shift.
        let config = HotkeyConfig(modifierFlags: [.maskControl, .maskAlternate])
        XCTAssertFalse(config.matches([.maskControl, .maskAlternate, .maskShift]))
    }

    func testCapsLockIgnoredInMatching() {
        // Toggle keys must not affect matching.
        let config = HotkeyConfig(modifierFlags: [.maskControl, .maskAlternate])
        let flagsWithCaps: CGEventFlags = [.maskControl, .maskAlternate, .maskAlphaShift]
        XCTAssertTrue(config.matches(flagsWithCaps))
    }

    func testEmptyConfigNeverMatches() {
        // Defensive: an empty config (no modifiers selected) must not fire.
        let config = HotkeyConfig(modifierFlags: [])
        XCTAssertFalse(config.matches([]))
        XCTAssertFalse(config.matches([.maskControl]))
    }

    func testRawValueRoundTrip() {
        let original = HotkeyConfig(modifierFlags: [.maskControl, .maskAlternate])
        let restored = HotkeyConfig(rawValue: original.rawValue)
        XCTAssertEqual(restored, original)
    }

    func testDefaultIsControlOption() {
        XCTAssertEqual(
            HotkeyConfig.default.modifierFlags,
            [.maskControl, .maskAlternate]
        )
    }
}
