import Foundation
import AVFoundation
import AppKit

enum MicAccessStatus: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined

    var line: String {
        switch self {
        case .authorized: return "Mic ready"
        case .notDetermined: return "Mic access needed"
        case .denied, .restricted: return "Mic blocked — open Settings"
        }
    }
}

@MainActor
@Observable
final class MicPermission {
    private(set) var status: MicAccessStatus = .notDetermined

    var statusLine: String { status.line }

    func refresh() {
        status = Self.map(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    @discardableResult
    func requestAccess() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
        return granted
    }

    func openSystemSettings() {
        // Privacy → Microphone deep link
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func map(_ status: AVAuthorizationStatus) -> MicAccessStatus {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}
