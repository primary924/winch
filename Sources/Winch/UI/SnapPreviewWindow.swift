import AppKit
import WinchDomain

final class SnapPreviewWindow: SnapPreviewing {

    private let window: NSWindow
    private let contentView: SnapPreviewView

    init() {
        let initialRect = NSRect.zero
        window = NSWindow(
            contentRect: initialRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.hasShadow = false
        contentView = SnapPreviewView()
        window.contentView = contentView
    }

    func show(at frame: CGRect) {
        let appKitFrame = SnapPreviewWindow.convertToAppKit(frame)
        window.setFrame(appKitFrame, display: true)
        window.orderFront(nil)
    }

    func hide() {
        window.orderOut(nil)
    }

    /// Converts a top-left-origin frame (Quartz / AXUIElement coords) to AppKit's
    /// bottom-left-origin coordinate space using the primary screen's height.
    private static func convertToAppKit(_ topLeftFrame: CGRect) -> NSRect {
        guard let primary = NSScreen.screens.first else { return topLeftFrame }
        let h = primary.frame.height
        return NSRect(
            x: topLeftFrame.origin.x,
            y: h - topLeftFrame.origin.y - topLeftFrame.height,
            width: topLeftFrame.width,
            height: topLeftFrame.height
        )
    }
}

final class SnapPreviewView: NSView {
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: inset, xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
        path.lineWidth = 2
        path.stroke()
    }
}
