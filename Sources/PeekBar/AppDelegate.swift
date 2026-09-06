import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PeekBarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    let settings = AppSettings.shared
    let state = AppState()
    private(set) var store: LayoutStore!
    private(set) var status: StatusItemController!
    private(set) var catalog: ExtraCatalog!
    private(set) var capture: CaptureService!
    private(set) var activation: ActivationService!
    private(set) var popup: PopupController!
    private(set) var hotkeys: HotKeyManager!
    private(set) var metrics: MetricsStore!
    private(set) var widgets: WidgetController!
    private(set) var notifications: NotificationService!
    private let cpuModule = CPUModule()
    private let networkModule = NetworkModule()
    private let gpuModule = GPUModule()
    private let sensorsModule = SensorsModule()
    private let clockModule = ClockModule()
    private(set) var arrange: ArrangeController!
    private var settingsWC: SettingsWindowController?
    private var onboardingWC: OnboardingWindowController?
    private var debugBridge: DebugBridge?
    private var rescanTimer: Timer?
    private var collapseWorkItem: DispatchWorkItem?
    private var appearanceObservation: NSKeyValueObservation?
    private var settingsSubscriptions: [Any] = []
    private var lastFlashRefresh: Date = .distantPast

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
        store = LayoutStore(fileURL: AppInfo.supportDirectory.appendingPathComponent("layout.json"))
        store.prune(olderThan: 180 * 86_400)

        status = StatusItemController()
        status.onLayoutRepaired = { [weak self] in
            self?.widgets.rebuildAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.rescanAndPublish(reason: "layout-repaired") }
        }
        catalog = ExtraCatalog(store: store)
        catalog.separatorMinXProvider = { [weak self] in self?.status.separatorFrame?.minX }
        catalog.excludedWindowsProvider = { [weak self] in (self?.status.ownWindowNumbers ?? []).union(self?.widgets.ownWindowNumbers ?? []) }
        widgets = WidgetController()
        widgets.togglePositionProvider = { [weak self] in self?.status.savedTogglePosition }
        status.extraOwnFramesProvider = { [weak self] in self?.widgets.ownFrames ?? [] }
        catalog.ownFramesProvider = { [weak self] in (self?.status.ownFrames ?? []) + (self?.widgets.ownFrames ?? []) }
        catalog.onChange = { [weak self] in self?.publishState() }
        capture = CaptureService()
        activation = ActivationService(status: status, catalog: catalog, capture: capture)
        activation.onTemporaryExpandEnded = { [weak self] in self?.rescanAndPublish(reason: "expand-ended") }
        cpuModule.temperatureProvider = { [sensorsModule] in sensorsModule.lastReading?.cpuTemperature }
        gpuModule.temperatureProvider = { [sensorsModule] in sensorsModule.lastReading?.gpuTemperature }
        clockModule.clocks = settings.clocks
        let engine = MetricsEngine(modules: [cpuModule, RAMModule(), DiskModule(), networkModule, BatteryModule(), gpuModule, sensorsModule, BluetoothModule(), clockModule])
        metrics = MetricsStore(engine: engine)
        metrics.temperatureUnit = settings.temperatureUnit
        metrics.byteStyle = settings.byteStyle
        networkModule.preferredInterface = settings.networkInterface
        networkModule.publicIPEnabled = settings.publicIPEnabled
        applySamplingInterval()
        notifications = NotificationService()
        notifications.temperatureUnit = settings.temperatureUnit
        notifications.onOpenModule = { [weak self] m in self?.openDashboard(detail: m) }
        metrics.setRules(settings.alertRules)
        metrics.onAlert = { [weak self] event in
            self?.notifications.post(event)
            self?.state.lastMessage = "Alert \(event.isFired ? "fired" : "cleared"): \(event.rule.metric.title) \(event.value)"
        }
        popup = PopupController(metrics: metrics)
        activation.pinDropMinXProvider = { [weak self] in self?.widgets.clusterMaxX }
        metrics.onSnapshot = { [weak self] _ in
            guard let self else { return }
            self.widgets.update(from: self.metrics)
        }
        widgets.onPrimaryClick = { [weak self] module, frame in self?.openDashboard(detail: module, anchorMaxX: frame.maxX) }
        widgets.onSecondaryClick = { [weak self] module, _ in self?.showWidgetMenu(module) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.widgets.apply(configs: self.settings.widgetConfigs)
            self.updateMetricsDemand()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.checkWidgetPlacement() }
        }
        popup.model.dashboardModules = settings.enabledModules
        popup.model.dashboardPlacement = settings.dashboardPlacement
        hotkeys = HotKeyManager()
        arrange = ArrangeController()

        wireStatusItem()
        installCommandDragMonitor()
        wirePopup()
        wireHotkey()
        wireArrange()
        observeSystem()
        observeSettings()

        if AppInfo.isDebugBridgeEnabled {
            debugBridge = DebugBridge { [weak self] cmd, arg in self?.handleDebug(cmd, arg) ?? "no-delegate" }
        }

        // Discover while everything is still on screen, capture icons, then collapse after the
        // settle delay (F-83). Onboarding defers the first collapse to Arrange mode.
        catalog.probeAllApplicationsIfDue(force: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.rescanAndPublish(reason: "launch")
            Task { @MainActor in await self?.captureAllVisible() }
        }
        if settings.onboardingCompleted {
            scheduleInitialCollapse()
        } else {
            showOnboarding()
        }
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.activation.isBusy else { return }
                self.rescanAndPublish(reason: "periodic")
                self.catalog.probeAllApplicationsIfDue()
            }
        }
        state.refreshPermissions()
        log.info("PeekBar launched \(AppInfo.version, privacy: .public)")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        store.save()
    }

    private func scheduleInitialCollapse() {
        collapseWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.arrange.isActive else { return }
            Task { @MainActor in
                self.rescanAndPublish(reason: "pre-collapse")
                await self.captureAllVisible()
                guard !self.arrange.isActive else { return }
                self.status.collapse()
                self.rescanAndPublish(reason: "initial-collapse")
            }
        }
        collapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.3, settings.collapseDelay), execute: item)
    }

    // MARK: Wiring

    private func wireStatusItem() {
        status.hoverEnabled = settings.hoverOpen
        status.hoverDelay = Double(settings.hoverDelayMs) / 1000
        status.revealMode = settings.revealMode
        status.onPrimaryClick = { [weak self] event in
            guard let self else { return }
            let vault = event?.modifierFlags.contains(.option) ?? false
            if vault || self.settings.revealMode == .popup {
                self.togglePopup(includeVault: vault)
            } else {
                self.toggleSideways()
            }
        }
        status.onSecondaryClick = { [weak self] event in self?.showContextMenu(event) }
        status.onHoverDwell = { [weak self] in
            guard let self, !self.popup.isVisible else { return }
            self.openPopup(includeVault: false)
        }
    }

    private func wirePopup() {
        popup.autoClose = settings.autoClose
        popup.liveRefresh = settings.liveRefresh
        popup.model.showLabels = settings.showLabels
        popup.model.searchThreshold = settings.searchThreshold
        popup.onActivate = { [weak self] id, right in self?.activateTile(id, rightClick: right) }
        popup.onDismissNew = { [weak self] id in self?.dismissNew(id) }
        popup.onDrop = { [weak self] id, point in self?.handleTileDrop(id, at: point) }
        popup.onArrange = { [weak self] in self?.startArrange() }
        popup.onRequestScreenRecording = { [weak self] in self?.requestScreenRecording() }
        popup.onClosed = { [weak self] in
            self?.status.setActiveAppearance(false)
            self?.updateMetricsDemand()
        }
        popup.onLiveRefresh = { [weak self] in self?.liveRefreshTiles() }
        popup.onOpened = { [weak self] in self?.updateMetricsDemand() }
        popup.onPageChanged = { [weak self] _ in self?.updateMetricsDemand() }
        popup.onMonitoringSettings = { [weak self] in self?.openSettings(tab: .monitoring) }
    }

    private func wireHotkey() {
        hotkeys.setHandler(.popup) { [weak self] in
            guard let self else { return }
            if self.settings.revealMode == .sideways { self.toggleSideways() } else { self.togglePopup(includeVault: false) }
        }
        hotkeys.setHandler(.arrange) { [weak self] in self?.toggleArrange() }
        hotkeys.setHandler(.dashboard) { [weak self] in self?.toggleDashboard() }
        applyHotkey()
    }

    private func applyHotkey() {
        if settings.hotkeyEnabled {
            state.hotkeyRegistered = hotkeys.register(settings.hotkey, id: .popup)
        } else {
            hotkeys.unregister(.popup)
            state.hotkeyRegistered = false
        }
        state.hotkeyConflict = HotKeyManager.conflicts(settings.hotkey)
        if settings.arrangeHotkeyEnabled {
            state.arrangeHotkeyRegistered = hotkeys.register(settings.arrangeHotkey, id: .arrange)
        } else {
            hotkeys.unregister(.arrange)
            state.arrangeHotkeyRegistered = false
        }
        state.arrangeHotkeyConflict = HotKeyManager.conflicts(settings.arrangeHotkey)
            || (settings.hotkeyEnabled && settings.arrangeHotkey == settings.hotkey)
        if settings.dashboardHotkeyEnabled {
            state.dashboardHotkeyRegistered = hotkeys.register(settings.dashboardHotkey, id: .dashboard)
        } else {
            hotkeys.unregister(.dashboard)
            state.dashboardHotkeyRegistered = false
        }
        state.dashboardHotkeyConflict = HotKeyManager.conflicts(settings.dashboardHotkey)
            || (settings.hotkeyEnabled && settings.dashboardHotkey == settings.hotkey)
            || (settings.arrangeHotkeyEnabled && settings.dashboardHotkey == settings.arrangeHotkey)
    }

    // MARK: Monitoring

    /// Modules sample only while something shows them (SRS: idle CPU ≈ 0).
    func updateMetricsDemand() {
        var popupModules: Set<ModuleID> = []
        if popup.isVisible {
            switch popup.model.page {
            case .home: if popup.model.dashboardCardsOnHome > 0 { popupModules = Set(popup.model.dashboardModules) }
            case .dashboard: popupModules = Set(popup.model.dashboardModules)
            case .detail(let id): popupModules = [id]
            }
        }
        let widgetModules = Set(settings.widgetConfigs.map(\.module))
        let alertModules = Set(settings.alertRules.filter(\.enabled).map(\.metric.module))
        metrics.setDemand(DemandSet(popupModules: popupModules, widgetModules: widgetModules, alertModules: alertModules,
                                    enabledModules: Set(settings.enabledModules).union(widgetModules).union(alertModules)))
    }

    private var autoMovedWidgets: Set<ModuleID> = []

    /// Overflow beside the notch: fall back to the mini style, then warn in Settings. A widget
    /// that landed on the hidden side without the user dragging it there is moved back once.
    private func checkWidgetPlacement() {
        var warnings: [ModuleID: String] = [:]
        let hidden = Set(widgets.hiddenWidgets(separatorFrame: status.separatorFrame, toggleFrame: status.toggleFrame))
        for module in hidden {
            guard let c = settings.widgetConfig(for: module), c.placement == .pinned else { continue }
            if autoMovedWidgets.insert(module).inserted {
                widgets.moveBack(module)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.checkWidgetPlacement() }
            } else {
                warnings[module] = "This widget is on the hidden side of the bar. Use “Move back” or ⌘-drag it right of the PeekBar icon."
            }
        }
        for module in widgets.undrawnWidgets() where !hidden.contains(module) {
            if var c = settings.widgetConfig(for: module), c.style != .mini {
                c.style = .mini
                settings.setWidgetConfig(c)
                warnings[module] = "Not enough room beside the notch; switched to the mini style."
            } else {
                warnings[module] = "Not enough room in the menu bar; macOS is not drawing this widget."
            }
        }
        state.widgetWarnings = warnings
    }

    private func showWidgetMenu(_ module: ModuleID) {
        guard let config = settings.widgetConfig(for: module) else { return }
        let menu = NSMenu()
        let styles = NSMenu()
        for style in WidgetLayoutMath.allowedStyles(for: module) {
            let item = styles.addItem(withTitle: style.title, action: #selector(widgetMenuStyle(_:)), keyEquivalent: "")
            item.representedObject = "\(module.rawValue)|\(style.rawValue)"
            item.state = style == config.style ? .on : .off
            item.target = self
        }
        let styleItem = NSMenuItem(title: "Style", action: nil, keyEquivalent: "")
        styleItem.submenu = styles
        menu.addItem(styleItem)
        let color = menu.addItem(withTitle: "Color by load", action: #selector(widgetMenuColor(_:)), keyEquivalent: "")
        color.representedObject = module.rawValue; color.state = config.colorMode == .utilization ? .on : .off; color.target = self
        let label = menu.addItem(withTitle: "Show label", action: #selector(widgetMenuLabel(_:)), keyEquivalent: "")
        label.representedObject = module.rawValue; label.state = config.showLabel ? .on : .off; label.target = self
        menu.addItem(.separator())
        let details = menu.addItem(withTitle: "Show \(module.title) Details", action: #selector(widgetMenuDetails(_:)), keyEquivalent: "")
        details.representedObject = module.rawValue; details.target = self
        let hide = menu.addItem(withTitle: "Remove Widget", action: #selector(widgetMenuRemove(_:)), keyEquivalent: "")
        hide.representedObject = module.rawValue; hide.target = self
        let settingsItem = menu.addItem(withTitle: "Monitoring Settings…", action: #selector(widgetMenuSettings), keyEquivalent: "")
        settingsItem.target = self
        popup.close()
        widgets.showMenu(menu, for: module)
    }

    @objc private func widgetMenuStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        let parts = raw.split(separator: "|").map(String.init)
        guard parts.count == 2, let module = ModuleID(rawValue: parts[0]), let style = WidgetStyle(rawValue: parts[1]),
              var c = settings.widgetConfig(for: module) else { return }
        c.style = style
        settings.setWidgetConfig(c)
    }
    @objc private func widgetMenuColor(_ sender: NSMenuItem) {
        guard let module = (sender.representedObject as? String).flatMap(ModuleID.init(rawValue:)), var c = settings.widgetConfig(for: module) else { return }
        c.colorMode = c.colorMode == .utilization ? .monochrome : .utilization
        settings.setWidgetConfig(c)
    }
    @objc private func widgetMenuLabel(_ sender: NSMenuItem) {
        guard let module = (sender.representedObject as? String).flatMap(ModuleID.init(rawValue:)), var c = settings.widgetConfig(for: module) else { return }
        c.showLabel.toggle()
        settings.setWidgetConfig(c)
    }
    @objc private func widgetMenuDetails(_ sender: NSMenuItem) {
        guard let module = (sender.representedObject as? String).flatMap(ModuleID.init(rawValue:)) else { return }
        openDashboard(detail: module, anchorMaxX: widgets.frame(of: module)?.maxX)
    }
    @objc private func widgetMenuRemove(_ sender: NSMenuItem) {
        guard let module = (sender.representedObject as? String).flatMap(ModuleID.init(rawValue:)) else { return }
        settings.setWidget(module, enabled: false)
    }
    @objc private func widgetMenuSettings() { openSettings(tab: .monitoring) }

    private func applySamplingInterval() {
        var intervals: [ModuleID: TimeInterval] = [:]
        for id in ModuleID.allCases { intervals[id] = max(id.defaultInterval, settings.samplingInterval) }
        metrics.baseIntervals = intervals
    }

    /// Opens the popup on the dashboard (or one module's detail page), optionally anchored
    /// under a widget instead of the PeekBar icon.
    func openDashboard(detail: ModuleID?, anchorMaxX: CGFloat? = nil) {
        if !popup.isVisible { openPopup(includeVault: false, anchorMaxX: anchorMaxX) }
        if let id = detail {
            popup.model.page = .detail(id)
        } else {
            popup.model.page = settings.dashboardPlacement == .hidden ? .dashboard : .home
        }
        popup.relayout()
        updateMetricsDemand()
    }

    func toggleDashboard() {
        if popup.isVisible, popup.model.page != .home || settings.dashboardPlacement != .hidden {
            popup.close()
        } else {
            openDashboard(detail: nil)
        }
    }

    /// Shortcut: show the pocket icons in the bar so they can be ⌘-dragged; press again to collapse.
    func toggleArrange() {
        if arrange.isActive { arrange.end() } else { startArrange() }
    }

    private func wireArrange() {
        arrange.onDone = { [weak self] in self?.finishArrange() }
        arrange.onOpenSettings = { [weak self] in self?.openSettings() }
    }

    private func observeSystem() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.status.refreshCollapseLength()
                self.popup.close()
                self.rescanAndPublish(reason: "screens-changed")
            }
        }
        let wnc = NSWorkspace.shared.notificationCenter
        wnc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.status.refreshCollapseLength()
                self.metrics.resetBaselines()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.rescanAndPublish(reason: "wake") }
            }
        }
        wnc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self.catalog.noteApplicationLaunched(app)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { self.rescanAndPublish(reason: "app-launched") }
            }
        }
        wnc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self.catalog.noteApplicationTerminated(app)
                self.rescanAndPublish(reason: "app-terminated")
            }
        }
        wnc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.popup.close() }
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                self.capture.clearCache()
                if self.popup.isVisible { self.liveRefreshTiles() }
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.capture.clearCache() }
        }
    }

    private func observeSettings() {
        settingsSubscriptions = [
            settings.$hotkey.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.applyHotkey() } },
            settings.$hotkeyEnabled.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.applyHotkey() } },
            settings.$arrangeHotkey.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.applyHotkey() } },
            settings.$arrangeHotkeyEnabled.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.applyHotkey() } },
            settings.$dashboardHotkey.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.applyHotkey() } },
            settings.$dashboardHotkeyEnabled.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.applyHotkey() } },
            settings.$enabledModules.dropFirst().sink { [weak self] ids in
                DispatchQueue.main.async { self?.popup.model.dashboardModules = ids; self?.popup.relayout(); self?.updateMetricsDemand() }
            },
            settings.$dashboardPlacement.dropFirst().sink { [weak self] p in
                DispatchQueue.main.async { self?.popup.model.dashboardPlacement = p; self?.popup.relayout(); self?.updateMetricsDemand() }
            },
            settings.$samplingInterval.dropFirst().sink { [weak self] _ in
                DispatchQueue.main.async { self?.applySamplingInterval(); self?.metrics.setDemand(DemandSet()); self?.updateMetricsDemand() }
            },
            settings.$temperatureUnit.sink { [weak self] u in self?.metrics.temperatureUnit = u },
            settings.$byteStyle.sink { [weak self] b in self?.metrics.byteStyle = b },
            settings.$networkInterface.dropFirst().sink { [weak self] n in self?.networkModule.preferredInterface = n; self?.networkModule.resetBaselines() },
            settings.$publicIPEnabled.dropFirst().sink { [weak self] on in self?.networkModule.publicIPEnabled = on },
            settings.$clocks.dropFirst().sink { [weak self] c in self?.clockModule.clocks = c },
            settings.$alertRules.dropFirst().removeDuplicates().sink { [weak self] rules in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.metrics.setRules(rules)
                    self.updateMetricsDemand()
                    if !rules.isEmpty, !self.notifications.authorized { self.notifications.requestAuthorization { _ in self.refreshNotificationStatus() } }
                }
            },
            settings.$temperatureUnit.sink { [weak self] u in self?.notifications?.temperatureUnit = u },
            settings.$widgetConfigs.dropFirst().removeDuplicates().sink { [weak self] configs in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.widgets.apply(configs: configs)
                    self.updateMetricsDemand()
                    self.widgets.update(from: self.metrics)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.checkWidgetPlacement() }
                }
            },
            settings.$autoClose.sink { [weak self] v in self?.popup.autoClose = v },
            settings.$liveRefresh.sink { [weak self] v in self?.popup.liveRefresh = v },
            settings.$showLabels.sink { [weak self] v in self?.popup.model.showLabels = v; self?.popup.relayout() },
            settings.$searchThreshold.sink { [weak self] v in self?.popup.model.searchThreshold = v },
            settings.$hoverOpen.sink { [weak self] v in self?.status.hoverEnabled = v },
            settings.$hoverDelayMs.sink { [weak self] v in self?.status.hoverDelay = Double(v) / 1000 },
            settings.$showInDock.dropFirst().sink { v in NSApp.setActivationPolicy(v ? .regular : .accessory) },
            settings.$revealMode.dropFirst().sink { [weak self] mode in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.status.revealMode = mode
                    if mode == .popup, !self.status.isCollapsed, !self.arrange.isActive { self.collapseSideways() }
                }
            },
        ]
    }

    // MARK: State publishing

    private var deferredRescan: DispatchWorkItem?

    /// Scans immediately when geometry is settled; otherwise waits for the window server to
    /// finish moving extras and scans once afterwards.
    @discardableResult
    func rescanAndPublish(reason: String) -> [MenuBarExtra] {
        guard status.hasRealFrames else { return catalog.extras }
        guard status.geometryIsSettled, widgets.geometryIsSettled else {
            deferredRescan?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.rescanAndPublish(reason: reason + "-settled") }
            deferredRescan = item
            DispatchQueue.main.asyncAfter(deadline: .now() + StatusItemController.settleInterval, execute: item)
            return catalog.extras
        }
        let extras = catalog.rescan(reason: reason)
        publishState()
        return extras
    }

    func publishState() {
        state.extras = catalog.extras
        state.collapseLength = status.collapseLength
        state.isCollapsed = status.isCollapsed
        state.lastCaptureError = capture.lastError
        state.incompatible = store.incompatible
        state.isArranging = arrange.isActive
        state.refreshPermissions()
        if popup.isVisible { refreshTilesFromCatalog() }
    }

    // MARK: Sideways reveal ("Pocket" mode)

    private var sidewaysTimer: Timer?

    /// Hidden Bar–style reveal: shrink the spacer so the hidden extras slide back into the bar.
    func toggleSideways() {
        guard !arrange.isActive, !activation.isBusy else { return }
        if status.isCollapsed {
            popup.close()
            status.expand()
            rescanAndPublish(reason: "sideways-expand")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in Task { @MainActor in await self?.captureAllVisible() } }
            restartSidewaysTimer()
        } else {
            collapseSideways()
        }
    }

    func collapseSideways() {
        sidewaysTimer?.invalidate(); sidewaysTimer = nil
        guard !status.isCollapsed, !arrange.isActive, !activation.isBusy else { return }
        Task { @MainActor in
            await captureAllVisible()
            status.collapse()
            rescanAndPublish(reason: "sideways-collapse")
        }
    }

    /// The popup's auto-close setting doubles as the sideways auto-hide delay.
    private func restartSidewaysTimer() {
        sidewaysTimer?.invalidate()
        guard let secs = settings.autoClose.seconds else { return }
        sidewaysTimer = Timer.scheduledTimer(withTimeInterval: secs, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.collapseSideways() }
        }
    }

    // MARK: Popup

    func togglePopup(includeVault: Bool) {
        if popup.isVisible { popup.close() } else { openPopup(includeVault: includeVault) }
    }

    func openPopup(includeVault: Bool, anchorMaxX customAnchor: CGFloat? = nil) {
        guard !arrange.isActive else { return }
        if !status.geometryIsSettled {
            DispatchQueue.main.asyncAfter(deadline: .now() + StatusItemController.settleInterval) { [weak self] in self?.openPopup(includeVault: includeVault, anchorMaxX: customAnchor) }
            return
        }
        rescanAndPublish(reason: "popup-open")
        popup.model.includeVault = includeVault
        popup.model.tileStates = [:]
        refreshTilesFromCatalog()

        // Screen Recording: ask on first popup open (SRS §11).
        if !capture.hasPermission && !settings.promptedScreenRecording {
            settings.promptedScreenRecording = true
            capture.requestPermission()
        }

        // F-15 / F-70: host the popup on the display the user is looking at.
        let screen = NSScreen.underMouse ?? status.toggleScreen ?? NSScreen.main ?? NSScreen.screens[0]
        var anchorMaxX = customAnchor ?? status.toggleFrame?.maxX ?? screen.frame.maxX - 60
        if let source = status.toggleScreen, source != screen {
            anchorMaxX = PopupPositioner.mirroredAnchorMaxX(anchorMaxX: anchorMaxX, from: source.geometry, to: screen.geometry)
        }
        popup.show(anchorMaxX: anchorMaxX, on: screen)
        status.setActiveAppearance(true)
        Task { await refreshTileImages(flash: true) }
    }

    private func refreshTilesFromCatalog() {
        var extras = catalog.popupExtras(includeVault: popup.model.includeVault)
        // Keep the grid stable while it is open: a click must not shuffle the tiles.
        let previous = popup.model.tiles.map(\.id)
        if popup.isVisible, !previous.isEmpty {
            let index = Dictionary(previous.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
            extras.sort { (index[$0.id] ?? Int.max, $0.frameCG.minX) < (index[$1.id] ?? Int.max, $1.frameCG.minX) }
        }
        if !capture.hasPermission {
            popup.model.content = .screenRecordingNeeded
        } else if extras.isEmpty {
            popup.model.content = .empty
        } else {
            popup.model.content = .tiles
        }
        popup.model.tiles = extras.map { e in
            TileItem(id: e.id, name: e.displayName, image: capture.cachedImage(for: e.id), fallbackIcon: e.appIcon,
                     imageVersion: 0, isTemplate: capture.isTemplate(e.id), isNew: e.isNew, zone: e.zone)
        }
        popup.relayout()
    }

    private var imageVersion = 0

    /// Fills tiles with live captures; falls back to a brief reveal when icons are missing.
    private func refreshTileImages(flash: Bool) async {
        guard popup.isVisible, capture.hasPermission, let screen = NSScreen.primary else { return }
        let extras = catalog.popupExtras(includeVault: popup.model.includeVault)
        var missing = 0
        for e in extras {
            if await capture.capture(extra: e, scale: screen.backingScaleFactor) == nil, capture.cachedImage(for: e.id) == nil { missing += 1 }
        }
        applyCachedImages()
        if flash, missing > 0, settings.flashRefreshEnabled { flashRefreshIcons(force: false) }
    }

    private func applyCachedImages() {
        imageVersion += 1
        popup.model.tiles = popup.model.tiles.map { t in
            var t = t
            if let img = capture.cachedImage(for: t.id) { t.image = img; t.imageVersion = imageVersion; t.isTemplate = capture.isTemplate(t.id) }
            return t
        }
    }

    private func liveRefreshTiles() {
        guard popup.isVisible, capture.hasPermission, !activation.isBusy else { return }
        Task { await refreshTileImages(flash: false) }
    }

    /// Short show → capture → hide (SRS §12). Rate limited so toggle spam cannot flicker the bar.
    func flashRefreshIcons(force: Bool) {
        guard capture.hasPermission, status.isCollapsed, !activation.isBusy, !arrange.isActive else { return }
        guard force || Date().timeIntervalSince(lastFlashRefresh) > 30 else { return }
        lastFlashRefresh = Date()
        Task { @MainActor in
            status.expand()
            await sleepMs(260)
            catalog.rescan(reason: "flash")
            await captureAllVisible()
            status.collapse()
            rescanAndPublish(reason: "flash-done")
            applyCachedImages()
        }
    }

    /// Captures whatever is currently drawn in the bar. Callers that collapse afterwards must
    /// await this: once the windows are off-screen the capture comes back blank.
    @discardableResult
    func captureAllVisible() async -> Int {
        guard capture.hasPermission, let screen = NSScreen.primary else { return 0 }
        let scale = screen.backingScaleFactor
        let targets = catalog.extras.filter { $0.isOnScreen }
        return await capture.refresh(extras: targets, scale: scale)
    }

    // MARK: Activation

    private func activateTile(_ id: ExtraID, rightClick: Bool) {
        guard !AccessibilityBridge.isTrusted else { runActivation(id, rightClick: rightClick); return }
        popup.model.tileStates[id] = .coachMark
        if !settings.promptedAccessibility {
            settings.promptedAccessibility = true
            AccessibilityBridge.requestTrust()
        } else {
            SystemSettingsPane.accessibility.open()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.popup.model.tileStates[id] = nil }
    }

    private func runActivation(_ id: ExtraID, rightClick: Bool) {
        popup.model.tileStates[id] = .busy
        popup.restartAutoClose()
        Task { @MainActor in
            let outcome = await activation.activate(id, rightClick: rightClick)
            switch outcome {
            case .menuOpened, .activated:
                popup.model.tileStates[id] = nil
                store.setIncompatible(id, reason: nil)
                if outcome.menuOpened { dismissNew(id) }
                if settings.closeBehavior.shouldClose(menuOpened: outcome.menuOpened) { popup.close() }
            case .needsAccessibility:
                popup.model.tileStates[id] = .coachMark
            case .notVisible(let reason), .failed(let reason):
                popup.model.tileStates[id] = .error(reason)
                store.setIncompatible(id, reason: reason)
                store.save()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                    if case .error = self?.popup.model.tileStates[id] ?? .idle { self?.popup.model.tileStates[id] = nil }
                }
            }
            publishState()
        }
    }

    /// A tile dropped on the menu bar band pins that extra at the drop point.
    private func handleTileDrop(_ id: ExtraID, at point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return }
        let geo = screen.geometry
        guard point.y >= geo.menuBarBottom - 30 else {   // dropped elsewhere: nothing happens
            state.lastMessage = "Drop a tile on the menu bar to pin it."
            return
        }
        guard let extra = catalog.extra(for: id) else { return }
        popup.close()
        guard AccessibilityBridge.isTrusted else {
            state.lastMessage = "Grant Accessibility to move extras by dragging."
            SystemSettingsPane.accessibility.open()
            return
        }
        // Drops on another display map to the same distance from the right edge on the primary bar.
        var targetX = point.x
        if let primary = NSScreen.primary, screen != primary {
            targetX = primary.frame.maxX - (screen.frame.maxX - point.x)
        }
        Task { @MainActor in
            let ok = await activation.move(id, toHidden: false, targetX: targetX)
            if ok {
                store.setZone(.pinned, for: id)
                store.save()
                state.lastMessage = "Pinned \(extra.displayName)."
            } else {
                state.lastMessage = "Could not pin \(extra.displayName). Try Arrange mode and ⌘-drag it."
                NSSound.beep()
            }
            rescanAndPublish(reason: "tile-drop")
        }
    }

    // MARK: ⌘-drag in the bar

    private var dragMonitor: Any?
    private var commandDragActive = false

    /// While the user ⌘-drags an extra in the bar, expand so the hide boundary (the dashed
    /// edge of the PeekBar icon) is visible and a drop left of it hides the extra. Collapses
    /// again when the mouse is released. Mouse monitors do not need Accessibility.
    private func installCommandDragMonitor() {
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
            Task { @MainActor in self?.handleGlobalDrag(event) }
        }
    }

    private func handleGlobalDrag(_ event: NSEvent) {
        if event.type == .leftMouseDragged {
            guard !commandDragActive, event.modifierFlags.contains(.command), status.isCollapsed,
                  !arrange.isActive, !activation.isBusy else { return }
            let p = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }),
                  p.y >= screen.geometry.menuBarBottom - 6 else { return }
            commandDragActive = true
            popup.close()
            status.expand()
        } else if event.type == .leftMouseUp, commandDragActive {
            commandDragActive = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self, !self.arrange.isActive, !self.commandDragActive else { return }
                Task { @MainActor in
                    self.catalog.rescan(reason: "command-drag-settle")
                    await self.captureAllVisible()
                    // Widgets dragged left of the spacer stay hidden by choice (option a).
                    for module in self.widgets.hiddenWidgets(separatorFrame: self.status.separatorFrame, toggleFrame: self.status.toggleFrame) {
                        if var c = self.settings.widgetConfig(for: module), c.placement != .hiddenByUser { c.placement = .hiddenByUser; self.settings.setWidgetConfig(c) }
                    }
                    self.status.collapse()
                    self.rescanAndPublish(reason: "command-drag-done")
                }
            }
        }
    }

    // MARK: Arrange mode

    func startArrange() {
        popup.close()
        collapseWorkItem?.cancel()
        status.expand()
        let screen = status.toggleScreen ?? NSScreen.primary ?? NSScreen.screens[0]
        var overflow = false
        if screen.hasNotch {
            let widths = catalog.extras.map { $0.frameCG.width } + [StatusItemController.iconWidth]
            overflow = NotchFit.overflows(itemWidths: widths, availableWidth: screen.geometry.statusAreaWidth)
        }
        arrange.shortcutHint = settings.arrangeHotkeyEnabled ? "\(settings.arrangeHotkey.displayString) to finish" : ""
        arrange.begin(overflow: overflow, on: screen)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.arrange.isActive, let icon = self.status.iconFrame else { return }
            let drawn = ExtraCatalog.rawStatusWindows(excluding: [], ownFrames: []).first {
                abs($0.bounds.maxX - icon.maxX) < 1.5 && $0.bounds.width <= 600
            }?.isOnScreen ?? true
            self.arrange.setDividerHidden(!drawn)
        }
        publishState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.rescanAndPublish(reason: "arrange")
            Task { @MainActor in await self?.captureAllVisible() }
        }
    }

    private func finishArrange() {
        Task { @MainActor in
            catalog.rescan(reason: "arrange-done")
            await captureAllVisible()
            status.collapse()
            rescanAndPublish(reason: "arrange-collapsed")
        }
    }

    // MARK: Onboarding

    func showOnboarding() {
        onboardingWC = OnboardingWindowController(state: state, settings: settings, onArrange: { [weak self] in
            guard let self else { return }
            self.settings.onboardingCompleted = true
            self.onboardingWC?.finish()
            self.startArrange()
        }, onSkip: { [weak self] in
            guard let self else { return }
            self.settings.onboardingCompleted = true
            self.onboardingWC?.finish()
            self.scheduleInitialCollapse()
        })
        onboardingWC?.present()
    }

    // MARK: Settings & actions

    func openSettings(tab: SettingsTab? = nil) {
        if settingsWC == nil { settingsWC = SettingsWindowController(settings: settings, state: state, metrics: metrics) }
        if let tab { state.settingsTab = tab }
        publishState()
        settingsWC?.present()
    }

    func setLoginItem(_ enabled: Bool) {
        do { try LoginItem.setEnabled(enabled) } catch { state.lastMessage = "Login item: \(error.localizedDescription)" }
        state.refreshPermissions()
    }

    func requestScreenRecording() {
        settings.promptedScreenRecording = true
        capture.requestPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.state.refreshPermissions() }
    }

    func requestAccessibility() {
        settings.promptedAccessibility = true
        AccessibilityBridge.requestTrust()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.state.refreshPermissions() }
    }

    func dismissNew(_ id: ExtraID) {
        store.dismissNew(id)
        store.save()
        rescanAndPublish(reason: "dismiss-new")
    }

    func dismissAllNew() {
        store.dismissAllNew()
        store.save()
        rescanAndPublish(reason: "dismiss-all-new")
    }

    func clearIncompatible(_ id: ExtraID) {
        store.setIncompatible(id, reason: nil)
        store.save()
        rescanAndPublish(reason: "clear-incompatible")
    }

    func resetLayout() {
        store.reset()
        store.save()
        capture.clearCache()
        rescanAndPublish(reason: "reset")
    }

    /// Zone changes: Pocket↔Vault is a flag; anything involving Pinned needs a physical move.
    func move(_ id: ExtraID, to zone: Zone) {
        guard let extra = catalog.extra(for: id) else { return }
        let needsPhysicalMove = (zone == .pinned) != (extra.zone == .pinned)
        if !needsPhysicalMove {
            store.setZone(zone, for: id)
            store.save()
            rescanAndPublish(reason: "zone-flag")
            return
        }
        guard AccessibilityBridge.isTrusted else {
            state.lastMessage = "Grant Accessibility to move extras from Settings, or use Arrange mode and ⌘-drag."
            return
        }
        Task { @MainActor in
            let ok = await activation.move(id, toHidden: zone != .pinned)
            if ok {
                store.setZone(zone, for: id)
                store.save()
                state.lastMessage = "Moved \(extra.displayName) to \(zone.title)."
            } else {
                state.lastMessage = "Could not move \(extra.displayName). Try Arrange mode and ⌘-drag it across the divider."
            }
            rescanAndPublish(reason: "zone-move")
        }
    }

    func exportLayout() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "PeekBar Layout.json"
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self else { return }
            do { try self.store.exportJSON().write(to: url); self.state.lastMessage = "Exported layout." }
            catch { self.state.lastMessage = "Export failed: \(error.localizedDescription)" }
        }
    }

    func importLayout() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url, let self else { return }
            do {
                try self.store.importJSON(Data(contentsOf: url))
                self.store.save()
                self.rescanAndPublish(reason: "import")
                self.state.lastMessage = "Imported layout."
            } catch { self.state.lastMessage = "Import failed: \(error.localizedDescription)" }
        }
    }

    func dumpCatalogToFile() {
        let url = AppInfo.supportDirectory.appendingPathComponent("catalog-dump.json")
        try? FileManager.default.createDirectory(at: AppInfo.supportDirectory, withIntermediateDirectories: true)
        try? catalog.dumpJSON().write(to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Context menu (SRS §7.2)

    private func showContextMenu(_ event: NSEvent?) {
        let menu = NSMenu()
        menu.addItem(withTitle: popup.isVisible ? "Hide Popup" : "Show Popup", action: #selector(menuTogglePopup), keyEquivalent: "")
        if settings.revealMode == .sideways {
            menu.addItem(withTitle: status.isCollapsed ? "Show Extras in Menu Bar" : "Hide Extras Again", action: #selector(menuToggleSideways), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Show Popup with Vault", action: #selector(menuShowVault), keyEquivalent: "")
        let dash = menu.addItem(withTitle: "Show Dashboard", action: #selector(menuDashboard), keyEquivalent: "")
        if settings.dashboardHotkeyEnabled { dash.toolTip = "Shortcut: \(settings.dashboardHotkey.displayString)" }
        menu.addItem(.separator())
        let arrangeItem = menu.addItem(withTitle: arrange.isActive ? "Done Arranging" : "Arrange Extras…", action: #selector(menuArrange), keyEquivalent: "")
        if settings.arrangeHotkeyEnabled { arrangeItem.toolTip = "Shortcut: \(settings.arrangeHotkey.displayString)" }
        menu.addItem(withTitle: "Refresh Icons", action: #selector(menuRefreshIcons), keyEquivalent: "")
        let auto = menu.addItem(withTitle: "Auto-close Popup", action: #selector(menuToggleAutoClose), keyEquivalent: "")
        auto.state = settings.autoClose == .off ? .off : .on
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Walkthrough…", action: #selector(menuWalkthrough), keyEquivalent: "")
        if event?.modifierFlags.contains(.option) == true || settings.showDebugTools {
            let debug = NSMenu()
            debug.addItem(withTitle: "Dump Extra Catalog", action: #selector(menuDump), keyEquivalent: "")
            debug.addItem(withTitle: "Dump Metrics Snapshot", action: #selector(menuDumpMetrics), keyEquivalent: "")
            debug.addItem(withTitle: "Collapse length: \(Int(status.collapseLength)) pt", action: nil, keyEquivalent: "")
            debug.addItem(withTitle: "Last capture error: \(capture.lastError ?? "none")", action: nil, keyEquivalent: "")
            debug.addItem(withTitle: status.isCollapsed ? "Expand (debug)" : "Collapse (debug)", action: #selector(menuToggleCollapse), keyEquivalent: "")
            let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
            item.submenu = debug
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PeekBar", action: #selector(menuQuit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        popup.close()
        status.showMenu(menu)
    }

    @objc private func menuTogglePopup() { togglePopup(includeVault: false) }
    @objc private func menuShowVault() { openPopup(includeVault: true) }
    @objc private func menuToggleSideways() { toggleSideways() }
    @objc private func menuDashboard() { openDashboard(detail: nil) }
    @objc private func menuDumpMetrics() { dumpMetricsToFile() }

    func refreshNotificationStatus() {
        notifications.refreshStatus { [weak self] ok in self?.state.notificationAuthorized = ok }
    }

    func requestNotifications() {
        notifications.requestAuthorization { [weak self] ok in self?.state.notificationAuthorized = ok }
    }

    func sendTestNotification() {
        if notifications.authorized { notifications.postTest(module: .cpu) }
        else { notifications.requestAuthorization { [weak self] ok in self?.state.notificationAuthorized = ok; if ok { self?.notifications.postTest(module: .cpu) } } }
    }

    func dumpMetricsToFile() {
        let url = AppInfo.supportDirectory.appendingPathComponent("metrics-dump.json")
        try? FileManager.default.createDirectory(at: AppInfo.supportDirectory, withIntermediateDirectories: true)
        try? metrics.snapshotJSON().write(to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    @objc private func menuArrange() { toggleArrange() }
    @objc private func menuRefreshIcons() { flashRefreshIcons(force: true) }
    @objc private func menuToggleAutoClose() { settings.toggleAutoClose() }
    @objc private func menuSettings() { openSettings() }
    @objc private func menuWalkthrough() { showOnboarding() }
    @objc private func menuDump() { dumpCatalogToFile() }
    @objc private func menuToggleCollapse() { if status.isCollapsed { status.expand() } else { status.collapse() }; publishState() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: Debug bridge

    private func handleDebug(_ cmd: String, _ arg: String?) -> String {
        switch cmd {
        case "ping": return "pong \(AppInfo.version)"
        case "openPopup": openPopup(includeVault: false); return popup.isVisible ? "open" : "closed"
        case "openVault": openPopup(includeVault: true); return popup.isVisible ? "open" : "closed"
        case "closePopup": popup.close(); return "closed"
        case "togglePopup": togglePopup(includeVault: false); return popup.isVisible ? "open" : "closed"
        case "popupFrame": return popup.frame.map { "\($0)" } ?? "none"
        case "popupTiles": return "\(popup.model.tiles.count) content=\(popup.model.content)"
        case "snapshot":
            guard let path = arg, let img = popup.snapshot() else { return "no-snapshot" }
            do { try img.writePNG(to: URL(fileURLWithPath: path)); return "ok" } catch { return "error \(error)" }
        case "settingsSnapshot":
            guard let path = arg else { return "no-path" }
            openSettings()
            guard let v = settingsWC?.window?.contentView, let img = v.snapshotImage() else { return "no-view" }
            do { try img.writePNG(to: URL(fileURLWithPath: path)); return "ok" } catch { return "error \(error)" }
        case "onboardingSnapshot":
            guard let path = arg else { return "no-path" }
            if onboardingWC?.window?.isVisible != true { showOnboarding() }
            guard let v = onboardingWC?.window?.contentView, let img = v.snapshotImage() else { return "no-view" }
            do { try img.writePNG(to: URL(fileURLWithPath: path)); return "ok" } catch { return "error \(error)" }
        case "closeWindows": onboardingWC?.finish(); settingsWC?.close(); return "ok"
        case "dump":
            guard let path = arg else { return "no-path" }
            rescanAndPublish(reason: "debug-dump")
            do { try catalog.dumpJSON().write(to: URL(fileURLWithPath: path)); return "ok \(catalog.extras.count)" } catch { return "error \(error)" }
        case "collapse": collapseWorkItem?.cancel(); status.collapse(); rescanAndPublish(reason: "debug-collapse"); return "collapsed \(Int(status.collapseLength))"
        case "expand": collapseWorkItem?.cancel(); status.expand(); rescanAndPublish(reason: "debug-expand"); return "expanded"
        case "status":
            let t = status.toggleFrame.map { "\($0)" } ?? "nil"
            let s = status.separatorFrame.map { "\($0)" } ?? "nil"
            return "collapsed=\(status.isCollapsed) length=\(Int(status.collapseLength)) toggle=\(t) separator=\(s) extras=\(catalog.extras.count) hidden=\(catalog.hidden.count) sr=\(capture.hasPermission) ax=\(AccessibilityBridge.isTrusted) hotkey=\(state.hotkeyRegistered) conflict=\(state.hotkeyConflict)"
        case "verify": status.verifyOrdering(); return status.verificationReport()
        case "defaults": return status.debugDefaults()
        case "rebuild":
            guard let p = Double(arg ?? "") else { return "usage: rebuild <position>" }
            status.debugRebuild(position: p)
            return "rebuilding"
        case "verifyReport": return status.verificationReport()
        case "reveal":
            guard let key = arg, let extra = catalog.extras.first(where: { $0.id.raw.contains(key) }) else { return "no such extra" }
            let length = status.revealLength(bringing: extra.frameCG.minX, to: status.drawableMinX + 8)
            status.reveal(length: length)
            return "revealing \(extra.id) length=\(Int(length)) from x=\(Int(extra.frameCG.minX))"
        case "revealBoundary":
            let length = status.revealLength(leftEdgeAt: status.drawableMinX + 90)
            status.reveal(length: length)
            return "boundary length=\(Int(length))"
        case "movePin", "moveHide":
            guard let key = arg, let extra = catalog.extras.first(where: { $0.id.raw.contains(key) }) else { return "no such extra" }
            let hide = cmd == "moveHide"
            Task { @MainActor in
                let ok = await self.activation.move(extra.id, toHidden: hide)
                self.state.lastMessage = "debug move \(extra.id) hidden=\(hide): \(ok)"
                self.rescanAndPublish(reason: "debug-move")
            }
            return "moving \(extra.id) toHidden=\(hide)"
        case "lastMessage": return state.lastMessage ?? "none"
        case "metrics":
            guard let path = arg else { return "no-path" }
            do { try metrics.snapshotJSON().write(to: URL(fileURLWithPath: path)); return "ok \(metrics.snapshot.readings.count) modules" } catch { return "error \(error)" }
        case "openDashboard": openDashboard(detail: nil); return "\(popup.model.page)"
        case "openDetail":
            guard let key = arg, let id = ModuleID(rawValue: key) else { return "usage: openDetail <module>" }
            openDashboard(detail: id); return "\(popup.model.page)"
        case "popupPage": return "\(popup.model.page)"
        case "revealMode":
            guard let m = RevealMode(rawValue: arg ?? "") else { return "usage: revealMode <popup|sideways>" }
            settings.revealMode = m; return "revealMode=\(m.rawValue)"
        case "primaryClick": status.onPrimaryClick?(nil); return "collapsed=\(status.isCollapsed) popup=\(popup.isVisible)"
        case "toggleSnapshot":
            guard let path = arg, let img = status.toggleSnapshot() else { return "usage: toggleSnapshot <path>" }
            let scale: CGFloat = 4
            let composed = NSImage(size: NSSize(width: img.size.width * scale, height: img.size.height * scale), flipped: false) { rect in
                NSColor(white: 0.55, alpha: 1).setFill(); rect.fill()
                img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                return true
            }
            do { try composed.writePNG(to: URL(fileURLWithPath: path)); return "ok" } catch { return "error \(error)" }
        case "walkStep":
            guard let n = Int(arg ?? ""), let step = WalkthroughStep(rawValue: n) else { return "usage: walkStep <0-6>" }
            if onboardingWC == nil || onboardingWC?.window?.isVisible != true { showOnboarding() }
            onboardingWC?.model.step = step
            return "step=\(step)"
        case "alertTest": sendTestNotification(); return "authorized=\(notifications.authorized)"
        case "alertRule":
            // alertRule <module.metric> <above|below> <threshold> <seconds>
            let parts = (arg ?? "").split(separator: " ").map(String.init)
            guard parts.count == 4, let dot = parts[0].firstIndex(of: "."), let module = ModuleID(rawValue: String(parts[0][..<dot])),
                  let comparator = AlertComparator(rawValue: parts[1]), let threshold = Double(parts[2]), let seconds = Double(parts[3]) else {
                return "usage: alertRule <module.metric> <above|below> <threshold> <seconds>"
            }
            let key = MetricKey(module: module, metric: String(parts[0][parts[0].index(after: dot)...]))
            settings.alertRules.append(AlertRule(metric: key, comparator: comparator, threshold: threshold, duration: seconds, cooldown: 20))
            return "rules=\(settings.alertRules.count)"
        case "alertsClear": settings.alertRules = []; return "cleared"
        case "alertStatus": return "active=\(metrics.activeAlerts.count) rules=\(settings.alertRules.count) authorized=\(notifications.authorized) demand=\(metrics.demand.demanded.map(\.rawValue).sorted())"
        case "smcKeys":
            let smc = SMCClient()
            do { try smc.open() } catch { return "open failed: \(error.localizedDescription)" }
            defer { smc.close() }
            let keys = smc.allKeys()
            let fans = keys.filter { $0.hasPrefix("F") }
            let temps = keys.filter { $0.hasPrefix("T") }
            let power = keys.filter { $0.hasPrefix("P") }
            let sample = temps.prefix(12).map { "\($0)=\(smc.read($0).map { String(format: "%.1f", $0) } ?? "nil")" }
            return "count=\(keys.count) fans=\(fans) temps=\(temps.count) power=\(power.prefix(10)) sample=\(sample)"
        case "moduleOn", "moduleOff":
            guard let id = ModuleID(rawValue: arg ?? "") else { return "usage: moduleOn|moduleOff <module>" }
            settings.setModule(id, enabled: cmd == "moduleOn"); return "enabled=\(settings.enabledModules.map(\.rawValue))"
        case "widgetOn":
            let parts = (arg ?? "").split(separator: ":").map(String.init)
            guard let module = parts.first.flatMap(ModuleID.init(rawValue:)) else { return "usage: widgetOn <module>[:<style>]" }
            var c = settings.widgetConfig(for: module) ?? WidgetConfig(module: module)
            if parts.count > 1, let style = WidgetStyle(rawValue: parts[1]) { c.style = style }
            settings.setWidgetConfig(c)
            return "widget \(module.rawValue) \(c.style.rawValue)"
        case "widgetOff":
            guard let module = ModuleID(rawValue: arg ?? "") else { return "usage: widgetOff <module>" }
            settings.setWidget(module, enabled: false); return "removed \(module.rawValue)"
        case "widgetFrames": return widgets.debugDescription().isEmpty ? "none" : widgets.debugDescription()
        case "widgetSnapshot":
            let parts = (arg ?? "").split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2, let module = ModuleID(rawValue: parts[0]), let img = widgets.snapshot(module) else { return "usage: widgetSnapshot <module>:<path>" }
            // Compose over a neutral background so label-coloured strokes are visible in the file.
            let scale: CGFloat = 4
            let size = NSSize(width: img.size.width * scale, height: img.size.height * scale)
            let composed = NSImage(size: size, flipped: false) { rect in
                NSColor(white: 0.55, alpha: 1).setFill(); rect.fill()
                img.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                return true
            }
            do { try composed.writePNG(to: URL(fileURLWithPath: parts[1])); return "ok" } catch { return "error \(error)" }
        case "widgetVerify": checkWidgetPlacement(); return "warnings=\(state.widgetWarnings)"
        case "widgetMoveBack":
            guard let module = ModuleID(rawValue: arg ?? "") else { return "usage: widgetMoveBack <module>" }
            widgets.moveBack(module); return "moved \(module.rawValue)"
        case "popupKey":
            guard let code = UInt16(arg ?? "") else { return "usage: popupKey <keyCode>" }
            return "consumed=\(popup.debugKey(code)) page=\(popup.model.page)"
        case "settingsTab":
            let tabs: [String: SettingsTab] = ["general": .general, "extras": .extras, "monitoring": .monitoring, "alerts": .alerts, "permissions": .permissions, "about": .about]
            guard let t = tabs[arg ?? ""] else { return "usage: settingsTab <name>" }
            openSettings(tab: t); return "tab=\(t)"
        case "engineTasks":
            let demand = metrics.demand.demanded.map(\.rawValue).sorted().joined(separator: ",")
            let live = popup.isVisible
            return "demand=[\(demand)] popupVisible=\(live)"
        case "engineTasksAsync":
            Task { @MainActor in
                let n = await self.metrics.engine.liveTaskCount
                self.state.lastMessage = "engineTasks=\(n)"
            }
            return "queued"
        case "sampleNow":
            guard let key = arg, let id = ModuleID(rawValue: key) else { return "usage: sampleNow <module>" }
            Task { @MainActor in
                let r = await self.metrics.engine.sampleNow(id)
                self.state.lastMessage = "\(r)"
            }
            return "sampling \(id)"
        case "activate":
            guard let key = arg, let extra = catalog.extras.first(where: { $0.id.raw.contains(key) }) else { return "no such extra" }
            Task { @MainActor in
                let outcome = await self.activation.activate(extra.id)
                self.state.lastMessage = "activate \(extra.id): \(outcome) via \(self.activation.lastMethod) saw [\(self.activation.lastSeenWindows)]"
                self.rescanAndPublish(reason: "debug-activate")
            }
            return "activating \(extra.id)"
        case "pidClick": activation.preferPidClick = (arg ?? "1") != "0"; return "preferPidClick=\(activation.preferPidClick)"
        case "axprobe":
            guard let pidText = arg, let pid = Int32(pidText) else { return "usage: axprobe <pid>" }
            let items = AccessibilityBridge.extrasMenuBarItems(pid: pid, timeout: 0.5)
            guard let items else { return "no extras menu bar for pid \(pid)" }
            return items.map { "x=\(Int($0.frame.minX)) w=\(Int($0.frame.width)) t=\($0.title ?? "-") d=\($0.descriptionText ?? "-")" }.joined(separator: "; ")
        case "escape": SyntheticInput.pressEscape(); return "escaped"
        case "pressArrangeHotkey": HotKeyManager.press(settings.arrangeHotkey); return "pressed \(settings.arrangeHotkey.displayString) registered=\(state.arrangeHotkeyRegistered)"
        case "pressPopupHotkey": HotKeyManager.press(settings.hotkey); return "pressed \(settings.hotkey.displayString) registered=\(state.hotkeyRegistered)"
        case "axinfo":
            guard let key = arg, let extra = catalog.extras.first(where: { $0.id.raw.contains(key) }) else { return "no such extra" }
            let actions = extra.axElement.map { AccessibilityBridge.actions(of: $0) } ?? []
            return "ax=\(extra.axElement != nil) app=\(extra.bundleID ?? "?") title=\(extra.title ?? "-") actions=\(actions)"
        case "requestAX": requestAccessibility(); return "prompted ax=\(AccessibilityBridge.isTrusted)"
        case "requestSR": requestScreenRecording(); return "prompted sr=\(capture.hasPermission)"
        case "tileImages":
            let withImage = popup.model.tiles.filter { $0.image != nil }.count
            return "\(withImage)/\(popup.model.tiles.count) cached=\(capture.cache.count) lastError=\(capture.lastError ?? "none")"
        case "arrange": startArrange(); return "arranging"
        case "arrangeDone": arrange.end(); return "done"
        case "skipOnboarding": settings.onboardingCompleted = true; onboardingWC?.finish(); scheduleInitialCollapse(); return "ok"
        case "previewTiles":
            let n = Int(arg ?? "8") ?? 8
            let icons = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap { $0.icon }
            popup.model.content = .tiles
            popup.model.tiles = (0..<n).map { i in
                TileItem(id: ExtraID("preview|\(i)"), name: "Preview \(i + 1)", image: nil, fallbackIcon: icons.isEmpty ? nil : icons[i % icons.count], imageVersion: 0, isNew: i == 1, zone: .pocket)
            }
            popup.relayout()
            return "ok \(popup.model.tiles.count) columns=\(popup.model.columns)"
        case "quit": DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }; return "bye"
        default: return "unknown"
        }
    }
}
