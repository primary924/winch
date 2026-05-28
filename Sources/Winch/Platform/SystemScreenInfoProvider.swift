import AppKit
import WinchDomain

final class SystemScreenInfoProvider: ScreenInfoProviding {
    func visibleFrame(containing point: CGPoint) -> CGRect? {
        // Find the screen whose frame contains the given point (Quartz/top-left coords).
        // NSScreen uses bottom-left origin; convert point for hit-testing, then convert
        // the visible frame back to top-left origin for callers.
        guard let primary = NSScreen.screens.first else { return nil }
        let primaryHeight = primary.frame.height

        // Convert point from Quartz (top-left) to AppKit (bottom-left) coords.
        let appKitPoint = CGPoint(x: point.x, y: primaryHeight - point.y)

        for screen in NSScreen.screens {
            let f = screen.frame
            if appKitPoint.x >= f.minX && appKitPoint.x <= f.maxX &&
               appKitPoint.y >= f.minY && appKitPoint.y <= f.maxY {
                // Convert the screen's visibleFrame back to Quartz top-left coords.
                let vf = screen.visibleFrame
                let converted = CGRect(
                    x: vf.origin.x,
                    y: primaryHeight - vf.origin.y - vf.height,
                    width: vf.width,
                    height: vf.height
                )
                return converted
            }
        }
        return nil
    }
}
