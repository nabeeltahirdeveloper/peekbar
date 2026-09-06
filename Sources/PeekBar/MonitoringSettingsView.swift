import SwiftUI
import PeekBarCore

struct MonitoringSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var state: AppState
    @EnvironmentObject var metrics: MetricsStore
    @State private var recording = false

    var body: some View {
        Form {
            Section("Dashboard") {
                Picker("Show readings", selection: $settings.dashboardPlacement) {
                    ForEach(DashboardPlacement.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Shortcut opens the dashboard", isOn: $settings.dashboardHotkeyEnabled)
                HStack {
                    KeyRecorder(combo: $settings.dashboardHotkey, recording: $recording).frame(width: 220, height: 26)
                    Button("Change…") { recording = true }
                    Button("Reset") { settings.dashboardHotkey = .defaultDashboardCombo }
                }
                if state.dashboardHotkeyConflict {
                    Label("This shortcut conflicts with a system shortcut or another PeekBar shortcut.", systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption)
                }
                Button("Open dashboard now") { AppDelegate.shared.openDashboard(detail: nil) }
            }
            Section {
                ForEach(ModuleID.allCases) { id in
                    ModuleSettingsRow(module: id)
                }
            } header: {
                Text("Modules")
            } footer: {
                Text("Readings are only sampled while they are shown, so disabled and unseen modules cost nothing. Hold ⌘ and drag widgets in the menu bar to reorder them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sampling and units") {
                Picker("Sampling interval", selection: $settings.samplingInterval) {
                    Text("Every second").tag(1.0)
                    Text("Every 2 seconds").tag(2.0)
                    Text("Every 5 seconds").tag(5.0)
                }
                Picker("Temperature", selection: $settings.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Sizes", selection: $settings.byteStyle) {
                    ForEach(ByteStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            }
            Section("Clocks") {
                ForEach(Array(settings.clocks.enumerated()), id: \.element.id) { index, clock in
                    HStack {
                        TextField("Label", text: Binding(get: { clock.label }, set: { v in var c = settings.clocks; c[index].label = v; settings.clocks = c }))
                            .frame(width: 120)
                        Picker("", selection: Binding(get: { clock.timeZoneID }, set: { v in var c = settings.clocks; c[index].timeZoneID = v; settings.clocks = c })) {
                            ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                        }.labelsHidden()
                        Button(role: .destructive) { var c = settings.clocks; c.remove(at: index); settings.clocks = c } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                    }
                }
                Button("Add clock") { settings.clocks.append(WorldClock(timeZoneID: TimeZone.current.identifier, label: "")) }
                    .disabled(settings.clocks.count >= 8)
            }
            Section("Network") {
                Picker("Interface", selection: Binding(
                    get: { settings.networkInterface ?? "" },
                    set: { settings.networkInterface = $0.isEmpty ? nil : $0 })) {
                    Text("Active interface").tag("")
                    ForEach(NetworkModule.interfaceNames(), id: \.self) { Text($0).tag($0) }
                }
                Toggle("Look up public IP address", isOn: $settings.publicIPEnabled)
                Text("Off by default. When on, PeekBar asks api.ipify.org for your address every 10 minutes. This is PeekBar’s only network request.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .groupedForm()
    }
}

struct ModuleSettingsRow: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var state: AppState
    @EnvironmentObject var metrics: MetricsStore
    let module: ModuleID

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: module.symbolName).frame(width: 20).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.title)
                if let reason = metrics.reading(module)?.unavailableReason {
                    Text(reason).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if settings.isModuleEnabled(module) || settings.widgetConfig(for: module) != nil {
                Toggle("Menu bar", isOn: Binding(get: { settings.widgetConfig(for: module) != nil }, set: { settings.setWidget(module, enabled: $0) }))
                    .toggleStyle(.checkbox)
                    .help("Show this module as its own widget in the menu bar")
                if let c = settings.widgetConfig(for: module) {
                    Picker("", selection: Binding(get: { c.style }, set: { var n = c; n.style = $0; settings.setWidgetConfig(n) })) {
                        ForEach(WidgetLayoutMath.allowedStyles(for: module)) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 120)
                }
            }
            Toggle("", isOn: Binding(get: { settings.isModuleEnabled(module) }, set: { settings.setModule(module, enabled: $0) }))
                .labelsHidden()
        }
        if let c = settings.widgetConfig(for: module) {
            HStack(spacing: 12) {
                Toggle("Label", isOn: Binding(get: { c.showLabel }, set: { var n = c; n.showLabel = $0; settings.setWidgetConfig(n) })).toggleStyle(.checkbox)
                Toggle("Color by load", isOn: Binding(get: { c.colorMode == .utilization }, set: { var n = c; n.colorMode = $0 ? .utilization : .monochrome; settings.setWidgetConfig(n) })).toggleStyle(.checkbox)
                if c.style == .lineChart {
                    Picker("Width", selection: Binding(get: { c.chartWidth }, set: { var n = c; n.chartWidth = $0; settings.setWidgetConfig(n) })) {
                        ForEach(WidgetLayoutMath.chartWidths, id: \.self) { Text("\($0) pt").tag($0) }
                    }.frame(width: 120)
                }
                if c.placement == .hiddenByUser {
                    Button("Move back next to PeekBar") {
                        var n = c; n.placement = .pinned; settings.setWidgetConfig(n)
                        AppDelegate.shared.widgets.moveBack(module)
                    }.controlSize(.small)
                }
                if let w = state.widgetWarnings[module] {
                    Label(w, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .padding(.leading, 30)
        }
    }
}
