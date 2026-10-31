import Foundation
import ServiceManagement

/// Login item registration via SMAppService. Only valid when running from an app bundle.
public enum LoginItemService {
    public static var isAvailable: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    public static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    public static func setEnabled(_ enabled: Bool) throws {
        guard isAvailable else {
            throw EnvBoxError.io("仅在 App Bundle 中运行时可设置登录项")
        }
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            throw EnvBoxError.io(error.localizedDescription)
        }
    }
}
