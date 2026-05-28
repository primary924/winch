import AppKit

final class MenuBarController: NSObject {

    enum Status {
        case active
        case paused
        case permissionMissing
    }

    var onTogglePause: (() -> Void)?
    var onOpenPreferences: (() -> Void)?
    var onQuit: (() -> Void)?

    private let statusItem: NSStatusItem
    private(set) var status: Status = .active

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        statusItem.button?.title = "W"
        rebuildMenu()
        updateAppearance()
    }

    func setStatus(_ status: Status) {
        self.status = status
        rebuildMenu()
        updateAppearance()
    }

    private func updateAppearance() {
        guard let button = statusItem.button else { return }
        switch status {
        case .active:            button.title = "●W"
        case .paused:            button.title = "⏸W"
        case .permissionMissing: button.title = "⚠W"
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        switch status {
        case .active:
            menu.addItem(disabled("Winch is active"))
        case .paused:
            menu.addItem(disabled("Winch is paused"))
        case .permissionMissing:
            menu.addItem(disabled("Accessibility permission required"))
        }
        menu.addItem(.separator())

        let pauseTitle = (status == .paused) ? "Resume" : "Pause"
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        if status == .permissionMissing { pauseItem.isEnabled = false }
        menu.addItem(pauseItem)

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Winch", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func togglePause() { onTogglePause?() }
    @objc private func openPreferences() { onOpenPreferences?() }
    @objc private func quit() { onQuit?() }
}
