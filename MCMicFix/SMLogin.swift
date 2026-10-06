import Foundation
import ServiceManagement
import AppKit

enum SMLoginResult: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case failed(String)
}

enum SMLogin {
    static var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    static var isEnabled: Bool {
        status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> SMLoginResult {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Fall through to re-read status — register can throw when approval is needed.
            NSLog("SMAppService error: \(error.localizedDescription)")
            let refreshed = SMAppService.mainApp.status
            if refreshed == .requiresApproval {
                return .requiresApproval
            }
            return .failed(error.localizedDescription)
        }

        let refreshed = SMAppService.mainApp.status
        switch refreshed {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return enabled ? .failed("Login item did not enable.") : .disabled
        @unknown default:
            return enabled ? .failed("Unknown login-item status.") : .disabled
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
