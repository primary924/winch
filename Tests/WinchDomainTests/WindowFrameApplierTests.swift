import XCTest
import CoreGraphics
@testable import WinchDomain

final class WindowFrameApplierTests: XCTestCase {

    /// Emulates how macOS applies AX writes: a size write is clamped so the window
    /// stays within `screen` from its *current* origin. This is the behavior that
    /// made full-screen snaps land smaller than the guide.
    private final class ClampingWindow {
        let screen: CGRect
        private(set) var frame: CGRect
        private(set) var calls: [String] = []

        init(screen: CGRect, frame: CGRect) {
            self.screen = screen
            self.frame = frame
        }

        func setPosition(_ p: CGPoint) {
            calls.append("position")
            frame.origin = p
        }

        func setSize(_ s: CGSize) {
            calls.append("size")
            let maxWidth = screen.maxX - frame.origin.x
            let maxHeight = screen.maxY - frame.origin.y
            frame.size = CGSize(width: min(s.width, maxWidth), height: min(s.height, maxHeight))
        }
    }

    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testFullScreenSnapReachesTargetWhenWindowStartsAwayFromCorner() {
        let target = screen
        let window = ClampingWindow(screen: screen, frame: CGRect(x: 600, y: 300, width: 800, height: 500))

        WindowFrameApplier.apply(
            target,
            setPosition: { window.setPosition($0) },
            setSize: { window.setSize($0) }
        )

        // Size-before-position would clamp the size to (840, 600); position-first
        // ordering must reach the full target in a single pass.
        XCTAssertEqual(window.frame, target)
    }

    func testAppliesPositionThenSizeThenPosition() {
        let window = ClampingWindow(screen: screen, frame: CGRect(x: 600, y: 300, width: 800, height: 500))

        WindowFrameApplier.apply(
            screen,
            setPosition: { window.setPosition($0) },
            setSize: { window.setSize($0) }
        )

        XCTAssertEqual(window.calls, ["position", "size", "position"])
    }

    func testRightHalfSnapReachesTarget() {
        let target = CGRect(x: 720, y: 0, width: 720, height: 900)
        let window = ClampingWindow(screen: screen, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))

        WindowFrameApplier.apply(
            target,
            setPosition: { window.setPosition($0) },
            setSize: { window.setSize($0) }
        )

        XCTAssertEqual(window.frame, target)
    }
}
