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
            updateStatus()
        } else {
            menuBar.setStatus(.permissionMissing)
            permissions.requestWithPrompt()
        }
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
            }
            self.updateStatus()
            // Update an open preferences window, if any.
            self.openPreferencesModelIfShowing()?.isAccessibilityTrusted = trusted
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
        if !installed {
            menuBar.setStatus(.permissionMissing)
        }
    }

    private func updateStatus() {
        if !permissions.isTrusted {
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
            preferencesWindow = PreferencesWindowController(
                rootView: PreferencesView(model: model)
            )
        }
        preferencesWindow?.show()
    }

    private func openPreferencesModelIfShowing() -> PreferencesModel? {
        guard let window = preferencesWindow?.window,
              window.isVisible,
              let hosting = window.contentViewController as? NSHostingController<PreferencesView>
        else { return nil }
        return hosting.rootView.model
    }
}
