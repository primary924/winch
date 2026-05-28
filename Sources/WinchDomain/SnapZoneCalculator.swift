import CoreGraphics

public enum SnapZoneCalculator {
    public static let edgeThreshold: CGFloat = 8

    /// Returns the snap zone the cursor is currently in, or nil if outside any zone.
    /// Top zone owns the corners — left/right are only matched when not in top.
    public static func zone(forCursor cursor: CGPoint, in visibleFrame: CGRect) -> SnapZone? {
        if cursor.y < visibleFrame.minY + edgeThreshold { return .top }
        if cursor.x < visibleFrame.minX + edgeThreshold { return .left }
        if cursor.x > visibleFrame.maxX - edgeThreshold { return .right }
        return nil
    }

    /// Returns the window frame to apply when committing the given snap zone.
    public static func target(for zone: SnapZone, in visibleFrame: CGRect) -> CGRect {
        switch zone {
        case .top:
            return visibleFrame
        case .left:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
        case .right:
            return CGRect(
                x: visibleFrame.minX + visibleFrame.width / 2,
                y: visibleFrame.minY,
                width: visibleFrame.width / 2,
                height: visibleFrame.height
            )
        }
    }
}
