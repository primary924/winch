import AppKit
import WinchDomain

final class SystemCursorLocator: CursorLocating {
    var location: CGPoint {
        // NSEvent.mouseLocation is in bottom-left origin (AppKit screen coords).
        // AXUIElement positions are in top-left origin (Quartz screen coords).
        // Convert by flipping against the primary display height.
        let mouse = NSEvent.mouseLocation
        guard let primary = NSScreen.screens.first else { return mouse }
        return CGPoint(x: mouse.x, y: primary.frame.height - mouse.y)
    }
}
