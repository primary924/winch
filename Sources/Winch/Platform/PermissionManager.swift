import AppKit
import ApplicationServices
import Foundation

final class PermissionManager {

    /// Called whenever the Accessibility trust status changes.
    var onStatusChange: ((Bool) -> Void)?

    private var pollTimer: Timer?
    private var lastKnownTrusted: Bool

    init() {
        self.lastKnownTrusted = AXIsProcessTrusted()
    }

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user via the system "App wants to control your computer" dialog.
    func requestWithPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Opens System Settings → Privacy & Security → Accessibility.
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Starts polling every 1 second to detect permission grant or revocation.
    /// Calls `onStatusChange` on every transition.
    func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = AXIsProcessTrusted()
            if current != self.lastKnownTrusted {
                self.lastKnownTrusted = current
                self.onStatusChange?(current)
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
