import SwiftUI
import Combine
import CoreGraphics
import WinchDomain

struct PreferencesView: View {

    @ObservedObject var model: PreferencesModel

    var body: some View {
        Form {
            Section("Trigger") {
                Toggle("⌘ Command", isOn: $model.command)
                Toggle("⌥ Option",  isOn: $model.option)
                Toggle("⌃ Control", isOn: $model.control)
                Toggle("⇧ Shift",   isOn: $model.shift)
                Toggle("fn Function", isOn: $model.fn)
                if model.isEmpty {
                    Text("At least one modifier is required.")
                        .foregroundColor(.red)
                        .font(.caption)
                } else {
                    Text("Hold \(model.previewSymbols) and move the cursor to drag the focused window.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Startup") {
                Toggle("Launch Winch at login", isOn: $model.launchAtLogin)
            }

            if !model.isAccessibilityTrusted {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Accessibility permission is required for Winch to move windows.")
                            .font(.caption)
                        Spacer()
                        Button("Open System Settings") { model.openSystemSettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
    }
}

@MainActor
final class PreferencesModel: ObservableObject {

    @Published var command: Bool { didSet { publishHotkey() } }
    @Published var option: Bool  { didSet { publishHotkey() } }
    @Published var control: Bool { didSet { publishHotkey() } }
    @Published var shift: Bool   { didSet { publishHotkey() } }
    @Published var fn: Bool      { didSet { publishHotkey() } }
    @Published var launchAtLogin: Bool {
        didSet {
            guard oldValue != launchAtLogin else { return }
            onLaunchAtLoginChange?(launchAtLogin)
        }
    }
    @Published var isAccessibilityTrusted: Bool

    var onHotkeyChange: ((HotkeyConfig) -> Void)?
    var onLaunchAtLoginChange: ((Bool) -> Void)?
    var onOpenSystemSettings: (() -> Void)?

    init(
        initial: HotkeyConfig,
        launchAtLogin: Bool,
        isAccessibilityTrusted: Bool
    ) {
        self.command = initial.modifierFlags.contains(.maskCommand)
        self.option  = initial.modifierFlags.contains(.maskAlternate)
        self.control = initial.modifierFlags.contains(.maskControl)
        self.shift   = initial.modifierFlags.contains(.maskShift)
        self.fn      = initial.modifierFlags.contains(.maskSecondaryFn)
        self.launchAtLogin = launchAtLogin
        self.isAccessibilityTrusted = isAccessibilityTrusted
    }

    var isEmpty: Bool {
        currentFlags.isEmpty
    }

    var previewSymbols: String {
        var s = ""
        if control { s += "⌃" }
        if option  { s += "⌥" }
        if shift   { s += "⇧" }
        if command { s += "⌘" }
        if fn      { s += "fn" }
        return s.isEmpty ? "—" : s
    }

    private var currentFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if option  { flags.insert(.maskAlternate) }
        if control { flags.insert(.maskControl) }
        if shift   { flags.insert(.maskShift) }
        if fn      { flags.insert(.maskSecondaryFn) }
        return flags
    }

    private func publishHotkey() {
        guard !currentFlags.isEmpty else { return }
        onHotkeyChange?(HotkeyConfig(modifierFlags: currentFlags))
    }

    func openSystemSettings() {
        onOpenSystemSettings?()
    }
}
