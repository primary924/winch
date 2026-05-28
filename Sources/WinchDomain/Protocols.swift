import CoreGraphics

// Marker protocol for an opaque window reference. The concrete Platform
// implementation wraps an AXUIElement; tests use a fake class.
// Reference semantics keep handles comparable by identity.
public protocol WindowHandle: AnyObject {}

public protocol WindowControlling {
    /// Returns a handle to the currently focused window of the frontmost app,
    /// or nil if no movable window is available (system UI, fullscreen, etc.).
    func frontmostWindow() -> WindowHandle?

    /// Reads the window's current top-left position in screen coordinates.
    /// Returns nil if the handle is invalid (window closed).
    func position(of window: WindowHandle) -> CGPoint?

    /// Sets the window's top-left position. Silently no-ops on failure
    /// (window closed mid-drag, etc.).
    func setPosition(of window: WindowHandle, to point: CGPoint)
}

public protocol CursorLocating {
    /// Current cursor position in screen coordinates.
    var location: CGPoint { get }
}
