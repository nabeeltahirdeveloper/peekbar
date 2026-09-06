import AppKit
import Combine
import PeekBarCore

/// Observable snapshot of app status for the Settings and Onboarding UI.
enum SettingsTab: Hashable { case general, extras, monitoring, alerts, permissions, about }

@MainActor
final class AppState: ObservableObject {
    @Published var settingsTab: SettingsTab = .general
    @Published var extras: [MenuBarExtra] = []
    @Published var permissions = PermissionState(screenRecording: false, accessibility: false)
    @Published var hotkeyConflict = false
    @Published var hotkeyRegistered = false
    @Published var arrangeHotkeyConflict = false
    @Published var arrangeHotkeyRegistered = false
    @Published var dashboardHotkeyConflict = false
    @Published var dashboardHotkeyRegistered = false
    @Published var widgetWarnings: [ModuleID: String] = [:]
    @Published var notificationAuthorized = false
    @Published var collapseLength: CGFloat = 0
    @Published var lastCaptureError: String?
    @Published var isArranging = false
    @Published var isCollapsed = false
    @Published var loginItemEnabled = false
    @Published var loginItemStatus = ""
    @Published var incompatible: [ExtraRecord] = []
    @Published var lastMessage: String?

    func refreshPermissions() {
        permissions = PermissionState(screenRecording: CGPreflightScreenCaptureAccess(), accessibility: AccessibilityBridge.isTrusted)
        loginItemEnabled = LoginItem.isEnabled
        loginItemStatus = LoginItem.statusDescription
    }
}
