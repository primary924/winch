import Foundation
import CoreGraphics

public final class DragController {
    private enum State {
        case idle
        case tracking(window: WindowHandle, originCursor: CGPoint, originWindow: CGPoint)
    }

    private var state: State = .idle
    public var hotkeyConfig: HotkeyConfig
    public var isPaused: Bool = false

    private let windowController: WindowControlling
    private let cursorLocator: CursorLocating

    public init(
        hotkeyConfig: HotkeyConfig,
        windowController: WindowControlling,
        cursorLocator: CursorLocating
    ) {
        self.hotkeyConfig = hotkeyConfig
        self.windowController = windowController
        self.cursorLocator = cursorLocator
    }

    public var isIdle: Bool {
        if case .idle = state { return true }
        return false
    }

    public func handleFlagsChanged(_ flags: CGEventFlags) {
        if isPaused {
            state = .idle
            return
        }

        if hotkeyConfig.matches(flags) {
            if case .idle = state {
                tryEnterTracking()
            }
            // Already tracking — keep the existing snapshot.
        } else {
            state = .idle
        }
    }

    public func handleMouseMoved() {
        if isPaused { return }
        guard case let .tracking(window, originCursor, originWindow) = state else {
            return
        }
        let current = cursorLocator.location
        let newPos = CGPoint(
            x: originWindow.x + (current.x - originCursor.x),
            y: originWindow.y + (current.y - originCursor.y)
        )
        windowController.setPosition(of: window, to: newPos)
    }

    private func tryEnterTracking() {
        guard let window = windowController.frontmostWindow() else { return }
        guard let originWindow = windowController.position(of: window) else { return }
        state = .tracking(
            window: window,
            originCursor: cursorLocator.location,
            originWindow: originWindow
        )
    }
}
