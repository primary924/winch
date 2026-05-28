import Foundation
import ServiceManagement

final class LoginItemManager {

    var isRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers the main app to launch at login. Throws on failure
    /// (e.g., the bundle is not signed or the user denied the operation).
    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
