import Foundation
import ServiceManagement

@MainActor
enum LoginItemManager {
    static func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("LoginItemManager failed: \(error)")
            }
        }
        // macOS 12: SMLoginItemSetEnabled with a helper bundle required — skipped for MVP.
    }
}
