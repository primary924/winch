import AppKit
import ApplicationServices
import WinchDomain

/// Wraps an AXUIElement reference as an opaque WindowHandle.
final class AXWindow: WindowHandle {
    let element: AXUIElement
    init(_ element: AXUIElement) {
        self.element = element
    }
}

final class WindowController: WindowControlling {

    func frontmostWindow() -> WindowHandle? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focused
        )
        guard result == .success, let focused = focused else { return nil }
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let windowElement = focused as! AXUIElement

        // Reject windows we cannot move (system UI, fullscreen panels).
        var movable: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            windowElement,
            "AXMovable" as CFString,  // kAXMovableAttribute (not in headers on all SDK versions)
            &movable
        ) == .success, let movableBool = movable as? Bool, !movableBool {
            return nil
        }

        return AXWindow(windowElement)
    }

    func position(of window: WindowHandle) -> CGPoint? {
        guard let window = window as? AXWindow else { return nil }
        var positionValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            window.element,
            kAXPositionAttribute as CFString,
            &positionValue
        )
        guard result == .success, let value = positionValue else { return nil }
        guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    func setPosition(of window: WindowHandle, to point: CGPoint) {
        guard let window = window as? AXWindow else { return }
        var mutablePoint = point
        guard let value = AXValueCreate(.cgPoint, &mutablePoint) else { return }
        // Silently ignore failure: window may have closed mid-drag.
        _ = AXUIElementSetAttributeValue(
            window.element,
            kAXPositionAttribute as CFString,
            value
        )
    }
}
