import SwiftUI
import AppKit
import PeekBarCore

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

/// Floating preview that follows the cursor while a tile is dragged out of the popup.
@MainActor
final class DragPreviewWindow {
    private let window: NSWindow
    init(image: NSImage?, size: CGSize) {
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .popUpMenu
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        let v = NSImageView(frame: NSRect(origin: .zero, size: size))
        v.imageScaling = .scaleProportionallyUpOrDown
        v.image = image
        v.alphaValue = 0.85
        window.contentView = v
    }
    func move(to p: NSPoint, validDrop: Bool) {
        window.setFrameOrigin(NSPoint(x: p.x - window.frame.width / 2, y: p.y - window.frame.height / 2))
        window.contentView?.alphaValue = validDrop ? 1.0 : 0.45
        if !window.isVisible { window.orderFrontRegardless() }
    }

    /// A drop counts when it lands on the menu bar band (plus a little slack below it).
    static func isValidDrop(_ p: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(p, $0.frame, false) }) else { return false }
        return p.y >= screen.geometry.menuBarBottom - 30
    }
    func close() { window.orderOut(nil) }
}

/// Transparent NSView overlay so tiles can distinguish left, right, and modified clicks, and
/// can be dragged out of the popup (a drop on the menu bar pins the extra there).
struct ClickCatcher: NSViewRepresentable {
    var onLeft: (NSEvent) -> Void
    var onRight: (NSEvent) -> Void
    var onDrop: ((NSPoint) -> Void)?
    var dragImage: NSImage?

    final class View: NSView {
        var onLeft: ((NSEvent) -> Void)?
        var onRight: ((NSEvent) -> Void)?
        var onDrop: ((NSPoint) -> Void)?
        var dragImage: NSImage?
        private var downPoint: NSPoint?
        private var preview: DragPreviewWindow?

        override func mouseDown(with event: NSEvent) {
            if event.modifierFlags.contains(.control) { onRight?(event); return }
            downPoint = NSEvent.mouseLocation
        }
        override func mouseDragged(with event: NSEvent) {
            guard let start = downPoint else { return }
            let now = NSEvent.mouseLocation
            if preview == nil, hypot(now.x - start.x, now.y - start.y) > 6 {
                preview = DragPreviewWindow(image: dragImage, size: CGSize(width: 36, height: 28))
                NSCursor.closedHand.push()
            }
            preview?.move(to: now, validDrop: DragPreviewWindow.isValidDrop(now))
        }
        override func mouseUp(with event: NSEvent) {
            defer { downPoint = nil }
            if let p = preview {
                p.close()
                preview = nil
                NSCursor.pop()
                onDrop?(NSEvent.mouseLocation)
            } else if downPoint != nil {
                onLeft?(event)
            }
        }
        override func rightMouseDown(with event: NSEvent) { onRight?(event) }
        override var acceptsFirstResponder: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }

    func makeNSView(context: Context) -> View {
        let v = View()
        update(v)
        return v
    }
    func updateNSView(_ v: View, context: Context) { update(v) }
    private func update(_ v: View) {
        v.onLeft = onLeft
        v.onRight = onRight
        v.onDrop = onDrop
        v.dragImage = dragImage
    }
}

struct TileView: View {
    let tile: TileItem
    let state: TileState
    let focused: Bool
    let showLabel: Bool
    let onActivate: (Bool) -> Void
    let onDismissNew: () -> Void
    let onDrop: (NSPoint) -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.16 : 0.07))
                iconView
                    .frame(width: 40, height: 28)
                overlay
                if tile.isNew {
                    VStack {
                        HStack {
                            Spacer()
                            Circle().fill(Color.accentColor).frame(width: 8, height: 8)
                                .padding(5)
                                .onTapGesture { onDismissNew() }
                                .help("New extra — click to dismiss")
                        }
                        Spacer()
                    }
                }
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(focused ? Color.accentColor : Color.clear, lineWidth: 2)
            }
            .frame(width: PopupLayout.tileSize, height: PopupLayout.tileSize)
            .overlay(ClickCatcher(onLeft: { _ in onActivate(false) }, onRight: { _ in onActivate(true) },
                                  onDrop: { onDrop($0) }, dragImage: tile.image ?? tile.fallbackIcon))
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            if showLabel {
                Text(tile.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: PopupLayout.tileSize + 6, height: PopupLayout.labelHeight - 3)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Activates this menu bar extra. Drag it onto the menu bar to pin it.")
        .help(tile.name)
    }

    @ViewBuilder private var iconView: some View {
        if let img = tile.image, tile.isTemplate {
            Image(nsImage: img).resizable().renderingMode(.template).interpolation(.high).aspectRatio(contentMode: .fit)
                .foregroundStyle(.primary)
        } else if let img = tile.image {
            Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        } else if let icon = tile.fallbackIcon {
            Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).frame(width: 26, height: 26)
        } else {
            Image(systemName: "square.dashed").font(.title2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var overlay: some View {
        switch state {
        case .idle: EmptyView()
        case .busy:
            ProgressView().controlSize(.small).padding(4)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        case .error(let msg):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.title3).help(msg)
        case .coachMark:
            Image(systemName: "hand.raised.fill").foregroundStyle(.orange).font(.title3)
                .help("Accessibility permission is needed to click extras.")
        }
    }
}

struct PopupView: View {
    @ObservedObject var model: PopupModel
    var onActivate: (ExtraID, Bool) -> Void
    var onDismissNew: (ExtraID) -> Void
    var onDrop: (ExtraID, NSPoint) -> Void
    var onArrange: () -> Void
    var onOpenScreenRecording: () -> Void
    var onRequestScreenRecording: () -> Void
    var onOpenDetail: (ModuleID) -> Void = { _ in }
    var onBack: () -> Void = {}
    var onMonitoringSettings: () -> Void = {}
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch model.page {
            case .home: homePage
            case .dashboard: DashboardView(modules: model.dashboardModules, onOpenDetail: onOpenDetail)
            case .detail(let id): ModuleDetailView(module: id, onBack: onBack, onSettings: onMonitoringSettings)
            }
        }
        .transition(reduceMotion ? .identity : .opacity)
        .padding(PopupLayout.padding)
        .background(VisualEffectBackground(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(contrast == .increased ? 0.5 : 0.12), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("PeekBar")
    }

    private var hasDashboardOnHome: Bool { model.dashboardCardsOnHome > 0 }

    @ViewBuilder private var dashboardBlock: some View {
        DashboardView(modules: model.dashboardModules, onOpenDetail: onOpenDetail)
    }

    private var homePage: some View {
        VStack(spacing: PopupLayout.spacing) {
            if hasDashboardOnHome && model.dashboardPlacement == .top { dashboardBlock }
            if model.content == .tiles && model.showSearch {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search extras", text: $model.query)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            if let first = model.filtered.first { onActivate(first.id, false) }
                        }
                }
                .padding(.horizontal, 8)
                .frame(height: PopupLayout.searchFieldHeight - 8)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            switch model.content {
            case .screenRecordingNeeded where hasDashboardOnHome:
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.dashed.badge.record").foregroundStyle(.secondary)
                    Text("Screen Recording is needed to show hidden extras").font(.caption)
                    Spacer()
                    Button("Allow…") { onRequestScreenRecording() }.controlSize(.small)
                }
                .frame(height: PopupLayout.emptyFooterHeight)
            case .empty where hasDashboardOnHome:
                HStack(spacing: 8) {
                    Text("No pocket extras yet").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Arrange extras") { onArrange() }.controlSize(.small)
                }
                .frame(height: PopupLayout.emptyFooterHeight)
            case .screenRecordingNeeded:
                VStack(spacing: 8) {
                    Image(systemName: "rectangle.dashed.badge.record").font(.title).foregroundStyle(.secondary)
                    Text("Screen Recording is needed to show icons")
                        .font(.callout.weight(.semibold))
                    Text("PeekBar only captures menu bar icons so it can draw them here. Nothing is saved or sent.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    HStack {
                        Button("Allow…") { onRequestScreenRecording() }
                        Button("Open System Settings") { onOpenScreenRecording() }
                    }.controlSize(.small)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                VStack(spacing: 8) {
                    Text("No pocket extras yet").font(.callout.weight(.semibold))
                    Text("⌘-drag extras left of the PeekBar icon to hide them.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Arrange extras") { onArrange() }.controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .tiles:
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(PopupLayout.tileSize), spacing: PopupLayout.spacing), count: max(1, model.columns)),
                              spacing: PopupLayout.spacing) {
                        ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, tile in
                            TileView(
                                tile: tile,
                                state: model.state(for: tile.id),
                                focused: model.focusedIndex == index,
                                showLabel: model.showLabels,
                                onActivate: { right in onActivate(tile.id, right) },
                                onDismissNew: { onDismissNew(tile.id) },
                                onDrop: { onDrop(tile.id, $0) }
                            )
                            .id(tile.id)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
            if hasDashboardOnHome && model.dashboardPlacement == .bottom { dashboardBlock }
        }
    }
}
