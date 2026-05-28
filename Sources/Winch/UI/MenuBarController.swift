import AppKit

final class MenuBarController: NSObject {

    enum Status {
        case active
        case paused
        case permissionMissing
    }

    var onTogglePause: (() -> Void)?
    var onOpenPreferences: (() -> Void)?
    var onToggleLaunchAtLogin: (() -> Void)?
    var onShowAbout: (() -> Void)?
    var onQuit: (() -> Void)?

    var isLaunchAtLogin: Bool = false {
        didSet { rebuildMenu() }
    }

    private let statusItem: NSStatusItem
    private(set) var status: Status = .active

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
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
        let symbolName: String
        let accessibilityLabel: String
        switch status {
        case .active:
            symbolName = "arrow.up.and.down.and.arrow.left.and.right"
            accessibilityLabel = "활성"
        case .paused:
            symbolName = "pause.fill"
            accessibilityLabel = "일시정지"
        case .permissionMissing:
            symbolName = "exclamationmark.triangle.fill"
            accessibilityLabel = "권한 필요"
        }
        let image = NSImage(systemSymbolName: symbolName,
                            accessibilityDescription: accessibilityLabel)
        image?.isTemplate = true
        button.image = image
        button.title = ""
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

        let loginItem = NSMenuItem(title: "Launch at login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = isLaunchAtLogin ? .on : .off
        if status == .permissionMissing { loginItem.isEnabled = false }
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "About Winch", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

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
    @objc private func toggleLaunchAtLogin() { onToggleLaunchAtLogin?() }
    @objc private func showAbout() { onShowAbout?() }
    @objc private func quit() { onQuit?() }
}
