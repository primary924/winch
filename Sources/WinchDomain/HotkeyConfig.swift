import Foundation
import CoreGraphics

public struct HotkeyConfig: Equatable {
    public let modifierFlags: CGEventFlags

    public init(modifierFlags: CGEventFlags) {
        self.modifierFlags = modifierFlags
    }

    public static let `default` = HotkeyConfig(
        modifierFlags: [.maskControl, .maskAlternate]
    )

    // The subset of CGEventFlags bits we consider when matching.
    // Toggle states (Caps Lock, NumLock) and event-source bits are excluded
    // so they cannot accidentally invalidate a match.
    public static let meaningfulMask: CGEventFlags = [
        .maskCommand,
        .maskAlternate,
        .maskControl,
        .maskShift,
        .maskSecondaryFn,
    ]

    public func matches(_ flags: CGEventFlags) -> Bool {
        guard !modifierFlags.isEmpty else { return false }
        let masked = flags.intersection(Self.meaningfulMask)
        return masked == modifierFlags
    }

    // Round-trips through UserDefaults via raw UInt64.
    public var rawValue: UInt64 { modifierFlags.rawValue }

    public init(rawValue: UInt64) {
        self.modifierFlags = CGEventFlags(rawValue: rawValue)
    }
}
