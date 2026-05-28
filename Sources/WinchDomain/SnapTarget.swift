import CoreGraphics

public enum SnapZone: Equatable {
    case left
    case right
    case top
}

public struct SnapTarget: Equatable {
    public let zone: SnapZone
    public let frame: CGRect

    public init(zone: SnapZone, frame: CGRect) {
        self.zone = zone
        self.frame = frame
    }
}
