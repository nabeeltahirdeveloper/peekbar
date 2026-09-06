import AppKit
import SwiftUI
import PeekBarCore

// MARK: - Illustrations

/// Diagram of a notched menu bar with the three zones (SRS §8.1).
struct ZoneDiagram: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let barH: CGFloat = 26
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)).frame(height: barH)
                RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.85))
                    .frame(width: w * 0.16, height: barH - 6).offset(x: w * 0.42, y: 0)
                HStack(spacing: 6) {
                    Circle().fill(Color.primary.opacity(0.5)).frame(width: 10, height: 10)
                    ForEach(0..<3, id: \.self) { _ in Capsule().fill(Color.primary.opacity(0.35)).frame(width: 26, height: 8) }
                }.padding(.leading, 10).frame(height: barH)
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 2).fill(Color.orange.opacity(0.8)).frame(width: 10, height: 10) }
                    RoundedRectangle(cornerRadius: 1).fill(Color.accentColor).frame(width: 2, height: 14)
                    RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 1.5).frame(width: 16, height: 11)
                    ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(0.8)).frame(width: 10, height: 10) }
                    RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.5)).frame(width: 34, height: 9)
                }
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 10).frame(height: barH)
                VStack(spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(0..<3, id: \.self) { _ in RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.8)).frame(width: 18, height: 18) }
                    }
                    HStack(spacing: 4) {
                        ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 4).fill(Color.orange.opacity(0.5)).frame(width: 18, height: 18) }
                        RoundedRectangle(cornerRadius: 4).fill(Color.purple.opacity(0.6)).frame(width: 18, height: 18)
                    }
                }
                .padding(6)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 60).offset(y: barH + 6)
            }
        }
        .frame(height: 90)
    }
}

/// A menu bar strip with an arrow showing an icon being ⌘-dragged past the PeekBar divider.
struct DragDiagram: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)).frame(height: 26)
                HStack(spacing: 6) {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2).fill(Color.orange.opacity(0.8)).frame(width: 10, height: 10)
                    Image(systemName: "arrow.left").font(.caption.weight(.bold)).foregroundStyle(Color.accentColor)
                    RoundedRectangle(cornerRadius: 1).fill(Color.accentColor).frame(width: 2, height: 14)
                    RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 1.5).frame(width: 16, height: 11)
                    ForEach(0..<2, id: \.self) { _ in RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(0.8)).frame(width: 10, height: 10) }
                    RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(0.8)).frame(width: 10, height: 10)
                        .overlay(Text("⌘").font(.system(size: 8, weight: .bold)).foregroundStyle(.white).offset(y: -12))
                    RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.5)).frame(width: 34, height: 9)
                }.padding(.trailing, 10)
            }
            HStack(spacing: 14) {
                Label("Left of the divider: hidden (Pocket)", systemImage: "eye.slash").font(.caption)
                Label("Right of it: always visible (Pinned)", systemImage: "eye").font(.caption)
            }.foregroundStyle(.secondary)
        }
    }
}

/// Mock of the popup: tiles plus a couple of dashboard cards.
struct PopupDiagram: View {
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(0..<2, id: \.self) { i in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i == 0 ? "CPU" : "Memory").font(.system(size: 8)).foregroundStyle(.secondary)
                            Text(i == 0 ? "12%" : "61%").font(.system(size: 13, weight: .semibold))
                        }
                        Spacer()
                        Sparkline(series: [0.2, 0.3, 0.25, 0.5, 0.4, 0.6, 0.45, 0.3], range: 0...1).frame(width: 40, height: 16)
                    }
                    .padding(.horizontal, 8).frame(width: 130, height: 40)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)).frame(width: 40, height: 40)
                        .overlay(Image(systemName: ["wifi", "bolt.fill", "message.fill", "cloud.fill"][i]).font(.system(size: 14)).foregroundStyle(.secondary))
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Mock of a few widget styles in a menu bar strip.
struct WidgetDiagram: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.08)).frame(height: 28)
            HStack(spacing: 12) {
                Spacer()
                RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 1.5).frame(width: 16, height: 11)
                Sparkline(series: [0.2, 0.4, 0.3, 0.7, 0.5, 0.3, 0.6, 0.4, 0.5], range: 0...1).frame(width: 40, height: 16)
                VStack(alignment: .leading, spacing: 0) {
                    Text("↓ 1.2 M").font(.system(size: 7, weight: .semibold))
                    Text("↑ 240 K").font(.system(size: 7, weight: .semibold))
                }
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.2), lineWidth: 2.5).frame(width: 14, height: 14)
                    Circle().trim(from: 0, to: 0.6).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90)).frame(width: 14, height: 14)
                }
                Text("41°C").font(.system(size: 10, weight: .medium))
                RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.5)).frame(width: 34, height: 9)
            }.padding(.trailing, 10)
        }
    }
}

// MARK: - Walkthrough

enum WalkthroughStep: Int, CaseIterable {
    case welcome, permissions, hideAndPin, popup, dashboard, alerts, done

    var title: String {
        switch self {
        case .welcome: return "Welcome to PeekBar"
        case .permissions: return "Two permissions"
        case .hideAndPin: return "Hide and pin extras"
        case .popup: return "The popup"
        case .dashboard: return "Dashboard and widgets"
        case .alerts: return "Alerts"
        case .done: return "You’re set"
        }
    }
}

@MainActor
final class WalkthroughModel: ObservableObject {
    @Published var step: WalkthroughStep = .welcome
    @Published var startArrangingOnFinish = true
}

struct ShortcutBadge: View {
    let keys: String
    var body: some View {
        Text(keys).font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }
}

struct WalkthroughView: View {
    @ObservedObject var model: WalkthroughModel
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings
    var onFinish: (Bool) -> Void
    var onSkip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLast: Bool { model.step == .done }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Step \(model.step.rawValue + 1) of \(WalkthroughStep.allCases.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 5) {
                    ForEach(WalkthroughStep.allCases, id: \.rawValue) { s in
                        Capsule().fill(s == model.step ? Color.accentColor : Color.primary.opacity(0.15))
                            .frame(width: s == model.step ? 16 : 6, height: 6)
                    }
                }
            }
            .padding(.bottom, 10)
            Text(model.step.title).font(.title.weight(.semibold)).padding(.bottom, 12)
            Group {
                switch model.step {
                case .welcome: welcome
                case .permissions: permissions
                case .hideAndPin: hideAndPin
                case .popup: popup
                case .dashboard: dashboard
                case .alerts: alerts
                case .done: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .transition(reduceMotion ? .identity : .opacity)
            .id(model.step)
            HStack {
                Button("Skip") { onSkip() }.keyboardShortcut(.cancelAction)
                Spacer()
                if model.step != .welcome {
                    Button("Back") { move(-1) }
                }
                if isLast {
                    Button("Finish") { onFinish(model.startArrangingOnFinish) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                } else {
                    Button("Next") { move(1) }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 600, height: 540)
        .onAppear { state.refreshPermissions() }
    }

    private func move(_ delta: Int) {
        guard let next = WalkthroughStep(rawValue: model.step.rawValue + delta) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { model.step = next }
        if next == .permissions { state.refreshPermissions() }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A cleaner menu bar, with every extra one click away, never lost under the notch.")
                .foregroundStyle(.secondary)
            ZoneDiagram()
            HStack(alignment: .top, spacing: 14) {
                ZoneCard(color: .green, zone: .pinned)
                ZoneCard(color: .orange, zone: .pocket)
                ZoneCard(color: .purple, zone: .vault)
            }
            Text("PeekBar keeps your menu bar short. Instead of stretching hidden icons sideways under the camera housing, it shows them in a Control Center–style popup, together with live system readings if you want them.")
                .font(.callout)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PeekBar takes pictures of menu bar icons only, so it can show them in the popup. It uses Accessibility only to click those icons for you. Nothing is saved or sent.")
                .font(.callout)
            VStack(alignment: .leading, spacing: 10) {
                PermissionRow(title: "Screen Recording", granted: state.permissions.screenRecording,
                              why: "Draws the real icons on the popup tiles. Frames are transient and never written to disk.",
                              request: { AppDelegate.shared.requestScreenRecording() }, open: { SystemSettingsPane.screenRecording.open() })
                PermissionRow(title: "Accessibility", granted: state.permissions.accessibility,
                              why: "Lets a tile click the real extra, and identifies which app owns each icon.",
                              request: { AppDelegate.shared.requestAccessibility() }, open: { SystemSettingsPane.accessibility.open() })
            }
            .padding(12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            Text("If macOS keeps asking after you allowed one, quit and reopen PeekBar once. You can also skip this: hiding still works, and the popup will show a reminder instead of icons.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Check again") { state.refreshPermissions() }.controlSize(.small)
        }
    }

    private var hideAndPin: some View {
        VStack(alignment: .leading, spacing: 14) {
            DragDiagram()
            step("1", "Hold ⌘ and drag any menu bar icon.", "PeekBar opens up while you drag and shows a divider line next to its icon.")
            step("2", "Drop it left of the divider to hide it.", "It becomes a tile in the popup. Drop it right of the divider to keep it in the bar.")
            step("3", "Drag a tile out of the popup onto the menu bar to pin it again.", "PeekBar performs the ⌘-drag for you.")
            HStack(spacing: 10) {
                Text("Arrange mode shows everything at once:").font(.caption).foregroundStyle(.secondary)
                ShortcutBadge(keys: settings.arrangeHotkey.displayString)
                Button("Try Arrange mode now") { AppDelegate.shared.startArrange() }.controlSize(.small)
            }
            Text("Extras you almost never need can be moved to the Vault in Settings ▸ Extras. They stay hidden even from the popup, unless you Option-click the PeekBar icon.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var popup: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                PopupDiagram()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) { Text("Open it with a click on the PeekBar icon or").font(.callout); ShortcutBadge(keys: settings.hotkey.displayString) }
                    Text("• Click a tile: the extra’s own menu opens, just like clicking it in the bar.").font(.callout)
                    Text("• Right-click a tile: forwarded as a right-click.").font(.callout)
                    Text("• Start typing to search when you have many extras.").font(.callout)
                    Text("• Arrow keys move, Return activates, Esc closes.").font(.callout)
                    Text("• Option-click the icon to include Vault extras.").font(.callout)
                }
            }
            HStack {
                Button("Open the popup now") { AppDelegate.shared.openPopup(includeVault: false) }.controlSize(.small)
                Text("The popup can also close itself after a few seconds; see Settings ▸ General.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Live CPU, memory, disk, network, battery, GPU, sensor, Bluetooth and clock readings, in the popup and optionally in the menu bar.")
                .font(.callout)
            WidgetDiagram()
            HStack(spacing: 6) {
                Text("Dashboard shortcut:").font(.callout)
                ShortcutBadge(keys: settings.dashboardHotkey.displayString)
                Text("Click a card for details.").font(.callout).foregroundStyle(.secondary)
            }
            step("•", "Choose modules in Settings ▸ Monitoring.", "Readings are only sampled while something shows them, so an idle PeekBar costs nothing.")
            step("•", "Tick “Menu bar” on a module to pin it as a widget.", "Right-click a widget to change its style, colour it by load, or remove it. ⌘-drag to reorder.")
            Button("Open Monitoring settings") { AppDelegate.shared.openSettings(tab: .monitoring) }.controlSize(.small)
        }
    }

    private var alerts: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge").font(.system(size: 34)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("CPU load above 90%").font(.callout.weight(.semibold))
                    Text("94% for 30 s").font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
            Text("Add rules in Settings ▸ Alerts: a reading, above or below a threshold, for how long. PeekBar posts a notification when it stays past the line, clears it when things return to normal, and repeats at most every five minutes.")
                .font(.callout)
            Text("macOS will ask once whether PeekBar may send notifications.").font(.caption).foregroundStyle(.secondary)
            Button("Open Alerts settings") { AppDelegate.shared.openSettings(tab: .alerts) }.controlSize(.small)
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Everything lives behind the PeekBar icon in the menu bar. Right-click it for Arrange mode, the dashboard, and Settings.")
                .font(.callout)
            VStack(alignment: .leading, spacing: 8) {
                shortcutRow(settings.hotkey.displayString, "Show or hide the popup")
                shortcutRow(settings.arrangeHotkey.displayString, "Arrange mode: reveal everything to ⌘-drag")
                shortcutRow(settings.dashboardHotkey.displayString, "Open the dashboard")
                shortcutRow("⌥ click", "Popup including Vault extras")
            }
            .padding(12)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            Toggle("Start in Arrange mode now so I can choose what to hide", isOn: $model.startArrangingOnFinish)
            Text("You can reopen this walkthrough any time from the PeekBar menu or Settings ▸ About.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func step(_ n: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n).font(.callout.weight(.bold)).foregroundStyle(Color.accentColor).frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func shortcutRow(_ keys: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            ShortcutBadge(keys: keys).frame(width: 70, alignment: .leading)
            Text(text).font(.callout)
        }
    }
}

struct ZoneCard: View {
    let color: Color
    let zone: Zone
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.8)).frame(width: 12, height: 12)
                Text(zone.title).fontWeight(.semibold)
            }
            Text(zone.summary).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Window

@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let onSkip: () -> Void
    private var finished = false
    let model = WalkthroughModel()

    init(state: AppState, settings: AppSettings, onArrange: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.onSkip = onSkip
        let m = model
        let root = WalkthroughView(model: m, onFinish: { startArranging in
            if startArranging { onArrange() } else { onSkip() }
        }, onSkip: onSkip)
            .environmentObject(state)
            .environmentObject(settings)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 540),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "PeekBar Walkthrough"
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

    /// Marks the flow as handled so closing the window afterwards does not re-run the skip path.
    func finish() { finished = true; close() }

    func windowWillClose(_ notification: Notification) {
        guard !finished else { return }
        finished = true
        onSkip()
    }
}
