import AppKit
import PeekBarCore

/// Watches for windows that appear after an activation (an NSMenu, a Control Center popover,
/// a custom panel) so we know whether something opened and when it closed.
enum MenuWatcher {
    struct Seen: CustomStringConvertible {
        let id: CGWindowID; let layer: Int; let owner: String; let size: CGSize
        var description: String { "\(owner)#\(id)@L\(layer) \(Int(size.width))x\(Int(size.height))" }
    }

    /// On-screen windows above the normal layer, excluding status items and our own windows.
    static func candidates() -> [Seen] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { w in
            guard let layer = w[kCGWindowLayer as String] as? Int, layer >= 3, layer != 25,
                  let pid = w[kCGWindowOwnerPID as String] as? Int, pid_t(pid) != own,
                  let id = w[kCGWindowNumber as String] as? Int,
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = b["Width"], let height = b["Height"], width >= 20, height >= 20 else { return nil }
            return Seen(id: CGWindowID(id), layer: layer, owner: w[kCGWindowOwnerName as String] as? String ?? "?", size: CGSize(width: width, height: height))
        }
    }

    static func snapshot() -> Set<CGWindowID> { Set(candidates().map(\.id)) }

    static func newWindows(since baseline: Set<CGWindowID>) -> [Seen] {
        candidates().filter { !baseline.contains($0.id) }
    }

    static func stillOpen(_ ids: Set<CGWindowID>) -> Bool {
        !snapshot().isDisjoint(with: ids)
    }
}

/// Synthetic input (requires Accessibility). Restores the cursor afterwards.
enum SyntheticInput {
    private static func post(_ type: CGEventType, at p: CGPoint, button: CGMouseButton, flags: CGEventFlags = []) {
        guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
        e.flags = flags
        e.post(tap: .cghidEventTap)
    }

    private static func postCommandKey(down: Bool) {
        guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 0x37, keyDown: down) else { return }
        e.flags = down ? .maskCommand : []
        e.post(tap: .cghidEventTap)
    }

    static func click(at p: CGPoint, right: Bool) async {
        let original = CGEvent(source: nil)?.location
        post(.mouseMoved, at: p, button: .left)
        await sleepMs(30)
        post(right ? .rightMouseDown : .leftMouseDown, at: p, button: right ? .right : .left)
        await sleepMs(40)
        post(right ? .rightMouseUp : .leftMouseUp, at: p, button: right ? .right : .left)
        await sleepMs(60)
        if let o = original { CGWarpMouseCursorPosition(o) }
    }

    /// Posts Escape (debug helper for closing whatever an activation opened).
    static func pressEscape() {
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down) else { continue }
            e.post(tap: .cghidEventTap)
        }
    }

    /// Delivers a click straight to the process that owns the window, without moving the
    /// cursor. Works for items whose events the owner dispatches itself (Control Center).
    static func click(at p: CGPoint, right: Bool, toPid pid: pid_t) async {
        func send(_ type: CGEventType, _ button: CGMouseButton) {
            guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: button) else { return }
            e.postToPid(pid)
        }
        send(right ? .rightMouseDown : .leftMouseDown, right ? .right : .left)
        await sleepMs(40)
        send(right ? .rightMouseUp : .leftMouseUp, right ? .right : .left)
        await sleepMs(60)
    }

    /// ⌘-drag from one point to another, the gesture macOS uses to rearrange extras (F-43).
    /// Slow enough for the menu bar to enter rearrange mode and reflow live.
    static func commandDrag(from: CGPoint, to: CGPoint) async {
        let original = CGEvent(source: nil)?.location
        let cmd: CGEventFlags = .maskCommand
        post(.mouseMoved, at: from, button: .left)
        await sleepMs(80)
        postCommandKey(down: true)
        await sleepMs(120)
        post(.mouseMoved, at: from, button: .left, flags: cmd)
        await sleepMs(60)
        post(.leftMouseDown, at: from, button: .left, flags: cmd)
        await sleepMs(180)
        let steps = 24
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            // Ease out so the last few pixels are slow and the drop lands precisely.
            let e = 1 - pow(1 - t, 2)
            let p = CGPoint(x: from.x + (to.x - from.x) * e, y: from.y + (to.y - from.y) * e)
            post(.leftMouseDragged, at: p, button: .left, flags: cmd)
            await sleepMs(22)
        }
        post(.leftMouseDragged, at: to, button: .left, flags: cmd)
        await sleepMs(180)
        post(.leftMouseUp, at: to, button: .left, flags: cmd)
        await sleepMs(120)
        postCommandKey(down: false)
        await sleepMs(60)
        if let o = original { CGWarpMouseCursorPosition(o) }
    }
}

/// Maps a tile click to a click on the real extra (SRS §7.4, F-13, F-30..F-33) and moves extras
/// across the hide boundary (F-43). Both use a targeted reveal: the PeekBar item shrinks just
/// enough to bring one extra beside the notch instead of expanding the whole bar.
@MainActor
final class ActivationService {
    private let status: StatusItemController
    private let catalog: ExtraCatalog
    private let capture: CaptureService
    private(set) var isBusy = false
    /// How the last activation reached the extra (debug / supportability).
    private(set) var lastMethod = "none"
    /// Right edge of PeekBar's widget cluster; pinned drops land right of it.
    var pinDropMinXProvider: (() -> CGFloat?)?
    private(set) var lastSeenWindows = ""
    /// Debug switch: deliver synthetic clicks to the owning process instead of the HID tap.
    var preferPidClick = true
    var onTemporaryExpandEnded: (() -> Void)?

    init(status: StatusItemController, catalog: ExtraCatalog, capture: CaptureService) {
        self.status = status
        self.catalog = catalog
        self.capture = capture
    }

    private func isDrawn(_ e: MenuBarExtra) -> Bool {
        guard let screen = NSScreen.primary else { return e.isOnScreen }
        return e.isOnScreen && VisibilityCheck.isFullyVisible(itemFrame: e.frameCocoa, on: screen.geometry)
    }

    /// Brings `id` into the drawn part of the bar by expanding fully. A partial ("targeted")
    /// reveal was tried and dropped: macOS re-sorts neighbours when the spacer changes length
    /// part-way, which silently reorders the user's extras. A full expand never did.
    private func reveal(_ id: ExtraID) async -> MenuBarExtra? {
        catalog.rescan(reason: "reveal")
        guard var extra = catalog.extra(for: id) else { return nil }
        if isDrawn(extra) { return extra }
        status.expand()
        await sleepMs(320)
        catalog.rescan(reason: "reveal-expanded")
        if let fresh = catalog.extra(for: id) { extra = fresh }
        return isDrawn(extra) ? extra : nil
    }

    private func restore(wasCollapsed: Bool) async {
        guard wasCollapsed else { return }
        await sleepMs(120)
        status.collapse()
        onTemporaryExpandEnded?()
    }

    func activate(_ id: ExtraID, rightClick: Bool = false) async -> ActivationOutcome {
        guard AccessibilityBridge.isTrusted else { return .needsAccessibility }
        guard !isBusy else { return .failed("Another activation is in progress.") }
        isBusy = true
        defer { isBusy = false }

        catalog.rescan(reason: "activate")
        guard let initial = catalog.extra(for: id) else { return .failed("The extra is no longer in the menu bar.") }
        let wasCollapsed = status.isCollapsed
        var extra = initial
        if !isDrawn(extra) {
            if let shown = await reveal(id) { extra = shown } else if let fresh = catalog.extra(for: id) { extra = fresh }
        }
        let expanded = status.isCollapsed != wasCollapsed || !status.isCollapsed && wasCollapsed

        let baseline = MenuWatcher.snapshot()
        let visible = isDrawn(extra)
        var pressed = false
        if visible {
            if let el = extra.axElement, !rightClick, AccessibilityBridge.press(el) {
                pressed = true; lastMethod = "axPress"
            } else if let el = extra.axElement, rightClick, AccessibilityBridge.showMenu(el) {
                pressed = true; lastMethod = "axShowMenu"
            } else {
                let center = CGPoint(x: extra.frameCG.midX, y: extra.frameCG.midY)
                if preferPidClick, extra.windowOwnerPID > 0 {
                    await SyntheticInput.click(at: center, right: rightClick, toPid: extra.windowOwnerPID)
                    lastMethod = "pidClick"
                    // If nothing reacts within a moment, fall back to a real click.
                    var reacted = false
                    for _ in 0..<10 {
                        await sleepMs(100)
                        if !MenuWatcher.newWindows(since: baseline).isEmpty { reacted = true; break }
                    }
                    if !reacted {
                        await SyntheticInput.click(at: center, right: rightClick)
                        lastMethod = "pidClick+hidClick"
                    }
                } else {
                    await SyntheticInput.click(at: center, right: rightClick)
                    lastMethod = "hidClick"
                }
                pressed = true
            }
        } else if let el = extra.axElement, AccessibilityBridge.press(el) {
            pressed = true; lastMethod = "axPressUndrawn"
        }

        if expanded, capture.hasPermission, let screen = NSScreen.primary {
            let drawn = catalog.hidden.filter { isDrawn($0) }
            let scale = screen.backingScaleFactor
            Task { @MainActor in _ = await self.capture.refresh(extras: drawn, scale: scale) }
        }

        guard pressed else {
            await restore(wasCollapsed: wasCollapsed)
            return .notVisible("Not enough room right of the camera housing to show this extra.")
        }

        var opened: [MenuWatcher.Seen] = []
        for _ in 0..<12 {
            await sleepMs(100)
            opened = MenuWatcher.newWindows(since: baseline)
            if !opened.isEmpty { break }
        }
        let menuOpened = !opened.isEmpty
        lastSeenWindows = opened.map(\.description).joined(separator: ", ")
        if menuOpened {
            // Keep the bar revealed while whatever opened stays on screen.
            let ids = Set(opened.map(\.id))
            var waited = 0
            await sleepMs(300)
            while MenuWatcher.stillOpen(ids), waited < 120_000 {
                await sleepMs(200)
                waited += 200
            }
        }
        await restore(wasCollapsed: wasCollapsed)
        return menuOpened ? .menuOpened : .activated
    }

    /// F-43: move an extra across the hide boundary with a synthetic ⌘-drag. `targetX`
    /// (window-server x) places a pinned extra at a specific spot; it is clamped to the
    /// pinned side.
    func move(_ id: ExtraID, toHidden: Bool, targetX: CGFloat? = nil) async -> Bool {
        guard AccessibilityBridge.isTrusted, !isBusy else { return false }
        isBusy = true
        defer { isBusy = false }
        let wasCollapsed = status.isCollapsed
        guard let screen = NSScreen.primary else { return false }
        catalog.rescan(reason: "move")
        guard let initial = catalog.extra(for: id) else { return false }
        if initial.isHidden == toHidden { await restore(wasCollapsed: wasCollapsed); return true }

        var from: CGPoint
        var to: CGPoint
        if toHidden {
            // The extra is pinned and drawn. Make the hide boundary (our left edge) visible with
            // room to drop left of it, then drag the extra just past it.
            status.expand()
            await sleepMs(320)
            catalog.rescan(reason: "move-boundary")
            guard let extra = catalog.extra(for: id), isDrawn(extra), let own = status.frame else {
                await restore(wasCollapsed: wasCollapsed)
                return false
            }
            let half = extra.frameCG.width / 2
            from = CGPoint(x: extra.frameCG.midX, y: extra.frameCG.midY)
            to = CGPoint(x: own.minX - half - 4, y: from.y)
        } else {
            // Drop right of the icon so the extra is pinned *and* visibly right of PeekBar.
            guard let extra = await reveal(id), let icon = status.iconFrame else {
                await restore(wasCollapsed: wasCollapsed)
                return false
            }
            let half = extra.frameCG.width / 2
            from = CGPoint(x: extra.frameCG.midX, y: extra.frameCG.midY)
            var x = max(icon.maxX, pinDropMinXProvider?() ?? icon.maxX) + half + 4
            if let t = targetX { x = max(x, t) }
            x = min(x, screen.frame.maxX - half - 2)
            to = CGPoint(x: x, y: from.y)
        }

        await SyntheticInput.commandDrag(from: from, to: to)
        var ok = false
        for _ in 0..<4 {
            await sleepMs(250)
            catalog.rescan(reason: "move-verify")
            if catalog.extra(for: id)?.isHidden == toHidden { ok = true; break }
        }
        await restore(wasCollapsed: wasCollapsed)
        return ok
    }
}
