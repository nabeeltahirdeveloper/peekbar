import Foundation
import Combine
import PeekBarCore

/// User settings (SRS F-17, F-50..F-53, F-60..F-62, Q6). Backed by UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d: UserDefaults

    init(defaults: UserDefaults = .standard) {
        d = defaults
        showLabels = d.bool(forKey: "showLabels")
        autoClose = AutoCloseOption(rawValue: d.integer(forKey: "autoCloseSeconds")) ?? .off
        lastAutoClose = AutoCloseOption(rawValue: d.integer(forKey: "lastAutoCloseSeconds")) ?? .ten
        closeBehavior = PopupCloseBehavior(rawValue: d.string(forKey: "closeBehavior") ?? "") ?? .smart
        hoverOpen = d.bool(forKey: "hoverOpen")
        hoverDelayMs = d.object(forKey: "hoverDelayMs") as? Int ?? 400
        collapseDelay = d.object(forKey: "collapseDelay") as? Double ?? 2.0
        showInDock = d.bool(forKey: "showInDock")
        hotkeyEnabled = d.object(forKey: "hotkeyEnabled") as? Bool ?? true
        if let data = d.data(forKey: "hotkey"), let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            hotkey = combo
        } else {
            hotkey = .defaultCombo
        }
        arrangeHotkeyEnabled = d.object(forKey: "arrangeHotkeyEnabled") as? Bool ?? true
        if let data = d.data(forKey: "arrangeHotkey"), let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            arrangeHotkey = combo
        } else {
            arrangeHotkey = .defaultArrangeCombo
        }
        liveRefresh = LiveRefreshRate(rawValue: d.object(forKey: "liveRefresh") as? Int ?? 1) ?? .oneHz
        searchThreshold = d.object(forKey: "searchThreshold") as? Int ?? 12
        onboardingCompleted = d.bool(forKey: "onboardingCompleted")
        flashRefreshEnabled = d.object(forKey: "flashRefreshEnabled") as? Bool ?? true
        promptedScreenRecording = d.bool(forKey: "promptedScreenRecording")
        promptedAccessibility = d.bool(forKey: "promptedAccessibility")
        showDebugTools = d.bool(forKey: "showDebugTools")
        revealMode = RevealMode(rawValue: d.string(forKey: "revealMode") ?? "") ?? .popup
        if let data = d.data(forKey: "enabledModules"), let ids = try? JSONDecoder().decode([ModuleID].self, from: data) {
            enabledModules = ids
        } else {
            enabledModules = ModuleID.defaultEnabled
        }
        dashboardPlacement = DashboardPlacement(rawValue: d.string(forKey: "dashboardPlacement") ?? "") ?? .top
        dashboardHotkeyEnabled = d.object(forKey: "dashboardHotkeyEnabled") as? Bool ?? true
        if let data = d.data(forKey: "dashboardHotkey"), let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) {
            dashboardHotkey = combo
        } else {
            dashboardHotkey = .defaultDashboardCombo
        }
        samplingInterval = d.object(forKey: "samplingInterval") as? Double ?? 1
        temperatureUnit = TemperatureUnit(rawValue: d.string(forKey: "temperatureUnit") ?? "") ?? .celsius
        byteStyle = ByteStyle(rawValue: d.string(forKey: "byteStyle") ?? "") ?? .binary
        networkInterface = d.string(forKey: "networkInterface")
        publicIPEnabled = d.bool(forKey: "publicIPEnabled")
        if let data = d.data(forKey: "clocks"), let list = try? JSONDecoder().decode([WorldClock].self, from: data) {
            clocks = list
        } else {
            clocks = [WorldClock(timeZoneID: "UTC", label: "UTC")]
        }
        if let data = d.data(forKey: "alertRules"), let list = try? JSONDecoder().decode([AlertRule].self, from: data) {
            alertRules = list
        } else {
            alertRules = []
        }
        if let data = d.data(forKey: "widgetConfigs"), let list = try? JSONDecoder().decode([WidgetConfig].self, from: data) {
            widgetConfigs = list
        } else {
            widgetConfigs = []
        }
    }

    @Published var clocks: [WorldClock] {
        didSet { if let data = try? JSONEncoder().encode(clocks) { d.set(data, forKey: "clocks") } }
    }

    @Published var alertRules: [AlertRule] {
        didSet { if let data = try? JSONEncoder().encode(alertRules) { d.set(data, forKey: "alertRules") } }
    }

    // MARK: Menu bar widgets

    @Published var widgetConfigs: [WidgetConfig] {
        didSet { if let data = try? JSONEncoder().encode(widgetConfigs) { d.set(data, forKey: "widgetConfigs") } }
    }

    func widgetConfig(for module: ModuleID) -> WidgetConfig? { widgetConfigs.first { $0.module == module } }

    func setWidgetConfig(_ config: WidgetConfig) {
        var list = widgetConfigs
        if let i = list.firstIndex(where: { $0.module == config.module }) { list[i] = config } else { list.append(config) }
        widgetConfigs = list
    }

    func setWidget(_ module: ModuleID, enabled: Bool) {
        if enabled {
            if widgetConfig(for: module) == nil { setWidgetConfig(WidgetConfig(module: module)) }
        } else {
            widgetConfigs.removeAll { $0.module == module }
        }
    }

    // MARK: Monitoring

    @Published var enabledModules: [ModuleID] {
        didSet { if let data = try? JSONEncoder().encode(enabledModules) { d.set(data, forKey: "enabledModules") } }
    }
    @Published var dashboardPlacement: DashboardPlacement { didSet { d.set(dashboardPlacement.rawValue, forKey: "dashboardPlacement") } }
    @Published var dashboardHotkeyEnabled: Bool { didSet { d.set(dashboardHotkeyEnabled, forKey: "dashboardHotkeyEnabled") } }
    @Published var dashboardHotkey: KeyCombo {
        didSet { if let data = try? JSONEncoder().encode(dashboardHotkey) { d.set(data, forKey: "dashboardHotkey") } }
    }
    @Published var samplingInterval: Double { didSet { d.set(samplingInterval, forKey: "samplingInterval") } }
    @Published var temperatureUnit: TemperatureUnit { didSet { d.set(temperatureUnit.rawValue, forKey: "temperatureUnit") } }
    @Published var byteStyle: ByteStyle { didSet { d.set(byteStyle.rawValue, forKey: "byteStyle") } }
    @Published var networkInterface: String? {
        didSet { if let n = networkInterface { d.set(n, forKey: "networkInterface") } else { d.removeObject(forKey: "networkInterface") } }
    }
    @Published var publicIPEnabled: Bool { didSet { d.set(publicIPEnabled, forKey: "publicIPEnabled") } }

    func isModuleEnabled(_ id: ModuleID) -> Bool { enabledModules.contains(id) }

    func setModule(_ id: ModuleID, enabled: Bool) {
        var list = enabledModules
        if enabled, !list.contains(id) { list.append(id) }
        if !enabled { list.removeAll { $0 == id } }
        enabledModules = list
    }

    @Published var showLabels: Bool { didSet { d.set(showLabels, forKey: "showLabels") } }
    @Published var autoClose: AutoCloseOption {
        didSet {
            d.set(autoClose.rawValue, forKey: "autoCloseSeconds")
            if autoClose != .off { lastAutoClose = autoClose }
        }
    }
    /// Remembered so "Toggle auto-close" in the context menu can restore the last duration.
    @Published var lastAutoClose: AutoCloseOption { didSet { d.set(lastAutoClose.rawValue, forKey: "lastAutoCloseSeconds") } }
    @Published var closeBehavior: PopupCloseBehavior { didSet { d.set(closeBehavior.rawValue, forKey: "closeBehavior") } }
    @Published var hoverOpen: Bool { didSet { d.set(hoverOpen, forKey: "hoverOpen") } }
    @Published var hoverDelayMs: Int { didSet { d.set(hoverDelayMs, forKey: "hoverDelayMs") } }
    @Published var collapseDelay: Double { didSet { d.set(collapseDelay, forKey: "collapseDelay") } }
    @Published var showInDock: Bool { didSet { d.set(showInDock, forKey: "showInDock") } }
    @Published var hotkeyEnabled: Bool { didSet { d.set(hotkeyEnabled, forKey: "hotkeyEnabled") } }
    @Published var hotkey: KeyCombo {
        didSet { if let data = try? JSONEncoder().encode(hotkey) { d.set(data, forKey: "hotkey") } }
    }
    @Published var arrangeHotkeyEnabled: Bool { didSet { d.set(arrangeHotkeyEnabled, forKey: "arrangeHotkeyEnabled") } }
    @Published var arrangeHotkey: KeyCombo {
        didSet { if let data = try? JSONEncoder().encode(arrangeHotkey) { d.set(data, forKey: "arrangeHotkey") } }
    }
    @Published var liveRefresh: LiveRefreshRate { didSet { d.set(liveRefresh.rawValue, forKey: "liveRefresh") } }
    @Published var searchThreshold: Int { didSet { d.set(searchThreshold, forKey: "searchThreshold") } }
    @Published var onboardingCompleted: Bool { didSet { d.set(onboardingCompleted, forKey: "onboardingCompleted") } }
    @Published var flashRefreshEnabled: Bool { didSet { d.set(flashRefreshEnabled, forKey: "flashRefreshEnabled") } }
    @Published var promptedScreenRecording: Bool { didSet { d.set(promptedScreenRecording, forKey: "promptedScreenRecording") } }
    @Published var promptedAccessibility: Bool { didSet { d.set(promptedAccessibility, forKey: "promptedAccessibility") } }
    @Published var showDebugTools: Bool { didSet { d.set(showDebugTools, forKey: "showDebugTools") } }
    @Published var revealMode: RevealMode { didSet { d.set(revealMode.rawValue, forKey: "revealMode") } }

    func toggleAutoClose() {
        autoClose = autoClose == .off ? lastAutoClose : .off
    }
}
