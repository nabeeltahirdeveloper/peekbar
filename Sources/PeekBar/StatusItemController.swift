import AppKit
import PeekBarCore

/// Owns the PeekBar affordance and the hiding spacer, and applies the collapse length
/// (SRS §12 StatusItemController, F-80..F-84).
///
/// Two items are unavoidable: macOS never draws a status item that does not fit in the bar,
/// so the glyph cannot live inside the 1512-point spacer. The spacer sits immediately left of
/// the icon and is only 8 points wide when expanded, so "left of the PeekBar icon" is the hide
/// boundary for all practical purposes; the icon shows a dashed left edge while expanded.
@MainActor
final class StatusItemController: NSObject {
    static let iconWidth: CGFloat = 34
    static let spacerExpandedLength: CGFloat = 12
    static let settleInterval: TimeInterval = 0.4

    /// Autosave names carry a generation suffix: AppKit ignores a saved position for a name it
    /// already created in this process, so a repair rebuilds under a fresh name.
    private static let generationKey = "statusItemGeneration"
    private static var generation: Int { UserDefaults.standard.integer(forKey: generationKey) }
    private static func name(_ base: String, generation: Int) -> String { generation == 0 ? base : "\(base)_\(generation)" }
    static var toggleAutosave: String { name("peekbar_toggle", generation: generation) }
    static var separatorAutosave: String { name("peekbar_separator", generation: generation) }

    enum Mode { case collapsed, expanded, revealing }

    private(set) var toggle: NSStatusItem!
    private(set) var separator: NSStatusItem!
    private(set) var mode: Mode = .expanded
    var isCollapsed: Bool { mode == .collapsed }
    var isFullyExpanded: Bool { mode == .expanded }

    /// The window server takes ~150 ms to reposition other extras after the spacer changes
    /// length; scans inside that window see stale geometry.
    private(set) var lastGeometryChange: Date = .distantPast
    var geometryIsSettled: Bool { Date().timeIntervalSince(lastGeometryChange) >= Self.settleInterval }

    private var hoverTimer: Timer?
    private var verificationAttempts = 0
    private var repairFloorX: CGFloat = -.greatestFiniteMagnitude
    private var activeAppearance = false
    var revealMode: RevealMode = .popup { didSet { updateGlyph() } }

    var onPrimaryClick: ((NSEvent?) -> Void)?
    var onSecondaryClick: ((NSEvent?) -> Void)?
    var onHoverDwell: (() -> Void)?
    var onLayoutRepaired: (() -> Void)?
    /// The toggle's saved "Preferred Position" (distance from the right edge to its right
    /// edge). Widgets rank against this value, not the live frame: the frame shifts left as
    /// widgets are inserted while the saved value does not.
    var savedTogglePosition: CGFloat? {
        if let v = UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position \(Self.toggleAutosave)") as? Double { return CGFloat(v) }
        guard let f = toggleFrame, let screen = NSScreen.primary else { return nil }
        return screen.frame.maxX - f.maxX
    }

    /// Frames of other PeekBar-owned status items (widgets) to ignore during repairs.
    var extraOwnFramesProvider: (() -> [CGRect])?
    var hoverDelay: TimeInterval = 0.4
    var hoverEnabled = false

    override init() {
        super.init()
        Self.forceVisible()
        build()
        scheduleVerification()
    }

    // MARK: Building

    /// F-82: both items must be visible at launch so a stray ⌘-drag off the bar can never
    /// brick the app.
    private static func forceVisible() {
        for name in [toggleAutosave, separatorAutosave] {
            UserDefaults.standard.set(true, forKey: "NSStatusItem Visible \(name)")
        }
    }

    private func build() {
        // Create the toggle first: macOS inserts new items at the left end of the extras
        // cluster, so creating the spacer second places it left of the toggle.
        toggle = NSStatusBar.system.statusItem(withLength: Self.iconWidth)
        toggle.autosaveName = Self.toggleAutosave
        toggle.isVisible = true
        toggle.behavior = []
        if let b = toggle.button {
            b.image = Glyphs.toggle
            b.imagePosition = .imageOnly
            b.target = self
            b.action = #selector(toggleClicked(_:))
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
            b.toolTip = "PeekBar — click for hidden extras. Extras left of this icon are hidden."
            b.setAccessibilityLabel("PeekBar")
            for ta in b.trackingAreas { b.removeTrackingArea(ta) }
            b.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        }

        separator = NSStatusBar.system.statusItem(withLength: Self.spacerExpandedLength)
        separator.autosaveName = Self.separatorAutosave
        separator.isVisible = true
        separator.behavior = []
        if let b = separator.button {
            b.image = Glyphs.separator
            b.imagePosition = .imageOnly
            b.title = ""
            b.toolTip = "PeekBar divider — extras left of this line are hidden"
            b.setAccessibilityLabel("PeekBar hide boundary")
        }
        mode = .expanded
    }

    // MARK: Modes

    var collapseLength: CGFloat {
        CollapseMath.collapseLength(screenWidths: NSScreen.screens.map { $0.frame.width })
    }

    private func setLength(_ length: CGFloat, mode: Mode) {
        lastGeometryChange = Date()
        self.mode = mode
        separator.length = length
        // The divider line is only meaningful while the boundary is on screen.
        separator.button?.image = mode == .collapsed ? nil : Glyphs.separator
        updateGlyph()
    }

    func collapse() { setLength(collapseLength, mode: .collapsed) }
    func expand() { setLength(Self.spacerExpandedLength, mode: .expanded) }

    /// Partial expansion ("targeted show"): the spacer keeps its right edge and shrinks to
    /// `length`, shifting hidden extras right by the difference.
    func reveal(length: CGFloat) {
        let l = max(Self.spacerExpandedLength, min(collapseLength, length))
        setLength(l, mode: l <= Self.spacerExpandedLength ? .expanded : .revealing)
    }

    var currentLength: CGFloat { separator.length }

    /// Length that brings a hidden extra currently at `itemMinX` (window-server x) to `targetMinX`.
    func revealLength(bringing itemMinX: CGFloat, to targetMinX: CGFloat) -> CGFloat {
        RevealMath.length(current: separator.length, itemMinX: itemMinX, targetMinX: targetMinX, minLength: Self.spacerExpandedLength)
    }

    /// Length that puts the spacer's left edge (the hide boundary) at `x`.
    func revealLength(leftEdgeAt x: CGFloat) -> CGFloat {
        guard let f = separatorFrame else { return Self.spacerExpandedLength }
        return RevealMath.length(rightEdge: f.maxX, leftEdgeAt: x, minLength: Self.spacerExpandedLength)
    }

    /// F-81: re-derive the collapse length when displays change.
    func refreshCollapseLength() {
        if isCollapsed { setLength(collapseLength, mode: .collapsed) }
    }

    /// Leftmost x the window server draws status items at, on the primary display.
    var drawableMinX: CGFloat {
        guard let s = NSScreen.primary else { return 0 }
        return RevealMath.drawableMinX(on: s.geometry)
    }

    // MARK: Geometry (Cocoa coordinates; x/width equal window-server values)

    var toggleFrame: CGRect? { toggle.button?.window?.frame }
    var separatorFrame: CGRect? { separator.button?.window?.frame }
    /// The glyph.
    var iconFrame: CGRect? { toggleFrame }
    /// The hide boundary item.
    var frame: CGRect? { separatorFrame }
    var toggleScreen: NSScreen? { toggle.button?.window?.screen }
    var screen: NSScreen? { toggleScreen }

    /// Where the glyph appears on another display (menu bar items mirror at the same distance
    /// from the right edge).
    func iconFrame(on screen: NSScreen) -> CGRect? {
        guard let icon = iconFrame, let primary = NSScreen.primary else { return nil }
        if screen == primary { return icon }
        let offset = primary.frame.maxX - icon.maxX
        return CGRect(x: screen.frame.maxX - offset - icon.width, y: screen.frame.maxY - icon.height, width: icon.width, height: icon.height)
    }

    var ownWindowNumbers: Set<Int> {
        var s = Set<Int>()
        if let n = toggle.button?.window?.windowNumber { s.insert(n) }
        if let n = separator.button?.window?.windowNumber { s.insert(n) }
        return s
    }

    var ownFrames: [CGRect] { [toggleFrame, separatorFrame].compactMap { $0 } }

    /// True once AppKit has positioned both items in the bar.
    var hasRealFrames: Bool {
        guard let t = toggleFrame, let s = separatorFrame else { return false }
        return t.width > 0 && s.width > 0 && t.minY > 100 && s.minY > 100
    }

    private func updateGlyph() {
        let image: NSImage
        switch revealMode {
        case .popup: image = Glyphs.chevron(activeAppearance ? "up" : "down")
        case .sideways: image = Glyphs.chevron(isCollapsed ? "left" : "right")
        }
        toggle.button?.image = image
        toggle.button?.toolTip = revealMode == .popup
            ? "PeekBar — click to open the popup below. Extras left of this icon are hidden."
            : (isCollapsed ? "PeekBar — click to show the hidden extras in the bar" : "PeekBar — click to hide the extras again")
    }

    /// Debug: the icon as drawn.
    func toggleSnapshot() -> NSImage? { toggle.button?.snapshotImage() }

    func setActiveAppearance(_ active: Bool) {
        activeAppearance = active
        updateGlyph()
        toggle.button?.highlight(active)
    }

    func showMenu(_ menu: NSMenu) {
        toggle.menu = menu
        toggle.button?.performClick(nil)
        toggle.menu = nil
    }

    // MARK: Verification / repair

    private func scheduleVerification() {
        verificationAttempts = 0
        if CommandLine.arguments.contains("--no-repair") { return }
        for delay in [0.5, 1.5, 3.0, 5.0, 8.0, 11.0, 14.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.verifyOrdering() }
        }
    }

    private func isDrawn(_ frame: CGRect, in windows: [ExtraCatalog.RawWindow]) -> Bool {
        windows.first { abs($0.bounds.minX - frame.minX) < 1.5 && abs($0.bounds.width - frame.width) < 1.5 }?.isOnScreen ?? true
    }

    /// F-82/F-84: repair the layout when macOS restored the items in the wrong order, let an
    /// extra slip between them, parked the icon off-screen or (fresh install on an overflowing
    /// bar) under the camera housing where it is never drawn, or left a pinned extra undrawn.
    /// The items move to the left edge of the drawn cluster: nothing visible gets hidden, and
    /// the extras that were already lost under the notch become the first Pocket.
    func verifyOrdering() {
        guard verificationAttempts < 3, hasRealFrames, let tf = toggleFrame, let sf = separatorFrame,
              let screen = NSScreen.primary else { return }
        let geo = screen.geometry
        let all = ExtraCatalog.rawStatusWindows(excluding: [], ownFrames: [])
        let iconVisible = VisibilityCheck.isFullyVisible(itemFrame: tf, on: geo) && isDrawn(tf, in: all)
        let wrongOrder = sf.minX > tf.minX
        let others = ExtraCatalog.rawStatusWindows(excluding: [], ownFrames: ownFrames + (extraOwnFramesProvider?() ?? []))
        let interleaved = !wrongOrder && others.contains { $0.bounds.minX >= sf.maxX - 1 && $0.bounds.maxX <= tf.minX + 1 }
        // A pinned extra (right of the icon) that macOS does not draw is stranded: neither in
        // the bar nor in the popup.
        let pinnedUndrawn = others.contains { $0.bounds.minX >= tf.maxX - 1 && $0.bounds.minX < geo.frame.maxX && !$0.isOnScreen }
        guard !iconVisible || wrongOrder || interleaved || pinnedUndrawn else { return }
        verificationAttempts += 1
        log.warning("Repairing status items (iconVisible: \(iconVisible), wrongOrder: \(wrongOrder), interleaved: \(interleaved), stranded: \(pinnedUndrawn))")
        var togglePos: CGFloat
        if !iconVisible || pinnedUndrawn {
            let primaryHeight = screen.frame.height
            let candidates = others.filter {
                $0.isOnScreen && $0.bounds.minX > repairFloorX
                    && VisibilityCheck.isFullyVisible(itemFrame: CoordinateSpace.cocoaRect(fromCG: $0.bounds, primaryScreenHeight: primaryHeight), on: geo)
            }
            if let target = candidates.min(by: { $0.bounds.minX < $1.bounds.minX }) {
                repairFloorX = target.bounds.minX + 0.5
                togglePos = screen.frame.maxX - target.bounds.minX + 0.5
            } else {
                togglePos = 200
            }
        } else {
            togglePos = screen.frame.maxX - tf.maxX
        }
        rebuild(togglePosition: togglePos, separatorPosition: togglePos + tf.width + 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.onLayoutRepaired?() }
    }

    /// Recreates both items under the next autosave-name generation. Positions are distances
    /// from the right edge of the primary display to each item's right edge.
    private func rebuild(togglePosition: CGFloat, separatorPosition: CGFloat) {
        let wasCollapsed = isCollapsed
        let d = UserDefaults.standard
        let next = Self.generation + 1
        let toggleName = Self.name("peekbar_toggle", generation: next)
        let separatorName = Self.name("peekbar_separator", generation: next)
        d.set(togglePosition, forKey: "NSStatusItem Preferred Position \(toggleName)")
        d.set(separatorPosition, forKey: "NSStatusItem Preferred Position \(separatorName)")
        d.set(true, forKey: "NSStatusItem Visible \(toggleName)")
        d.set(true, forKey: "NSStatusItem Visible \(separatorName)")
        d.set(next, forKey: Self.generationKey)
        NSStatusBar.system.removeStatusItem(separator)
        NSStatusBar.system.removeStatusItem(toggle)
        Self.forceVisible()
        build()
        if wasCollapsed { collapse() }
    }

    // MARK: Debug

    func debugRebuild(position: CGFloat) { rebuild(togglePosition: position, separatorPosition: position + Self.iconWidth + 1) }

    func debugDefaults() -> String {
        let d = UserDefaults.standard
        let live = d.dictionaryRepresentation().filter { $0.key.contains("NSStatusItem") }.map { "\($0.key)=\($0.value)" }.sorted()
        let persisted = (d.persistentDomain(forName: AppInfo.bundleID) ?? [:]).map { "\($0.key)=\($0.value)" }.sorted()
        return "live: \(live)\npersisted(\(AppInfo.bundleID)): \(persisted)"
    }

    func verificationReport() -> String {
        guard let screen = NSScreen.primary else { return "no primary screen" }
        let geo = screen.geometry
        let t = toggleFrame.map { "\($0)" } ?? "nil"
        let s = separatorFrame.map { "\($0)" } ?? "nil"
        var vis = "n/a"
        if let tf = toggleFrame { vis = "\(VisibilityCheck.isFullyVisible(itemFrame: tf, on: geo))" }
        return "attempts=\(verificationAttempts) real=\(hasRealFrames) mode=\(mode) length=\(Int(separator.length)) toggle=\(t) separator=\(s) drawableMinX=\(drawableMinX) visible=\(vis)"
    }

    // MARK: Events

    @objc private func toggleClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            onSecondaryClick?(event)
        } else {
            onPrimaryClick?(event)
        }
    }

    @objc func mouseEntered(with event: NSEvent) {
        guard hoverEnabled else { return }
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: hoverDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.onHoverDwell?() }
        }
    }

    @objc func mouseExited(with event: NSEvent) {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }
}
