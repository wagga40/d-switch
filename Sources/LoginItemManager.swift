import Foundation
import ServiceManagement

enum LoginItemManager {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status == .enabled { return true }
                try service.register()
            } else {
                try service.unregister()
            }
            return true
        } catch {
            NSLog("[D-Switch] Launch at Login \(enabled ? "enable" : "disable") failed: \(error.localizedDescription)")
            return false
        }
    }
}
