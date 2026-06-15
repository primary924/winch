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
            "AXMovable" as CFString,
            &movable
        ) == .success, let movableBool = movable as? Bool, !movableBool {
            return nil
        }

        return AXWindow(windowElement)
    }

    func frame(of window: WindowHandle) -> CGRect? {
        guard let window = window as? AXWindow else { return nil }
        guard let origin = readPoint(window.element, attribute: kAXPositionAttribute) else { return nil }
        guard let size = readSize(window.element, attribute: kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    func setPosition(of window: WindowHandle, to point: CGPoint) {
        guard let window = window as? AXWindow else { return }
        setAXPosition(window.element, point)
    }

    func setFrame(of window: WindowHandle, to frame: CGRect) {
        guard let window = window as? AXWindow else { return }
        // Order matters: position → size → position. Setting size first lets macOS
        // clamp the window to fit on screen from its *current* location, landing it
        // smaller than the target; moving to the corner first gives the resize room.
        WindowFrameApplier.apply(
            frame,
            setPosition: { setAXPosition(window.element, $0) },
            setSize: { setAXSize(window.element, $0) }
        )
    }

    // MARK: - private helpers

    private func setAXPosition(_ element: AXUIElement, _ point: CGPoint) {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return }
        _ = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    private func setAXSize(_ element: AXUIElement, _ size: CGSize) {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return }
        _ = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }

    private func readPoint(_ element: AXUIElement, attribute: String) -> CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let v = value,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        let axValue = v as! AXValue
        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func readSize(_ element: AXUIElement, attribute: String) -> CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let v = value,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        let axValue = v as! AXValue
        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else { return nil }
        return size
    }
}
