import AppKit
import SwiftUI
import WinchDomain

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var menuBar: MenuBarController!
    private var permissions: PermissionManager!
    private var eventTap: EventTap!
    private var dragController: DragController!
    private var windowController: WindowController!
    private var cursorLocator: SystemCursorLocator!
    private var settings: SettingsStore!
    private var loginItem: LoginItemManager!
    private var preferencesWindow: PreferencesWindowController?
    private var preferencesModel: PreferencesModel?
    private var isEventTapInstalled: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings         = SettingsStore()
        windowController = WindowController()
        cursorLocator    = SystemCursorLocator()
        loginItem        = LoginItemManager()
        permissions      = PermissionManager()
        eventTap         = EventTap()
        menuBar          = MenuBarController()

        dragController = DragController(
            hotkeyConfig: settings.hotkeyConfig,
            windowController: windowController,
            cursorLocator: cursorLocator
        )
        dragController.isPaused = settings.isPaused

        wireMenuBar()
        wirePermissions()

        if permissions.isTrusted {
            installEventTap()
        } else {
            permissions.requestWithPrompt()
        }
        updateStatus()
        permissions.startPolling()
    }

    private func wireMenuBar() {
        menuBar.onTogglePause = { [weak self] in
            guard let self else { return }
            self.dragController.isPaused.toggle()
            self.settings.isPaused = self.dragController.isPaused
            self.updateStatus()
        }
        menuBar.onOpenPreferences = { [weak self] in
            self?.openPreferences()
        }
        menuBar.isLaunchAtLogin = loginItem.isRegistered
        menuBar.onToggleLaunchAtLogin = { [weak self] in
            guard let self else { return }
            do {
                if self.loginItem.isRegistered {
                    try self.loginItem.unregister()
                } else {
                    try self.loginItem.register()
                }
                self.settings.launchAtLogin = self.loginItem.isRegistered
                self.menuBar.isLaunchAtLogin = self.loginItem.isRegistered
                self.preferencesModel?.launchAtLogin = self.loginItem.isRegistered
            } catch {
                NSLog("Login item update failed: \(error)")
            }
        }
        menuBar.onShowAbout = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        }
        menuBar.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private func wirePermissions() {
        permissions.onStatusChange = { [weak self] trusted in
            guard let self else { return }
            if trusted {
                self.installEventTap()
            } else {
                self.eventTap.uninstall()
                self.isEventTapInstalled = false
            }
            self.updateStatus()
            // Update an open preferences window, if any.
            self.preferencesModel?.isAccessibilityTrusted = trusted
        }
    }

    private func installEventTap() {
        let installed = eventTap.install { [weak self] event in
            guard let self else { return }
            switch event {
            case .flagsChanged(let flags):
                self.dragController.handleFlagsChanged(flags)
            case .mouseMoved:
                self.dragController.handleMouseMoved()
            }
        }
        isEventTapInstalled = installed
    }

    private func updateStatus() {
        if !permissions.isTrusted || !isEventTapInstalled {
            menuBar.setStatus(.permissionMissing)
        } else if dragController.isPaused {
            menuBar.setStatus(.paused)
        } else {
            menuBar.setStatus(.active)
        }
    }

    private func openPreferences() {
        if preferencesWindow == nil {
            let model = PreferencesModel(
                initial: settings.hotkeyConfig,
                launchAtLogin: loginItem.isRegistered,
                isAccessibilityTrusted: permissions.isTrusted
            )
            model.onHotkeyChange = { [weak self] config in
                self?.settings.hotkeyConfig = config
                self?.dragController.hotkeyConfig = config
            }
            model.onLaunchAtLoginChange = { [weak self] enabled in
                guard let self else { return }
                do {
                    if enabled { try self.loginItem.register() }
                    else       { try self.loginItem.unregister() }
                    self.settings.launchAtLogin = enabled
                } catch {
                    NSLog("Login item update failed: \(error)")
                }
            }
            model.onOpenSystemSettings = { [weak self] in
                self?.permissions.openSystemSettings()
            }
            preferencesModel = model
            preferencesWindow = PreferencesWindowController(
                rootView: PreferencesView(model: model)
            )
            if let window = preferencesWindow?.window {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handlePreferencesWindowClose(_:)),
                    name: NSWindow.willCloseNotification,
                    object: window
                )
            }
        }
        preferencesWindow?.show()
    }

    @objc private func handlePreferencesWindowClose(_ notification: Notification) {
        if let window = preferencesWindow?.window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        }
        preferencesWindow = nil
        preferencesModel = nil
    }
}
