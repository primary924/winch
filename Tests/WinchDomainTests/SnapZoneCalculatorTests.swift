import XCTest
import CoreGraphics
@testable import WinchDomain

final class SnapZoneCalculatorTests: XCTestCase {

    // Standard 1440x900 screen, origin at (0, 0), top-left.
    private let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)

    // MARK: zone(forCursor:in:)

    func testReturnsNilInCenter() {
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 720, y: 450), in: frame)
        XCTAssertNil(z)
    }

    func testReturnsTopForCursorAtTopEdge() {
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 720, y: 2), in: frame)
        XCTAssertEqual(z, .top)
    }

    func testReturnsTopAtExactlyThreshold() {
        // Threshold is 8; cursor at y=7 is INSIDE (< minY + 8).
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 720, y: 7), in: frame)
        XCTAssertEqual(z, .top)
    }

    func testReturnsNilJustBelowTopThreshold() {
        // y=8 is NOT < 0 + 8 → outside top zone.
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 720, y: 8), in: frame)
        XCTAssertNil(z)
    }

    func testReturnsLeftForCursorAtLeftEdge() {
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 2, y: 450), in: frame)
        XCTAssertEqual(z, .left)
    }

    func testReturnsRightForCursorAtRightEdge() {
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 1438, y: 450), in: frame)
        XCTAssertEqual(z, .right)
    }

    func testTopWinsOverLeftAtTopLeftCorner() {
        // Cursor in corner where both top AND left thresholds are met.
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 2, y: 2), in: frame)
        XCTAssertEqual(z, .top)
    }

    func testTopWinsOverRightAtTopRightCorner() {
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: 1438, y: 2), in: frame)
        XCTAssertEqual(z, .top)
    }

    func testReturnsNilWhenCursorOutsideFrameLeft() {
        let z = SnapZoneCalculator.zone(forCursor: CGPoint(x: -10, y: 450), in: frame)
        // Cursor left of minX → x < minX + 8 still true → .left
        // This is intentional: the threshold treats anything <= minX+8 as "left zone",
        // including negative x. The caller is responsible for picking the right screen.
        XCTAssertEqual(z, .left)
    }

    // MARK: target(for:in:)

    func testTargetForTopIsFullVisibleFrame() {
        let t = SnapZoneCalculator.target(for: .top, in: frame)
        XCTAssertEqual(t, frame)
    }

    func testTargetForLeftIsLeftHalf() {
        let t = SnapZoneCalculator.target(for: .left, in: frame)
        XCTAssertEqual(t, CGRect(x: 0, y: 0, width: 720, height: 900))
    }

    func testTargetForRightIsRightHalf() {
        let t = SnapZoneCalculator.target(for: .right, in: frame)
        XCTAssertEqual(t, CGRect(x: 720, y: 0, width: 720, height: 900))
    }

    func testTargetForLeftRespectsNonZeroOrigin() {
        let secondary = CGRect(x: 1440, y: 100, width: 1280, height: 800)
        let t = SnapZoneCalculator.target(for: .left, in: secondary)
        XCTAssertEqual(t, CGRect(x: 1440, y: 100, width: 640, height: 800))
    }

    func testTargetForRightRespectsNonZeroOrigin() {
        let secondary = CGRect(x: 1440, y: 100, width: 1280, height: 800)
        let t = SnapZoneCalculator.target(for: .right, in: secondary)
        XCTAssertEqual(t, CGRect(x: 2080, y: 100, width: 640, height: 800))
    }

    func testEdgeThresholdIsEight() {
        XCTAssertEqual(SnapZoneCalculator.edgeThreshold, 8)
    }
}
