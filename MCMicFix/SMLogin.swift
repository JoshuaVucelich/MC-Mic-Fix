import Foundation
import ServiceManagement

enum SMLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Best-effort; UI still reflects attempted state via AppState.
            NSLog("SMAppService error: \(error.localizedDescription)")
        }
    }
}
