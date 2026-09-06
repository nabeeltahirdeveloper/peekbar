import Foundation

/// F-52: auto-close after N seconds of no interaction.
public enum AutoCloseOption: Int, CaseIterable, Codable, Sendable {
    case off = 0, five = 5, ten = 10, fifteen = 15, thirty = 30, sixty = 60

    public var title: String {
        switch self {
        case .off: return "Never"
        default: return "\(rawValue) seconds"
        }
    }
    public var seconds: TimeInterval? { self == .off ? nil : TimeInterval(rawValue) }
}

/// Q6: what to do with the popup after a tile activation.
public enum PopupCloseBehavior: String, CaseIterable, Codable, Sendable {
    case smart, always, never

    public var title: String {
        switch self {
        case .smart: return "Close when a menu opens"
        case .always: return "Always close"
        case .never: return "Keep open"
        }
    }

    public func shouldClose(menuOpened: Bool) -> Bool {
        switch self {
        case .smart: return menuOpened
        case .always: return true
        case .never: return false
        }
    }
}

/// F-32 live refresh rate.
public enum LiveRefreshRate: Int, CaseIterable, Codable, Sendable {
    case off = 0, oneHz = 1, twoHz = 2
    public var title: String {
        switch self {
        case .off: return "Off"
        case .oneHz: return "1 per second"
        case .twoHz: return "2 per second"
        }
    }
    public var interval: TimeInterval? { self == .off ? nil : 1.0 / Double(rawValue) }
}

/// Outcome of trying to activate an extra (F-13, F-30, F-31).
public enum ActivationOutcome: Equatable, Sendable {
    case menuOpened
    case activated
    case needsAccessibility
    case notVisible(String)
    case failed(String)

    public var succeeded: Bool {
        switch self {
        case .menuOpened, .activated: return true
        default: return false
        }
    }

    public var menuOpened: Bool { self == .menuOpened }

    public var failureReason: String? {
        switch self {
        case .notVisible(let r), .failed(let r): return r
        case .needsAccessibility: return "Accessibility permission is required to click extras."
        default: return nil
        }
    }
}

/// Which system permissions are granted (SRS §11, PermissionsGate).
public struct PermissionState: Equatable, Sendable {
    public var screenRecording: Bool
    public var accessibility: Bool
    public init(screenRecording: Bool, accessibility: Bool) {
        self.screenRecording = screenRecording
        self.accessibility = accessibility
    }
    public var canCapture: Bool { screenRecording }
    public var canActivate: Bool { accessibility }
    public var allGranted: Bool { screenRecording && accessibility }
}

/// How a click on the PeekBar icon reveals hidden extras.
public enum RevealMode: String, CaseIterable, Codable, Sendable {
    /// "Vault": the Control Center–style popup opens below the icon.
    case popup
    /// "Pocket": hidden extras expand sideways into the menu bar, Hidden Bar style.
    case sideways

    public var title: String {
        switch self {
        case .popup: return "Vault — open below in a popup"
        case .sideways: return "Pocket — open to the left in the menu bar"
        }
    }

    public var summary: String {
        switch self {
        case .popup: return "The icon shows a down arrow. Clicking it opens the popup under the menu bar; the bar itself never moves."
        case .sideways: return "The icon shows a left arrow. Clicking it slides the hidden icons back into the bar; click again to hide them. Icons that do not fit beside the notch are still reachable from the popup shortcut."
        }
    }
}

/// Where the monitoring dashboard sits inside the popup.
public enum DashboardPlacement: String, CaseIterable, Codable, Sendable {
    case top, bottom, hidden
    public var title: String {
        switch self {
        case .top: return "Above extras"
        case .bottom: return "Below extras"
        case .hidden: return "Separate page only"
        }
    }
}
