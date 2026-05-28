import Foundation
import CoreGraphics
@testable import WinchDomain

final class FakeWindowHandle: WindowHandle {
    let id: String
    init(_ id: String) { self.id = id }
}

final class FakeWindowController: WindowControlling {
    var stubFrontmostWindow: WindowHandle?
    var stubFrames: [ObjectIdentifier: CGRect] = [:]
    var setPositionCalls: [(WindowHandle, CGPoint)] = []
    var setFrameCalls: [(WindowHandle, CGRect)] = []

    func frontmostWindow() -> WindowHandle? {
        stubFrontmostWindow
    }

    func frame(of window: WindowHandle) -> CGRect? {
        stubFrames[ObjectIdentifier(window)]
    }

    func setPosition(of window: WindowHandle, to point: CGPoint) {
        setPositionCalls.append((window, point))
        // Mirror into stubFrames so subsequent frame(of:) reflects the move.
        if let existing = stubFrames[ObjectIdentifier(window)] {
            stubFrames[ObjectIdentifier(window)] = CGRect(origin: point, size: existing.size)
        }
    }

    func setFrame(of window: WindowHandle, to frame: CGRect) {
        setFrameCalls.append((window, frame))
        stubFrames[ObjectIdentifier(window)] = frame
    }
}

final class FakeCursorLocator: CursorLocating {
    var location: CGPoint = .zero
}

final class FakeScreenInfoProvider: ScreenInfoProviding {
    var stubVisibleFrame: CGRect? = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func visibleFrame(containing point: CGPoint) -> CGRect? {
        stubVisibleFrame
    }
}
