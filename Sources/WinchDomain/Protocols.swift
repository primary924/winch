import CoreGraphics

// Marker protocol for an opaque window reference. The concrete Platform
// implementation wraps an AXUIElement; tests use a fake class.
// Reference semantics keep handles comparable by identity.
public protocol WindowHandle: AnyObject {}

public protocol WindowControlling {
    /// Returns a handle to the currently focused window of the frontmost app,
    /// or nil if no movable window is available (system UI, fullscreen, etc.).
    func frontmostWindow() -> WindowHandle?

    /// Reads the window's current frame (position + size) in screen coordinates
    /// with top-left origin. Returns nil if the handle is invalid.
    func frame(of window: WindowHandle) -> CGRect?

    /// Sets the window's top-left position. Silently no-ops on failure.
    func setPosition(of window: WindowHandle, to point: CGPoint)

    /// Sets the window's full frame (position + size). Used for snap commit and
    /// pre-snap restoration. Silently no-ops on failure.
    func setFrame(of window: WindowHandle, to frame: CGRect)
}

public protocol CursorLocating {
    /// Current cursor position in top-left screen coordinates.
    var location: CGPoint { get }
}

public protocol ScreenInfoProviding {
    /// Returns the visible frame (excludes menu bar and Dock) of the screen
    /// containing the given point, in top-left screen coordinates.
    /// Returns nil if the point is not on any connected screen.
    func visibleFrame(containing point: CGPoint) -> CGRect?
}

public protocol SnapPreviewing {
    /// Shows the snap preview overlay at the given frame (top-left coords).
    func show(at frame: CGRect)

    /// Hides the snap preview overlay.
    func hide()
}
