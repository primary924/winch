import XCTest
import CoreGraphics
@testable import WinchDomain

final class DragControllerTests: XCTestCase {

    private func makeController(
        config: HotkeyConfig = HotkeyConfig(modifierFlags: [.maskControl, .maskAlternate]),
        windows: FakeWindowController = FakeWindowController(),
        cursor: FakeCursorLocator = FakeCursorLocator(),
        screens: FakeScreenInfoProvider = FakeScreenInfoProvider()
    ) -> (DragController, FakeWindowController, FakeCursorLocator, FakeScreenInfoProvider) {
        let controller = DragController(
            hotkeyConfig: config,
            windowController: windows,
            cursorLocator: cursor,
            screenInfoProvider: screens
        )
        return (controller, windows, cursor, screens)
    }

    // MARK: existing behaviors (carried over)

    func testStartsIdle() {
        let (controller, _, _, _) = makeController()
        XCTAssertTrue(controller.isIdle)
    }

    func testEntersTrackingOnHotkeyMatch() {
        let (controller, windows, cursor, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 200, width: 500, height: 400)
        cursor.location = CGPoint(x: 50, y: 50)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertFalse(controller.isIdle)
    }

    func testStaysIdleWhenNoFrontmostWindow() {
        let (controller, windows, _, _) = makeController()
        windows.stubFrontmostWindow = nil

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertTrue(controller.isIdle)
    }

    func testStaysIdleWhenWindowHasNoFrame() {
        let (controller, windows, _, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        // No stubFrames entry → frame(of:) returns nil

        controller.handleFlagsChanged([.maskControl, .maskAlternate])

        XCTAssertTrue(controller.isIdle)
    }

    func testMouseMovedUpdatesWindowPosition() {
        let (controller, windows, cursor, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 200, width: 500, height: 400)
        cursor.location = CGPoint(x: 50, y: 50)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 80, y: 70)
        controller.handleMouseMoved()

        XCTAssertEqual(windows.setPositionCalls.count, 1)
        XCTAssertEqual(windows.setPositionCalls[0].1, CGPoint(x: 130, y: 220))
    }

    func testMultipleMouseMovesAllRelativeToOriginNotCumulative() {
        // Regression guard: absolute offset from snapshot, not accumulated deltas.
        let (controller, windows, cursor, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 0, y: 0, width: 500, height: 400)
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
        let (controller, windows, _, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 0, y: 0, width: 100, height: 100)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        XCTAssertFalse(controller.isIdle)
        controller.handleFlagsChanged([])
        XCTAssertTrue(controller.isIdle)
    }

    func testMouseMovedIgnoredWhenIdle() {
        let (controller, windows, _, _) = makeController()
        controller.handleMouseMoved()
        XCTAssertEqual(windows.setPositionCalls.count, 0)
    }

    func testPausedDoesNotEnterTracking() {
        let (controller, windows, _, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = .zero
        controller.isPaused = true

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        XCTAssertTrue(controller.isIdle)
    }

    func testPausedDuringDragForcesIdle() {
        let (controller, windows, _, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = .zero

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        XCTAssertFalse(controller.isIdle)

        controller.isPaused = true
        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        XCTAssertTrue(controller.isIdle)
    }

    func testHotkeyConfigCanBeReplacedAtRuntime() {
        let (controller, windows, _, _) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = .zero

        controller.hotkeyConfig = HotkeyConfig(modifierFlags: [.maskCommand])
        controller.handleFlagsChanged([.maskCommand])

        XCTAssertFalse(controller.isIdle)
    }

    // MARK: new snap behaviors

    func testSnapZoneCallbackFiresOnEnteringLeftZone() {
        let (controller, windows, cursor, screens) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 100, width: 400, height: 300)
        screens.stubVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        cursor.location = CGPoint(x: 50, y: 50)

        var fired: [SnapTarget?] = []
        controller.onSnapZoneChanged = { fired.append($0) }

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 3, y: 450)
        controller.handleMouseMoved()

        XCTAssertEqual(fired.count, 1)
        XCTAssertEqual(fired.first??.zone, .left)
        XCTAssertEqual(fired.first??.frame, CGRect(x: 0, y: 0, width: 720, height: 900))
    }

    func testSnapZoneCallbackFiresWithNilOnLeavingZone() {
        let (controller, windows, cursor, screens) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 100, width: 400, height: 300)
        screens.stubVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        cursor.location = CGPoint(x: 50, y: 50)

        var fired: [SnapTarget?] = []
        controller.onSnapZoneChanged = { fired.append($0) }

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 3, y: 450)
        controller.handleMouseMoved()
        cursor.location = CGPoint(x: 720, y: 450)
        controller.handleMouseMoved()

        XCTAssertEqual(fired.count, 2)
        XCTAssertEqual(fired[0]?.zone, .left)
        XCTAssertNil(fired[1])
    }

    func testSnapDoesNotFireWhenIsSnapEnabledIsFalse() {
        let (controller, windows, cursor, screens) = makeController()
        controller.isSnapEnabled = false
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 100, width: 400, height: 300)
        screens.stubVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        cursor.location = CGPoint(x: 50, y: 50)

        var fired: [SnapTarget?] = []
        controller.onSnapZoneChanged = { fired.append($0) }

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 3, y: 450)
        controller.handleMouseMoved()

        XCTAssertEqual(fired.count, 0)
    }

    func testHotkeyReleaseCommitsSnapWhenInZone() {
        let (controller, windows, cursor, screens) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 100, width: 400, height: 300)
        screens.stubVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        cursor.location = CGPoint(x: 50, y: 50)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 3, y: 450)
        controller.handleMouseMoved()
        controller.handleFlagsChanged([])

        XCTAssertEqual(windows.setFrameCalls.count, 1)
        XCTAssertEqual(windows.setFrameCalls[0].1, CGRect(x: 0, y: 0, width: 720, height: 900))
    }

    func testHotkeyReleaseDoesNothingWhenNotInZone() {
        let (controller, windows, cursor, screens) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 100, width: 400, height: 300)
        screens.stubVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        cursor.location = CGPoint(x: 50, y: 50)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 720, y: 450)
        controller.handleMouseMoved()
        controller.handleFlagsChanged([])

        XCTAssertEqual(windows.setFrameCalls.count, 0)
    }

    func testSnappedWindowRestoresOnReDrag() {
        let (controller, windows, cursor, screens) = makeController()
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        let originalFrame = CGRect(x: 100, y: 100, width: 400, height: 300)
        windows.stubFrames[ObjectIdentifier(window)] = originalFrame
        screens.stubVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        cursor.location = CGPoint(x: 200, y: 200)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 3, y: 450)
        controller.handleMouseMoved()
        controller.handleFlagsChanged([])

        XCTAssertEqual(windows.setFrameCalls.count, 1)
        XCTAssertEqual(windows.setFrameCalls[0].1, CGRect(x: 0, y: 0, width: 720, height: 900))

        cursor.location = CGPoint(x: 200, y: 50)
        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        cursor.location = CGPoint(x: 202, y: 51)
        controller.handleMouseMoved()
        XCTAssertEqual(windows.setFrameCalls.count, 1, "restore should not trigger below threshold")
        cursor.location = CGPoint(x: 220, y: 80)
        controller.handleMouseMoved()
        XCTAssertEqual(windows.setFrameCalls.count, 2, "restore should trigger above threshold")
        let restored = windows.setFrameCalls[1].1
        XCTAssertEqual(restored.size, originalFrame.size)
        XCTAssertEqual(restored.origin.x, 220 - 200, accuracy: 0.001)
        XCTAssertEqual(restored.origin.y, 80 - 14, accuracy: 0.001)
    }

    func testIsSnapEnabledFalseSkipsCommit() {
        let (controller, windows, cursor, screens) = makeController()
        controller.isSnapEnabled = false
        let window = FakeWindowHandle("w1")
        windows.stubFrontmostWindow = window
        windows.stubFrames[ObjectIdentifier(window)] = CGRect(x: 100, y: 100, width: 400, height: 300)
        screens.stubVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        cursor.location = CGPoint(x: 3, y: 450)

        controller.handleFlagsChanged([.maskControl, .maskAlternate])
        controller.handleMouseMoved()
        controller.handleFlagsChanged([])

        XCTAssertEqual(windows.setFrameCalls.count, 0)
    }
}
