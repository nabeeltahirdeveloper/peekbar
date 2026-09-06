import AppKit
import PeekBarCore

/// Owns one NSStatusItem per enabled widget module, placed immediately right of the PeekBar
/// icon (pinned side). Widgets use their own autosave generation so repairs never desync the
/// toggle's name.
@MainActor
final class WidgetController: NSObject {
    private static let generationKey = "widgetGeneration"
    private static var generation: Int { UserDefaults.standard.integer(forKey: generationKey) }
    private static func name(_ module: ModuleID, generation: Int) -> String {
        generation == 0 ? "peekbar_widget_\(module.rawValue)" : "peekbar_widget_\(module.rawValue)_\(generation)"
    }

    private(set) var items: [ModuleID: NSStatusItem] = [:]
    private(set) var views: [ModuleID: WidgetView] = [:]
    private(set) var configs: [WidgetConfig] = []
    private(set) var lastGeometryChange: Date = .distantPast
    private var lastDataUpdate: Date = .distantPast
    private var coreCount = 1

    var geometryIsSettled: Bool { Date().timeIntervalSince(lastGeometryChange) >= StatusItemController.settleInterval }
    var onPrimaryClick: ((ModuleID, CGRect) -> Void)?
    var onSecondaryClick: ((ModuleID, NSEvent?) -> Void)?
    /// Distance from the primary display's right edge to the PeekBar icon's right edge.
    var togglePositionProvider: (() -> CGFloat?)?

    override init() {
        super.init()
        coreCount = Int(Sysctl.int32("hw.ncpu") ?? 1)
    }

    // MARK: Geometry shared with the catalog and status controller

    var ownFrames: [CGRect] { items.values.compactMap { $0.button?.window?.frame } }
    var ownWindowNumbers: Set<Int> { Set(items.values.compactMap { $0.button?.window?.windowNumber }) }
    var clusterMaxX: CGFloat? { ownFrames.map(\.maxX).max() }
    func frame(of module: ModuleID) -> CGRect? { items[module]?.button?.window?.frame }

    // MARK: Apply configuration

    func apply(configs new: [WidgetConfig]) {
        let wanted = Dictionary(uniqueKeysWithValues: new.map { ($0.module, $0) })
        for (module, item) in items where wanted[module] == nil {
            NSStatusBar.system.removeStatusItem(item)
            items[module] = nil
            views[module] = nil
            lastGeometryChange = Date()
        }
        for (rank, config) in new.enumerated() {
            if let view = views[config.module] {
                if view.config != config {
                    view.config = config
                    items[config.module]?.length = width(for: config)
                    lastGeometryChange = Date()
                }
            } else {
                create(config, rank: rank)
            }
        }
        configs = new
    }

    private func width(for config: WidgetConfig) -> CGFloat {
        WidgetLayoutMath.width(for: config.style, module: config.module, coreCount: coreCount, chartWidth: config.chartWidth, showLabel: config.showLabel)
    }

    private func create(_ config: WidgetConfig, rank: Int, generation: Int? = nil) {
        let gen = generation ?? Self.generation
        let name = Self.name(config.module, generation: gen)
        let d = UserDefaults.standard
        let positionKey = "NSStatusItem Preferred Position \(name)"
        if d.object(forKey: positionKey) == nil, let togglePos = togglePositionProvider?() {
            d.set(WidgetLayoutMath.preferredPosition(togglePosition: togglePos, rank: rank), forKey: positionKey)
        }
        d.set(true, forKey: "NSStatusItem Visible \(name)")
        let item = NSStatusBar.system.statusItem(withLength: width(for: config))
        item.autosaveName = name
        item.isVisible = true
        item.behavior = []
        let view = WidgetView(config: config)
        if let b = item.button {
            b.image = nil
            b.title = ""
            b.target = self
            b.action = #selector(clicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.toolTip = config.module.title
            b.setAccessibilityLabel("\(config.module.title) widget")
            view.frame = b.bounds
            view.autoresizingMask = [.width, .height]
            b.addSubview(view)
            b.identifier = NSUserInterfaceItemIdentifier("peekbar.widget.\(config.module.rawValue)")
        }
        items[config.module] = item
        views[config.module] = view
        lastGeometryChange = Date()
    }

    /// Recreates every widget under the next generation, right of the (possibly moved) icon.
    func rebuildAll() {
        guard !items.isEmpty else { return }
        let next = Self.generation + 1
        UserDefaults.standard.set(next, forKey: Self.generationKey)
        let ordered = configs.sorted { (frame(of: $0.module)?.minX ?? 0) < (frame(of: $1.module)?.minX ?? 0) }
        for (_, item) in items { NSStatusBar.system.removeStatusItem(item) }
        items.removeAll(); views.removeAll()
        // Rank 0 is nearest the icon, so create from the rightmost (largest x) first.
        for (rank, config) in ordered.reversed().enumerated() { create(config, rank: rank, generation: next) }
    }

    /// Recreates one widget next to the icon ("Move back" after the user hid it).
    func moveBack(_ module: ModuleID) {
        guard let config = configs.first(where: { $0.module == module }), let item = items[module] else { return }
        let next = Self.generation + 1
        UserDefaults.standard.set(next, forKey: Self.generationKey)
        NSStatusBar.system.removeStatusItem(item)
        items[module] = nil; views[module] = nil
        create(config, rank: 0, generation: next)
    }

    // MARK: Placement checks

    /// Widgets the user ⌘-dragged left of the spacer (they are hidden now).
    func hiddenWidgets(separatorFrame: CGRect?, toggleFrame: CGRect?) -> [ModuleID] {
        guard let s = separatorFrame, let t = toggleFrame else { return [] }
        return items.compactMap { module, item in
            guard let f = item.button?.window?.frame else { return nil }
            return WidgetPlacementCheck.classify(widgetMinX: f.minX, separatorMinX: s.minX, separatorMaxX: s.maxX, toggleMinX: t.minX) == .hidden ? module : nil
        }
    }

    /// Modules whose window macOS is not drawing (overflow beside the notch).
    func undrawnWidgets() -> [ModuleID] {
        let windows = ExtraCatalog.rawStatusWindows(excluding: [], ownFrames: [])
        return items.compactMap { module, item in
            guard let f = item.button?.window?.frame else { return nil }
            let drawn = windows.first { abs($0.bounds.minX - f.minX) < 1.5 && abs($0.bounds.width - f.width) < 1.5 }?.isOnScreen ?? true
            return drawn ? nil : module
        }
    }

    // MARK: Data

    private func shortLabel(_ m: ModuleID) -> String {
        switch m {
        case .cpu: return "CPU"; case .ram: return "RAM"; case .disk: return "SSD"; case .network: return "NET"
        case .battery: return "BAT"; case .gpu: return "GPU"; case .sensors: return "TMP"; case .bluetooth: return "BT"; case .clock: return "CLK"
        }
    }

    func update(from store: MetricsStore) {
        guard !views.isEmpty, Date().timeIntervalSince(lastDataUpdate) >= 0.45 else { return }
        lastDataUpdate = Date()
        for (module, view) in views {
            view.data = data(for: module, store: store)
            if let b = items[module]?.button {
                let tip = "\(module.title): \(view.data.text)"
                if b.toolTip != tip { b.toolTip = tip }
            }
        }
    }

    private func data(for module: ModuleID, store: MetricsStore) -> WidgetData {
        var d = WidgetData()
        d.shortLabel = shortLabel(module)
        guard let reading = store.reading(module) else { d.text = "…"; return d }
        let unit = store.temperatureUnit
        switch reading {
        case .unavailable: d.unavailable = true
        case .cpu(let c):
            d.fraction = c.total; d.text = UnitFormatter.percent(c.total); d.perCore = c.perCore
            d.series = store.history.values(for: .cpuTotal, last: 40)
        case .ram(let r):
            d.fraction = r.usedFraction; d.text = UnitFormatter.percent(r.usedFraction)
            d.series = store.history.values(for: .ramUsed, last: 40)
        case .disk(let k):
            d.fraction = k.primary?.usedFraction; d.text = k.primary.map { UnitFormatter.percent($0.usedFraction) } ?? "–"
            d.downText = UnitFormatter.compactRate(bytesPerSecond: k.readRate); d.upText = UnitFormatter.compactRate(bytesPerSecond: k.writeRate)
            d.series = store.history.values(for: .diskRead, last: 40); d.seriesRange = nil
        case .network(let n):
            d.downText = UnitFormatter.compactRate(bytesPerSecond: n.downloadRate); d.upText = UnitFormatter.compactRate(bytesPerSecond: n.uploadRate)
            d.text = "↓" + d.downText
            d.series = store.history.values(for: .networkDown, last: 40); d.seriesRange = nil
        case .battery(let b):
            d.batteryLevel = b.level; d.charging = b.isCharging; d.fraction = b.level; d.text = UnitFormatter.percent(b.level)
        case .gpu(let g):
            d.fraction = g.utilization; d.text = g.utilization.map { UnitFormatter.percent($0) } ?? "–"
            d.series = store.history.values(for: .gpuUtilization, last: 40)
        case .sensors(let s):
            d.text = s.cpuTemperature.map { UnitFormatter.temperature($0, unit: unit) } ?? "–"
            d.fraction = s.cpuTemperature.map { min(1, $0 / 100) }
        case .bluetooth(let b):
            let connected = b.devices.filter(\.isConnected)
            let withBattery = connected.first { $0.battery != nil || $0.batteryLeft != nil }
            d.text = withBattery.map { UnitFormatter.percent($0.battery ?? $0.batteryLeft ?? 0) } ?? "\(connected.count)"
            d.fraction = withBattery.map { $0.battery ?? $0.batteryLeft ?? 0 }
        case .clock(let c):
            d.text = c.entries.first?.time ?? "–"
        }
        return d
    }

    // MARK: Events

    @objc private func clicked(_ sender: Any?) {
        guard let button = sender as? NSStatusBarButton,
              let module = items.first(where: { $0.value.button === button })?.key else { return }
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            onSecondaryClick?(module, event)
        } else {
            onPrimaryClick?(module, button.window?.frame ?? .zero)
        }
    }

    func showMenu(_ menu: NSMenu, for module: ModuleID) {
        guard let item = items[module] else { return }
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    func snapshot(_ module: ModuleID) -> NSImage? { views[module]?.snapshotImage() }

    func debugDescription() -> String {
        let undrawn = Set(undrawnWidgets())
        return items.keys.sorted().map { m in
            let f = frame(of: m).map { "x=\(Int($0.minX)) w=\(Int($0.width))" } ?? "no-frame"
            return "\(m.rawValue): \(f) drawn=\(!undrawn.contains(m)) style=\(views[m]?.config.style.rawValue ?? "?")"
        }.joined(separator: "; ")
    }
}
