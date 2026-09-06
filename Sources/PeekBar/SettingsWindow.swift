import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let contentSize = NSSize(width: 620, height: 580)

    init(settings: AppSettings, state: AppState, metrics: MetricsStore) {
        let root = SettingsRootView().environmentObject(settings).environmentObject(state).environmentObject(metrics)
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "PeekBar Settings"
        w.contentView = NSHostingView(rootView: root)
        w.isReleasedWhenClosed = false
        w.center()
        super.init(window: w)
        w.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
