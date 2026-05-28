import XCTest
import CoreGraphics
@testable import WinchDomain

final class DragControllerTests: XCTestCase {

    private func makeController(
        config: HotkeyConfig = HotkeyConfig(modifierFlags: [.maskControl, .maskAlternate]),
        windows: FakeWindowController = FakeWindowController(),
        cursor: FakeCursorLocator = FakeCursorLocator()
    ) -> (DragController, FakeWindowController, FakeCursorLocator) {
        let controller = DragController(
            hotkeyConfig: config,
            windowController: windows,
            cursorLocator: cursor
        )
        return (controller, windows, cursor)
    }

    func testStartsIdle() {
        let (controller, _, _) = makeController()
        XCTAssertTrue(controller.isIdle)
    }

    func testEntersTrackingOnHotkeyMatch() {
        let (controller, windows, cursor) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubPositions[ObjectIdentifier(window)] = CGPoint(x: 100, y: 200)
        cursor.location = CGPoint(x: 50, y: 50)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertFalse(controller.isIdle)
    }

    func testStaysIdleWhenNoFrontmostWindow() {
        let (controller, windows, _) = makeController()
        windows.stubFrontmostWindow = nil

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertTrue(controller.isIdle)
    }

    func testStaysIdleWhenWindowHasNoPosition() {
        let (controller, windows, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        // No stubPositions entry → position(of:) returns nil

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertTrue(controller.isIdle)
    }

    func testMouseMovedUpdatesWindowPosition() {
        let (controller, windows, cursor) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubPositions[ObjectIdentifier(window)] = CGPoint(x: 100, y: 200)
        cursor.location = CGPoint(x: 50, y: 50)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 80, y: 70)
        controller.handleMouseMoved()

        XCTAssertEqual(windows.setPositionCalls.count, 1)
        // origin window (100, 200) + delta (30, 20) = (130, 220)
        XCTAssertEqual(windows.setPositionCalls[0].1, CGPoint(x: 130, y: 220))
    }

    func testMultipleMouseMovesAllRelativeToOriginNotCumulative() {
        // Regression guard: ensure we use absolute offset from snapshot,
        // not accumulated deltas.
        let (controller, windows, cursor) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubPositions[ObjectIdentifier(window)] = CGPoint(x: 0, y: 0)
        cursor.location = CGPoint(x: 0, y: 0)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        cursor.location = CGPoint(x: 10, y: 10)
        controller.handleMouseMoved()
        cursor.location = CGPoint(x: 20, y: 20)
        controller.handleMouseMoved()
        cursor.location = CGPoint(x: 30, y: 30)
        controller.handleMouseMoved()

        XCTAssertEqual(windows.setPositionCalls.map { $0.1 }, [
            CGPoint(x: 10, y: 10),
            CGPoint(x: 20, y: 20),
            CGPoint(x: 30, y: 30),
        ])
    }

    func testTransitionsToIdleOnHotkeyRelease() {
        let (controller, windows, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubPositions[ObjectIdentifier(window)] = .zero

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        XCTAssertFalse(controller.isIdle)

        controller.handleFlagsChanged([])
        XCTAssertTrue(controller.isIdle)
    }

    func testMouseMovedIgnoredWhenIdle() {
        let (controller, windows, _) = makeController()
        controller.handleMouseMoved()
        XCTAssertEqual(windows.setPositionCalls.count, 0)
    }

    func testPausedDoesNotEnterTracking() {
        let (controller, windows, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubPositions[ObjectIdentifier(window)] = .zero
        controller.isPaused = true

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertTrue(controller.isIdle)
    }

    func testPausedDuringDragForcesIdle() {
        let (controller, windows, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubPositions[ObjectIdentifier(window)] = .zero

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        XCTAssertFalse(controller.isIdle)

        controller.isPaused = true
        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertTrue(controller.isIdle)
    }

    func testHotkeyConfigCanBeReplacedAtRuntime() {
        let (controller, windows, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubPositions[ObjectIdentifier(window)] = .zero

        controller.hotkeyConfig = HotkeyConfig(modifierFlags: [.maskCommand])
        controller.handleFlagsChanged([.maskCommand])

        XCTAssertFalse(controller.isIdle)
    }
}
