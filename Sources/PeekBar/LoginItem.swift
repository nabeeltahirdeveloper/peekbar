import Foundation
import ServiceManagement

/// F-60: launch at login via SMAppService.
enum LoginItem {
    static var isSupported: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    static var statusDescription: String {
        guard #available(macOS 13.0, *) else { return "Requires macOS 13. Add PeekBar under System Settings ▸ Users & Groups ▸ Login Items." }
        switch SMAppService.mainApp.status {
        case .enabled: return "Enabled"
        case .requiresApproval: return "Waiting for approval in System Settings"
        case .notFound: return "Not registered"
        case .notRegistered: return "Off"
        @unknown default: return "Unknown"
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw NSError(domain: "PeekBar", code: 13, userInfo: [NSLocalizedDescriptionKey: "Launch at login needs macOS 13 or newer."])
        }
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
