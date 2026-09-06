import AppKit
import SwiftUI
import PeekBarCore

struct ArrangeHUDView: View {
    var overflowWarning: Bool
    var dividerHidden: Bool = false
    var shortcutHint: String = ""
    var onDone: () -> Void
    var onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.and.right").foregroundStyle(.secondary)
                Text("⌘-drag extras across the PeekBar divider").fontWeight(.semibold)
                Spacer()
                Text(shortcutHint).font(.caption).foregroundStyle(.secondary)
            }
            Text("Left of the dashed edge on the PeekBar icon: Pocket (hidden, shown in the popup). Right of it: Pinned (always visible). You can also drag a tile out of the popup onto the bar to pin it.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if dividerHidden {
                Label("The PeekBar icon is under the camera housing right now, so its edge cannot be seen. Drop extras well to the left of the visible icons to hide them, or use the popup and Settings instead.", systemImage: "eye.slash")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if overflowWarning {
                Label("Some extras will not fit right of the camera housing while expanded. Anything under the notch cannot be dragged.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Arrange in Settings list instead") { onSettings() }
                Spacer()
                Button("Done") { onDone() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 420)
        .background(VisualEffectBackground(material: .hudWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.12)))
    }
}

/// Arrange mode (F-40..F-42): the only mode allowed to use sideways geometry.
@MainActor
final class ArrangeController {
    private var panel: NSPanel?
    private(set) var isActive = false
    private var overflow = false
    private var dividerHidden = false
    private var screen: NSScreen?
    var shortcutHint = ""
    var onDone: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    func setDividerHidden(_ hidden: Bool) {
        guard isActive, hidden != dividerHidden, let screen else { return }
        dividerHidden = hidden
        begin(overflow: overflow, on: screen)
    }

    func begin(overflow: Bool, on screen: NSScreen) {
        isActive = true
        self.overflow = overflow
        self.screen = screen
        let p = panel ?? NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 140),
                                 styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = ArrangeHUDView(overflowWarning: overflow, dividerHidden: dividerHidden, shortcutHint: shortcutHint,
                                  onDone: { [weak self] in self?.end() },
                                  onSettings: { [weak self] in self?.end(); self?.onOpenSettings?() })
        let host = NSHostingView(rootView: view)
        p.contentView = host
        let size = host.fittingSize
        let geo = screen.geometry
        let x = geo.frame.midX - size.width / 2
        let y = geo.menuBarBottom - 16 - size.height
        p.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        p.orderFrontRegardless()
        panel = p
    }

    func end() {
        guard isActive else { return }
        isActive = false
        dividerHidden = false
        panel?.orderOut(nil)
        onDone?()
    }
}
