import Foundation
import CoreGraphics
import WinchDomain

final class SettingsStore {

    private let defaults: UserDefaults

    private enum Key {
        static let hotkeyModifierFlags = "hotkey.modifierFlags"
        static let appPaused = "app.paused"
        static let launchAtLogin = "app.launchAtLogin"
        static let snapEnabled = "snap.enabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hotkeyConfig: HotkeyConfig {
        get {
            if defaults.object(forKey: Key.hotkeyModifierFlags) == nil {
                return .default
            }
            let raw = UInt64(bitPattern: Int64(defaults.integer(forKey: Key.hotkeyModifierFlags)))
            let config = HotkeyConfig(rawValue: raw)
            // Defensive: an empty config saved by an older build → reset to default.
            return config.modifierFlags.isEmpty ? .default : config
        }
        set {
            defaults.set(Int64(bitPattern: newValue.rawValue), forKey: Key.hotkeyModifierFlags)
        }
    }

    var isPaused: Bool {
        get { defaults.bool(forKey: Key.appPaused) }
        set { defaults.set(newValue, forKey: Key.appPaused) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    var isSnapEnabled: Bool {
        get {
            if defaults.object(forKey: Key.snapEnabled) == nil { return true }
            return defaults.bool(forKey: Key.snapEnabled)
        }
        set { defaults.set(newValue, forKey: Key.snapEnabled) }
    }
}
