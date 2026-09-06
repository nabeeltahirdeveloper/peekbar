import SwiftUI
import AppKit
import PeekBarCore

/// Records a global shortcut by listening to the next key press (F-50).
struct KeyRecorder: NSViewRepresentable {
    @Binding var combo: KeyCombo
    @Binding var recording: Bool

    final class RecorderView: NSView {
        var onCombo: ((KeyCombo) -> Void)?
        var onCancel: (() -> Void)?
        var label = ""
        var isRecording = false { didSet { needsDisplay = true } }
        override var acceptsFirstResponder: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); isRecording = true }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { isRecording = false; onCancel?(); return }
            let mods = HotKeyManager.carbonModifiers(from: event.modifierFlags)
            let c = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods)
            guard c.isUsable else { NSSound.beep(); return }
            isRecording = false
            onCombo?(c)
        }
        override func resignFirstResponder() -> Bool { isRecording = false; return true }
        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
            path.fill()
            (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
            path.stroke()
            let text = isRecording ? "Type shortcut… (Esc to cancel)" : label
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
            let size = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
        }
    }

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.onCombo = { combo = $0; recording = false }
        v.onCancel = { recording = false }
        return v
    }
    func updateNSView(_ v: RecorderView, context: Context) {
        v.label = combo.displayString
        v.isRecording = recording
        v.needsDisplay = true
    }
}

struct SettingsRootView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView(selection: $state.settingsTab) {
            GeneralSettingsView().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsTab.general)
            ExtrasSettingsView().tabItem { Label("Extras", systemImage: "menubar.rectangle") }.tag(SettingsTab.extras)
            MonitoringSettingsView().tabItem { Label("Monitoring", systemImage: "gauge") }.tag(SettingsTab.monitoring)
            AlertsSettingsView().tabItem { Label("Alerts", systemImage: "bell.badge") }.tag(SettingsTab.alerts)
            PermissionsSettingsView().tabItem { Label("Permissions", systemImage: "lock.shield") }.tag(SettingsTab.permissions)
            AboutSettingsView().tabItem { Label("About", systemImage: "info.circle") }.tag(SettingsTab.about)
        }
        .frame(width: SettingsWindowController.contentSize.width, height: SettingsWindowController.contentSize.height)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var state: AppState
    @State private var recording = false
    @State private var recordingArrange = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch PeekBar at login", isOn: Binding(
                    get: { state.loginItemEnabled },
                    set: { AppDelegate.shared.setLoginItem($0) }))
                    .disabled(!LoginItem.isSupported)
                Text(state.loginItemStatus).font(.caption).foregroundStyle(.secondary)
                Toggle("Show in Dock (for debugging)", isOn: $settings.showInDock)
                HStack {
                    Text("Collapse after launch")
                    Slider(value: $settings.collapseDelay, in: 0.5...6, step: 0.5)
                    Text(String(format: "%.1f s", settings.collapseDelay)).monospacedDigit().frame(width: 44)
                }
                Text("Late-launching extras are zoned correctly when the first collapse waits a moment.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Shortcut") {
                Toggle("Global shortcut toggles the popup", isOn: $settings.hotkeyEnabled)
                HStack {
                    KeyRecorder(combo: $settings.hotkey, recording: $recording).frame(width: 220, height: 26)
                    Button("Change…") { recording = true }
                    Button("Reset") { settings.hotkey = .defaultCombo }
                }
                if state.hotkeyConflict {
                    Label("This shortcut conflicts with a system shortcut.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                } else if settings.hotkeyEnabled && !state.hotkeyRegistered {
                    Label("The shortcut could not be registered. Another app may own it.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                }
                Divider()
                Toggle("Shortcut shows pocket icons in the bar for ⌘-dragging (press again to hide)", isOn: $settings.arrangeHotkeyEnabled)
                HStack {
                    KeyRecorder(combo: $settings.arrangeHotkey, recording: $recordingArrange).frame(width: 220, height: 26)
                    Button("Change…") { recordingArrange = true }
                    Button("Reset") { settings.arrangeHotkey = .defaultArrangeCombo }
                }
                if state.arrangeHotkeyConflict {
                    Label("This shortcut conflicts with a system shortcut or the popup shortcut.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                } else if settings.arrangeHotkeyEnabled && !state.arrangeHotkeyRegistered {
                    Label("The shortcut could not be registered. Another app may own it.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                }
            }
            Section("Reveal hidden extras") {
                Picker("When I click the PeekBar icon", selection: $settings.revealMode) {
                    ForEach(RevealMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Text(settings.revealMode.summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if settings.revealMode == .sideways {
                    Text("Option-click the icon, or use the dashboard shortcut, to open the popup anyway.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Popup") {
                Toggle("Show names under tiles", isOn: $settings.showLabels)
                Picker("After activating an extra", selection: $settings.closeBehavior) {
                    ForEach(PopupCloseBehavior.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Auto-close after", selection: $settings.autoClose) {
                    ForEach(AutoCloseOption.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Live icon refresh", selection: $settings.liveRefresh) {
                    ForEach(LiveRefreshRate.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Open popup when the pointer rests on the PeekBar icon", isOn: $settings.hoverOpen)
                if settings.hoverOpen {
                    Stepper("Rest delay: \(settings.hoverDelayMs) ms", value: $settings.hoverDelayMs, in: 100...2000, step: 100)
                }
                Toggle("Refresh icons by briefly revealing extras when needed", isOn: $settings.flashRefreshEnabled)
            }
        }
        .groupedForm()
    }
}

struct ExtrasSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var state: AppState
    @State private var confirmReset = false

    private func rows(_ zone: Zone) -> [MenuBarExtra] { state.extras.filter { $0.zone == zone } }

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(Zone.allCases, id: \.self) { zone in
                    Section {
                        let items = rows(zone)
                        if items.isEmpty {
                            Text("Nothing here.").foregroundStyle(.secondary).font(.caption)
                        }
                        ForEach(items) { extra in
                            ExtraRow(extra: extra)
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(zone.title)
                            Text(zone.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !state.incompatible.isEmpty {
                    Section("Known incompatible extras") {
                        ForEach(state.incompatible) { rec in
                            VStack(alignment: .leading) {
                                Text(rec.displayName)
                                Text(rec.incompatibleReason ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Divider()
            HStack {
                Button("Arrange in Menu Bar…") { AppDelegate.shared.startArrange() }
                Button("Refresh") { AppDelegate.shared.rescanAndPublish(reason: "settings") }
                Spacer()
                if state.extras.contains(where: \.isNew) {
                    Button("Clear “New” badges") { AppDelegate.shared.dismissAllNew() }
                }
                Menu("More") {
                    Button("Export layout…") { AppDelegate.shared.exportLayout() }
                    Button("Import layout…") { AppDelegate.shared.importLayout() }
                    Divider()
                    Button("Reset all assignments…") { confirmReset = true }
                }.frame(width: 90)
            }
            .padding(10)
            if let msg = state.lastMessage {
                Text(msg).font(.caption).foregroundStyle(.secondary).padding(.bottom, 6)
            }
        }
        .alert("Reset all assignments?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { AppDelegate.shared.resetLayout() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Vault flags, “New” badges, and the incompatible list are cleared. Extras stay where they are in the menu bar.")
        }
    }
}

struct ExtraRow: View {
    @EnvironmentObject var state: AppState
    let extra: MenuBarExtra

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let img = AppDelegate.shared.capture.cachedImage(for: extra.id) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                } else if let icon = extra.appIcon {
                    Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "square.dashed").foregroundStyle(.secondary)
                }
            }.frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(extra.displayName)
                    if extra.isNew {
                        Text("New").font(.caption2.weight(.semibold)).padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.2), in: Capsule())
                    }
                    if extra.isSystemProtected {
                        Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary).help("System extra; keep it pinned.")
                    }
                }
                Text(extra.bundleID ?? "Unknown owner — grant Accessibility to identify extras").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(Zone.allCases, id: \.self) { z in
                    Button("Move to \(z.title)") { AppDelegate.shared.move(extra.id, to: z) }
                        .disabled(z == extra.zone)
                }
                if extra.isNew { Button("Dismiss “New”") { AppDelegate.shared.dismissNew(extra.id) } }
                if extra.incompatibleReason != nil { Button("Clear incompatible flag") { AppDelegate.shared.clearIncompatible(extra.id) } }
            } label: { Text(extra.zone.title) }
            .menuStyle(.borderlessButton)
            .frame(width: 90)
        }
        .padding(.vertical, 2)
    }
}

struct PermissionsSettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    title: "Screen Recording",
                    granted: state.permissions.screenRecording,
                    why: "Captures only status-item windows so tiles look like the real extras. Frames are transient and never written to disk.",
                    request: { AppDelegate.shared.requestScreenRecording() },
                    open: { SystemSettingsPane.screenRecording.open() })
                PermissionRow(
                    title: "Accessibility",
                    granted: state.permissions.accessibility,
                    why: "Forwards a click from a tile to the real extra and identifies which app owns each extra. No reading of other apps’ documents.",
                    request: { AppDelegate.shared.requestAccessibility() },
                    open: { SystemSettingsPane.accessibility.open() })
            } header: {
                Text("Why PeekBar asks")
            } footer: {
                Text("If a permission was granted to an earlier build with a different code signature, remove PeekBar from the list in System Settings and add it again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Login item") {
                HStack {
                    Text("Launch at login: \(state.loginItemStatus)")
                    Spacer()
                    Button("Open Login Items") { SystemSettingsPane.loginItems.open() }
                }
            }
            Section("Without permissions") {
                Text("Hiding still works. The popup shows a permission notice instead of icons, and tiles cannot click extras for you.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .groupedForm()
        .onAppear { state.refreshPermissions() }
    }
}

struct PermissionRow: View {
    let title: String
    let granted: Bool
    let why: String
    let request: () -> Void
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(granted ? .green : .secondary)
                Text(title).fontWeight(.semibold)
                Spacer()
                if !granted { Button("Allow…") { request() } }
                Button("System Settings") { open() }
            }
            Text(why).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct AboutSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading) {
                        Text("PeekBar").font(.title2.weight(.semibold))
                        Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
                        Text("Control Center for hidden extras. The notch never eats them.").font(.caption)
                    }
                }
            }
            Section("Privacy") {
                Text("PeekBar takes pictures of menu bar icons only, so it can show them in the popup. It uses Accessibility only to click those icons for you. Nothing is saved or sent. There is no account, no telemetry, and no network access.")
                    .font(.callout)
            }
            Section {
                Button("Show walkthrough again") { AppDelegate.shared.showOnboarding() }
                Toggle("Show debug tools", isOn: $settings.showDebugTools)
            }
            if settings.showDebugTools {
                Section("Debug") {
                    LabeledRow(label: "Collapse length", value: "\(Int(state.collapseLength)) pt")
                    LabeledRow(label: "Collapsed", value: state.isCollapsed ? "Yes" : "No")
                    LabeledRow(label: "Last capture error", value: state.lastCaptureError ?? "None")
                    HStack {
                        Button("Dump extra catalog…") { AppDelegate.shared.dumpCatalogToFile() }
                        Button("Force rescan") { AppDelegate.shared.rescanAndPublish(reason: "debug") }
                        Button("Flash refresh icons") { AppDelegate.shared.flashRefreshIcons(force: true) }
                    }
                }
            }
        }
        .groupedForm()
    }
}
