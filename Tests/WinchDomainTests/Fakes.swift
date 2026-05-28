import Foundation
import CoreGraphics
@testable import WinchDomain

final class FakeWindowHandle: WindowHandle {
    let id: String
    init(_ id: String) { self.id = id }
}

final class FakeWindowController: WindowControlling {
    var stubFrontmostWindow: WindowHandle?
    var stubPositions: [ObjectIdentifier: CGPoint] = [:]
    var setPositionCalls: [(WindowHandle, CGPoint)] = []

    func frontmostWindow() -> WindowHandle? {
        stubFrontmostWindow
    }

    func position(of window: WindowHandle) -> CGPoint? {
        stubPositions[ObjectIdentifier(window)]
    }

    func setPosition(of window: WindowHandle, to point: CGPoint) {
        setPositionCalls.append((window, point))
    }
}

final class FakeCursorLocator: CursorLocating {
    var location: CGPoint = .zero
}
