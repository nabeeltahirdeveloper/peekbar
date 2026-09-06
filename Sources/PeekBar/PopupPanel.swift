import AppKit
import SwiftUI
import PeekBarCore

final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the Control Center–style panel (SRS §7.3, F-10..F-19, F-52, F-53).
@MainActor
final class PopupController {
    let model = PopupModel()
    private let metrics: MetricsStore
    private var panel: PopupPanel?
    private var hosting: NSHostingView<AnyView>?
    private var pageSink: Any?

    init(metrics: MetricsStore) {
        self.metrics = metrics
        pageSink = model.$page.dropFirst().removeDuplicates().sink { [weak self] page in
            DispatchQueue.main.async {
                guard let self else { return }
                self.relayout()
                self.onPageChanged?(page)
            }
        }
    }
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var autoCloseTimer: Timer?
    private var liveTimer: Timer?
    private var lastFlashRefresh: Date = .distantPast
    private(set) var isVisible = false
    private var currentScreen: NSScreen?

    var onActivate: ((ExtraID, Bool) -> Void)?
    var onDismissNew: ((ExtraID) -> Void)?
    var onDrop: ((ExtraID, NSPoint) -> Void)?
    var onArrange: (() -> Void)?
    var onRequestScreenRecording: (() -> Void)?
    var onClosed: (() -> Void)?
    var onLiveRefresh: (() -> Void)?
    var onOpened: (() -> Void)?
    var onPageChanged: ((PopupPage) -> Void)?
    var onMonitoringSettings: (() -> Void)?
    var autoClose: AutoCloseOption = .off
    var liveRefresh: LiveRefreshRate = .oneHz

    private func makePanel() -> PopupPanel {
        let p = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 120),
                           styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                           backing: .buffered, defer: false)
        p.level = .popUpMenu
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = false
        p.becomesKeyOnlyIfNeeded = false
        p.animationBehavior = .none
        p.isReleasedWhenClosed = false
        p.setAccessibilityLabel("PeekBar popup")
        let view = PopupView(
            model: model,
            onActivate: { [weak self] id, right in self?.onActivate?(id, right) },
            onDismissNew: { [weak self] id in self?.onDismissNew?(id) },
            onDrop: { [weak self] id, p in self?.onDrop?(id, p) },
            onArrange: { [weak self] in self?.close(); self?.onArrange?() },
            onOpenScreenRecording: { [weak self] in self?.close(); SystemSettingsPane.screenRecording.open() },
            onRequestScreenRecording: { [weak self] in self?.onRequestScreenRecording?() },
            onOpenDetail: { [weak self] id in self?.model.page = .detail(id) },
            onBack: { [weak self] in self?.model.page = .home },
            onMonitoringSettings: { [weak self] in self?.close(); self?.onMonitoringSettings?() }
        )
        let h = NSHostingView(rootView: AnyView(view.environmentObject(metrics)))
        h.wantsLayer = true
        p.contentView = h
        hosting = h
        return p
    }

    var contentView: NSView? { hosting }

    // MARK: Show / hide

    func show(anchorMaxX: CGFloat, on screen: NSScreen) {
        let p = panel ?? makePanel()
        panel = p
        currentScreen = screen
        model.focusedIndex = nil
        model.query = ""
        model.userTyped = false
        layout(on: screen, anchorMaxX: anchorMaxX)
        installMonitors()
        p.alphaValue = 0
        p.orderFrontRegardless()
        p.makeKey()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = reduceMotion ? 0 : 0.16
            p.animator().alphaValue = 1
        }
        isVisible = true
        restartAutoClose()
        startLiveRefresh()
        onOpened?()
    }

    private var lastAnchorMaxX: CGFloat = 0

    func layout(on screen: NSScreen, anchorMaxX: CGFloat) {
        guard let p = panel else { return }
        lastAnchorMaxX = anchorMaxX
        let geo = screen.geometry
        var cards = 0
        var detail: CGFloat?
        switch model.page {
        case .home: cards = model.dashboardCardsOnHome
        case .dashboard: cards = max(1, model.dashboardModules.count)
        case .detail(let id): detail = DetailHeights.height(for: id)
        }
        let layout = PopupLayout.compute(tileCount: model.content == .tiles ? model.tiles.count : 0,
                                         showLabels: model.showLabels,
                                         showSearch: model.content == .tiles && model.showSearch,
                                         dashboardCards: cards,
                                         detailHeight: detail,
                                         maxHeight: PopupPositioner.maxHeight(on: geo))
        model.columns = max(1, layout.columns)
        let frame = PopupPositioner.frame(anchorMaxX: anchorMaxX, size: layout.size, on: geo)
        p.setFrame(frame, display: true)
    }

    func relayout() {
        guard let s = currentScreen else { return }
        layout(on: s, anchorMaxX: lastAnchorMaxX)
    }

    func close() {
        guard isVisible, let p = panel else { return }
        isVisible = false
        removeMonitors()
        autoCloseTimer?.invalidate(); autoCloseTimer = nil
        liveTimer?.invalidate(); liveTimer = nil
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = reduceMotion ? 0 : 0.12
            p.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                if !self.isVisible { p.orderOut(nil) }
            }
        })
        onClosed?()
    }

    var frame: CGRect? { panel?.frame }

    // MARK: Monitors

    private func installMonitors() {
        removeMonitors()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .mouseMoved, .scrollWheel]) { [weak self] event in
            guard let self, let p = self.panel else { return event }
            if event.type == .keyDown {
                if event.window === p { return self.handleKey(event) ? nil : event }
                return event
            }
            if event.window !== p, event.type == .leftMouseDown || event.type == .rightMouseDown {
                self.close()
                return event
            }
            self.restartAutoClose()
            return event
        }
    }

    private func removeMonitors() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    /// Debug: feed a key code through the popup's key handling as if the panel were key.
    func debugKey(_ keyCode: UInt16) -> Bool {
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                       characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode) else { return false }
        return handleKey(e)
    }

    /// F-19 keyboard operation. Returns true when the event was consumed.
    private func handleKey(_ event: NSEvent) -> Bool {
        let count = model.filtered.count
        if event.keyCode == 53 {
            if model.page != .home { model.page = .home } else { close() }
            return true
        }
        guard model.page == .home else { return false }
        switch event.keyCode {
        case 123: model.focusedIndex = GridNavigation.move(from: model.focusedIndex, direction: .left, count: count, columns: model.columns); return true
        case 124: model.focusedIndex = GridNavigation.move(from: model.focusedIndex, direction: .right, count: count, columns: model.columns); return true
        case 126: model.focusedIndex = GridNavigation.move(from: model.focusedIndex, direction: .up, count: count, columns: model.columns); return true
        case 125: model.focusedIndex = GridNavigation.move(from: model.focusedIndex, direction: .down, count: count, columns: model.columns); return true
        case 36, 76:
            if let i = model.focusedIndex, i < count { onActivate?(model.filtered[i].id, false); return true }
            if let first = model.filtered.first, model.showSearch, !model.query.isEmpty { onActivate?(first.id, false); return true }
            return false
        case 48:
            model.focusedIndex = GridNavigation.move(from: model.focusedIndex, direction: event.modifierFlags.contains(.shift) ? .left : .right, count: count, columns: model.columns)
            return true
        default:
            break
        }
        if model.content == .tiles, !model.showSearch, let chars = event.characters, !chars.isEmpty,
           chars.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == " " }),
           !event.modifierFlags.contains(.command) {
            model.userTyped = true
            model.query.append(chars)
            relayout()
            return true
        }
        return false
    }

    // MARK: Timers

    func restartAutoClose() {
        autoCloseTimer?.invalidate()
        guard isVisible, let secs = autoClose.seconds else { return }
        autoCloseTimer = Timer.scheduledTimer(withTimeInterval: secs, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, let f = self.panel?.frame else { return }
                // F-53: if the pointer is inside, restart instead of closing.
                if NSMouseInRect(NSEvent.mouseLocation, f, false) { self.restartAutoClose() } else { self.close() }
            }
        }
    }

    private func startLiveRefresh() {
        liveTimer?.invalidate()
        guard let interval = liveRefresh.interval else { return }
        liveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onLiveRefresh?() }
        }
    }

    func snapshot() -> NSImage? { hosting?.snapshotImage() }
}
