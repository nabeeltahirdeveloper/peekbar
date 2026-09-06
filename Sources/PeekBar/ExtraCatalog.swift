import AppKit
import PeekBarCore

/// A menu bar extra as currently observed (SRS §12 ExtraCatalog).
struct MenuBarExtra: Identifiable {
    let id: ExtraID
    var windowID: CGWindowID
    /// Window frame in the window server's top-left space.
    var frameCG: CGRect
    /// Window frame in AppKit's bottom-left space.
    var frameCocoa: CGRect
    var isOnScreen: Bool
    var windowOwnerPID: pid_t
    var appPID: pid_t?
    var bundleID: String?
    var appName: String?
    var title: String?
    var windowName: String?
    var axElement: AXUIElement?
    var isHidden: Bool
    var zone: Zone
    var isNew: Bool
    var displayName: String
    var incompatibleReason: String?

    /// Clock and Control Center should stay pinned by default (Q5).
    var isSystemProtected: Bool {
        guard bundleID == "com.apple.controlcenter" else { return false }
        let n = (windowName ?? title ?? "").lowercased()
        return n.contains("clock") || n.contains("bentobox") || n == "control center" || n == "control centre"
    }

    var appIcon: NSImage? {
        guard let pid = appPID, let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        return app.icon
    }
}

/// Enumerates status-item windows and enriches them with Accessibility data.
@MainActor
final class ExtraCatalog {
    static let statusWindowLevel = 25          // kCGStatusWindowLevel
    private static let maxItemWidth: CGFloat = 600
    private static let axProbeInterval: TimeInterval = 20

    let store: LayoutStore
    private(set) var extras: [MenuBarExtra] = []
    private(set) var lastScan: Date?
    private(set) var lastScanHadWindowNames = false

    private var axItems: [pid_t: [AXExtraItem]] = [:]
    private var axPIDsWithExtras: Set<pid_t> = []
    private var lastFullAXProbe: Date = .distantPast
    private var probeInFlight = false
    private let probeQueue = DispatchQueue(label: "com.peekbar.ax-probe", qos: .utility)

    var onChange: (() -> Void)?

    init(store: LayoutStore) {
        self.store = store
    }

    // MARK: Window enumeration

    struct RawWindow {
        let id: CGWindowID
        let bounds: CGRect
        let ownerPID: pid_t
        let ownerName: String?
        let name: String?
        let isOnScreen: Bool
        let alpha: CGFloat
    }

    /// Frames of PeekBar's own status items (window-server x and width). On macOS 26 every
    /// status item window is owned by Control Center, so ownership and window numbers cannot
    /// identify our own items; geometry can.
    static func rawStatusWindows(excluding: Set<Int>, ownFrames: [CGRect] = []) -> [RawWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var out: [RawWindow] = []
        for w in list {
            guard (w[kCGWindowLayer as String] as? Int) == statusWindowLevel else { continue }
            guard let num = w[kCGWindowNumber as String] as? Int, !excluding.contains(num) else { continue }
            guard let pid = w[kCGWindowOwnerPID as String] as? Int, pid_t(pid) != ownPID else { continue }
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"] else { continue }
            // Only the menu bar band of the primary display; other layer-25 windows exist.
            guard abs(y) < 1, height >= 18, height <= 48, width >= 4, width <= maxItemWidth else { continue }
            let alpha = w[kCGWindowAlpha as String] as? CGFloat ?? 1
            guard alpha > 0 else { continue }
            if ownFrames.contains(where: { abs($0.minX - x) < 1.5 && abs($0.width - width) < 1.5 }) { continue }
            let name = w[kCGWindowName as String] as? String
            if let n = name?.lowercased(), n.contains("privacy") || n.contains("indicator") { continue }
            out.append(RawWindow(
                id: CGWindowID(num),
                bounds: CGRect(x: x, y: y, width: width, height: height),
                ownerPID: pid_t(pid),
                ownerName: w[kCGWindowOwnerName as String] as? String,
                name: name,
                isOnScreen: w[kCGWindowIsOnscreen as String] as? Bool ?? false,
                alpha: alpha
            ))
        }
        // Drop the copies macOS draws on other displays that share the primary's menu bar band.
        let copies = DisplayDedupe.copies(in: out.map { StatusWindowStub(id: $0.id, minX: $0.bounds.minX, width: $0.bounds.width, name: $0.name, isOnScreen: $0.isOnScreen) },
                                          secondaries: secondaryDisplays())
        return out.filter { !copies.contains($0.id) }.sorted { $0.bounds.minX < $1.bounds.minX }
    }

    /// Non-primary displays whose top edge matches the primary's (their status windows report y == 0 too).
    static func secondaryDisplays() -> [SecondaryDisplay] {
        guard let primary = NSScreen.primary else { return [] }
        return NSScreen.screens.compactMap { s in
            guard s != primary, abs(s.frame.maxY - primary.frame.maxY) < 1 else { return nil }
            return SecondaryDisplay(minX: s.frame.minX, maxX: s.frame.maxX, delta: s.frame.maxX - primary.frame.maxX)
        }
    }

    // MARK: Accessibility index

    /// Probes every running application for an extras menu bar on a background queue.
    func probeAllApplicationsIfDue(force: Bool = false) {
        guard AccessibilityBridge.isTrusted else { return }
        guard force || Date().timeIntervalSince(lastFullAXProbe) > Self.axProbeInterval else { return }
        guard !probeInFlight else { return }
        probeInFlight = true
        lastFullAXProbe = Date()
        let pids = NSWorkspace.shared.runningApplications
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
            .map { $0.processIdentifier }
        probeQueue.async { [weak self] in
            var found: [pid_t: [AXExtraItem]] = [:]
            for pid in pids {
                if let items = AccessibilityBridge.extrasMenuBarItems(pid: pid, timeout: 0.15), !items.isEmpty {
                    found[pid] = items
                }
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.axItems = found
                self.axPIDsWithExtras = Set(found.keys)
                self.probeInFlight = false
                self.rescan(reason: "ax-probe")
            }
        }
    }

    /// Fast refresh of the apps already known to publish extras (positions move on collapse).
    private func refreshKnownAXItems() {
        guard AccessibilityBridge.isTrusted else { axItems = [:]; return }
        for pid in axPIDsWithExtras {
            if let items = AccessibilityBridge.extrasMenuBarItems(pid: pid, timeout: 0.1) {
                axItems[pid] = items
            } else {
                axItems[pid] = nil
            }
        }
        axPIDsWithExtras = Set(axItems.keys)
    }

    func noteApplicationLaunched(_ app: NSRunningApplication) {
        guard AccessibilityBridge.isTrusted else { return }
        let pid = app.processIdentifier
        probeQueue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            let items = AccessibilityBridge.extrasMenuBarItems(pid: pid, timeout: 0.2)
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let items, !items.isEmpty {
                    self.axItems[pid] = items
                    self.axPIDsWithExtras.insert(pid)
                }
                self.rescan(reason: "app-launch")
            }
        }
    }

    func noteApplicationTerminated(_ app: NSRunningApplication) {
        axItems[app.processIdentifier] = nil
        axPIDsWithExtras.remove(app.processIdentifier)
    }

    /// Accessibility frames are often inset from the window (Control Center reports the glyph,
    /// 8 pt inside a 38 pt window), so match by centre containment rather than edges.
    private func matchAX(for window: RawWindow) -> AXExtraItem? {
        var best: AXExtraItem?
        var bestDelta = CGFloat.greatestFiniteMagnitude
        for items in axItems.values {
            for item in items {
                guard item.frame.width > 0 else { continue }
                let mid = item.frame.midX
                guard mid >= window.bounds.minX - 2, mid <= window.bounds.maxX + 2 else { continue }
                let dw = abs(item.frame.width - window.bounds.width)
                guard dw <= 24 else { continue }
                let delta = abs(mid - window.bounds.midX) + dw * 0.25
                if delta < bestDelta { bestDelta = delta; best = item }
            }
        }
        return best
    }

    // MARK: Scan

    /// Synchronous scan. `separatorMinX` is the PeekBar separator's left edge in window-server
    /// coordinates; when nil nothing is considered hidden.
    @discardableResult
    func rescan(reason: String, separatorMinX: CGFloat? = nil, excludeWindowNumbers: Set<Int> = [], refreshAX: Bool = true) -> [MenuBarExtra] {
        let sepX = separatorMinX ?? currentSeparatorMinX
        let excluded = excludeWindowNumbers.isEmpty ? currentExcludedWindows : excludeWindowNumbers
        if refreshAX { refreshKnownAXItems() }

        let windows = Self.rawStatusWindows(excluding: excluded, ownFrames: ownFramesProvider?() ?? [])
        lastScanHadWindowNames = windows.contains { ($0.name ?? "").isEmpty == false }
        let primaryHeight = NSScreen.primaryHeight

        var sources: [IdentitySource] = []
        var displayTitles: [String?] = []
        var matched: [AXExtraItem?] = []
        var apps: [NSRunningApplication?] = []
        for w in windows {
            let ax = matchAX(for: w)
            let app = ax.flatMap { NSRunningApplication(processIdentifier: $0.pid) }
                ?? (w.ownerPID != 0 && isOwnerMeaningful(w) ? NSRunningApplication(processIdentifier: w.ownerPID) : nil)
            matched.append(ax)
            apps.append(app)
            // Descriptions can carry live state ("Wi‑Fi, connected, 3 bars"); keep only the
            // leading label, and prefer the window name for the identity when it is readable.
            let axTitle = ax?.title?.isEmpty == false ? ax?.title : nil
            let axLabel = ax?.descriptionText.flatMap { $0.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } }
            let hasWindowName = !(w.name ?? "").isEmpty
            let identityTitle = axTitle ?? (hasWindowName ? nil : axLabel)
            sources.append(IdentitySource(bundleID: app?.bundleIdentifier, title: identityTitle, windowName: w.name, width: w.bounds.width, minX: w.bounds.minX))
            displayTitles.append(axTitle ?? axLabel)
        }
        let ids = ExtraIdentity.makeIDs(for: sources)
        var siblingCounts: [String: Int] = [:]
        for a in apps { if let b = a?.bundleIdentifier { siblingCounts[b, default: 0] += 1 } }

        var result: [MenuBarExtra] = []
        for (i, w) in windows.enumerated() {
            let app = apps[i]
            let src = sources[i]
            let hidden = sepX.map { ZoneResolver.isHidden(itemMinX: w.bounds.minX, separatorMinX: $0) } ?? false
            let name = ExtraIdentity.displayName(
                bundleID: app?.bundleIdentifier,
                appName: app?.localizedName,
                title: displayTitles[i],
                windowName: w.name,
                siblingCount: app?.bundleIdentifier.map { siblingCounts[$0] ?? 1 } ?? 1
            )
            let rec = store.observe(id: ids[i], displayName: name, bundleID: app?.bundleIdentifier, physicallyHidden: hidden, orderX: Double(w.bounds.minX))
            result.append(MenuBarExtra(
                id: ids[i],
                windowID: w.id,
                frameCG: w.bounds,
                frameCocoa: CoordinateSpace.cocoaRect(fromCG: w.bounds, primaryScreenHeight: primaryHeight),
                isOnScreen: w.isOnScreen,
                windowOwnerPID: w.ownerPID,
                appPID: app?.processIdentifier,
                bundleID: app?.bundleIdentifier,
                appName: app?.localizedName,
                title: src.title,
                windowName: w.name,
                axElement: matched[i]?.element,
                isHidden: hidden,
                zone: rec.zone,
                isNew: rec.isNew,
                displayName: name,
                incompatibleReason: rec.incompatibleReason
            ))
        }
        let changed = result.map(\.id) != extras.map(\.id) || result.map(\.isHidden) != extras.map(\.isHidden)
        extras = result
        lastScan = Date()
        store.save()
        if changed { onChange?() }
        log.debug("rescan(\(reason, privacy: .public)): \(result.count) extras, \(result.filter(\.isHidden).count) hidden")
        return result
    }

    /// On macOS 26 every status item window is owned by Control Center, so ownership only
    /// identifies the app when the owner is not Control Center.
    private func isOwnerMeaningful(_ w: RawWindow) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: w.ownerPID) else { return false }
        return app.bundleIdentifier != "com.apple.controlcenter"
    }

    // Injected by the app so callers can rescan without passing geometry around.
    var separatorMinXProvider: (() -> CGFloat?)?
    var excludedWindowsProvider: (() -> Set<Int>)?
    var ownFramesProvider: (() -> [CGRect])?
    private var currentSeparatorMinX: CGFloat? { separatorMinXProvider?() }
    private var currentExcludedWindows: Set<Int> { excludedWindowsProvider?() ?? [] }

    // MARK: Queries

    func extra(for id: ExtraID) -> MenuBarExtra? { extras.first { $0.id == id } }

    var hidden: [MenuBarExtra] { extras.filter(\.isHidden) }
    var pinned: [MenuBarExtra] { extras.filter { !$0.isHidden } }

    func popupExtras(includeVault: Bool) -> [MenuBarExtra] {
        hidden.filter { includeVault || $0.zone != .vault }
    }

    /// Debug dump (SRS §13 Supportability).
    func dumpJSON() -> Data {
        struct Row: Codable {
            var id: String; var name: String; var bundle: String?; var window: UInt32; var x: Double; var width: Double
            var onScreen: Bool; var hidden: Bool; var zone: String; var hasAX: Bool; var windowName: String?
        }
        let rows = extras.map {
            Row(id: $0.id.raw, name: $0.displayName, bundle: $0.bundleID, window: $0.windowID, x: $0.frameCG.minX, width: $0.frameCG.width,
                onScreen: $0.isOnScreen, hidden: $0.isHidden, zone: $0.zone.rawValue, hasAX: $0.axElement != nil, windowName: $0.windowName)
        }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(rows)) ?? Data()
    }
}
