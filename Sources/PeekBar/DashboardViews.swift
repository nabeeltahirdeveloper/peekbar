import SwiftUI
import PeekBarCore

// MARK: - Sparkline

struct Sparkline: View {
    var series: [Double]
    var range: ClosedRange<Double>?
    var tint: Color = .accentColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { ctx, size in
            guard series.count >= 2 else { return }
            let lo = range?.lowerBound ?? (series.min() ?? 0)
            let hiRaw = range?.upperBound ?? (series.max() ?? 1)
            let hi = hiRaw > lo ? hiRaw : lo + 1
            let stepX = size.width / CGFloat(series.count - 1)
            func point(_ i: Int) -> CGPoint {
                let y = 1 - (series[i] - lo) / (hi - lo)
                return CGPoint(x: CGFloat(i) * stepX, y: CGFloat(y) * (size.height - 2) + 1)
            }
            var line = Path()
            line.move(to: point(0))
            for i in 1..<series.count { line.addLine(to: point(i)) }
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .color(tint.opacity(0.18)))
            ctx.stroke(line, with: .color(tint), lineWidth: 1.2)
        }
        .accessibilityHidden(true)
        .animation(reduceMotion ? nil : .linear(duration: 0.2), value: series.count)
    }
}

// MARK: - Card text

struct CardText {
    var primary: String
    var secondary: String
    var series: [Double]
    var range: ClosedRange<Double>?
    var unavailable: Bool = false

    @MainActor
    static func make(_ module: ModuleID, store: MetricsStore) -> CardText {
        let unit = store.temperatureUnit
        let bytes = store.byteStyle
        guard let reading = store.reading(module) else {
            return CardText(primary: "…", secondary: "Waiting for data", series: [], range: nil)
        }
        switch reading {
        case .unavailable(let reason):
            return CardText(primary: "—", secondary: reason, series: [], range: nil, unavailable: true)
        case .cpu(let c):
            var s = String(format: "user %.0f%% · sys %.0f%%", c.user * 100, c.system * 100)
            if let p = c.performanceCores, let e = c.efficiencyCores { s = String(format: "P %.0f%% · E %.0f%%", p * 100, e * 100) }
            if let t = c.temperature { s += " · " + UnitFormatter.temperature(t, unit: unit) }
            return CardText(primary: UnitFormatter.percent(c.total), secondary: s, series: store.history.values(for: .cpuTotal, last: 60), range: 0...1)
        case .ram(let r):
            return CardText(primary: UnitFormatter.percent(r.usedFraction),
                            secondary: "\(UnitFormatter.bytes(r.used, style: bytes)) of \(UnitFormatter.bytes(r.total, style: bytes))",
                            series: store.history.values(for: .ramUsed, last: 60), range: 0...1)
        case .disk(let d):
            let p = d.primary
            return CardText(primary: p.map { UnitFormatter.percent($0.usedFraction) } ?? "—",
                            secondary: "↓ \(UnitFormatter.compactRate(bytesPerSecond: d.readRate))/s  ↑ \(UnitFormatter.compactRate(bytesPerSecond: d.writeRate))/s",
                            series: store.history.values(for: .diskRead, last: 60), range: nil)
        case .network(let n):
            return CardText(primary: "↓ \(UnitFormatter.compactRate(bytesPerSecond: n.downloadRate))/s",
                            secondary: "↑ \(UnitFormatter.compactRate(bytesPerSecond: n.uploadRate))/s · \(n.interfaceName ?? "—")",
                            series: store.history.values(for: .networkDown, last: 60), range: nil)
        case .battery(let b):
            var s = b.isCharging ? "Charging" : (b.isPluggedIn ? "Plugged in" : "On battery")
            if let m = b.timeToEmptyMinutes, !b.isPluggedIn { s += " · \(UnitFormatter.duration(minutes: m)) left" }
            if let m = b.timeToFullMinutes, b.isCharging { s += " · \(UnitFormatter.duration(minutes: m)) to full" }
            return CardText(primary: UnitFormatter.percent(b.level), secondary: s, series: store.history.values(for: .batteryLevel, last: 60), range: 0...1)
        case .gpu(let g):
            var s = g.name
            if let t = g.temperature { s += " · " + UnitFormatter.temperature(t, unit: unit) }
            return CardText(primary: g.utilization.map { UnitFormatter.percent($0) } ?? "—", secondary: s,
                            series: store.history.values(for: .gpuUtilization, last: 60), range: 0...1)
        case .sensors(let s):
            let cpu = s.cpuTemperature.map { UnitFormatter.temperature($0, unit: unit) } ?? "—"
            var sec: [String] = []
            if let g = s.gpuTemperature { sec.append("GPU " + UnitFormatter.temperature(g, unit: unit)) }
            if let f = s.fanSpeeds.first { sec.append(UnitFormatter.rpm(f.value)) }
            if let p = s.totalPower { sec.append(UnitFormatter.power(watts: p)) }
            return CardText(primary: cpu, secondary: sec.isEmpty ? "\(s.sensors.count) sensors" : sec.joined(separator: " · "),
                            series: store.history.values(for: .cpuTemperature, last: 60), range: nil)
        case .bluetooth(let b):
            let connected = b.devices.filter(\.isConnected)
            let first = connected.first { $0.battery != nil || $0.batteryLeft != nil }
            var sec = "No battery info"
            if let f = first {
                let level = f.battery ?? f.batteryLeft ?? 0
                sec = "\(f.name) \(UnitFormatter.percent(level))"
            }
            return CardText(primary: "\(connected.count)", secondary: connected.isEmpty ? "No devices connected" : sec, series: [], range: nil)
        case .clock(let c):
            let e = c.entries.first
            return CardText(primary: e?.time ?? "—", secondary: e.map { "\($0.label) · \($0.offset)" } ?? "Add clocks in Settings", series: [], range: nil)
        }
    }
}

// MARK: - Cards

struct ModuleCard: View {
    @EnvironmentObject var store: MetricsStore
    let module: ModuleID
    let onOpen: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let text = CardText.make(module, store: store)
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.16 : 0.07))
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: module.symbolName).font(.caption).foregroundStyle(.secondary)
                        Text(module.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(text.primary)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(text.unavailable ? .secondary : .primary)
                        .lineLimit(1)
                    Text(text.secondary).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                }
                Spacer(minLength: 2)
                if !text.series.isEmpty {
                    Sparkline(series: text.series, range: text.range).frame(width: 56, height: 22)
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(width: PopupLayout.cardWidth, height: PopupLayout.cardHeight)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { onOpen() }
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .help(text.unavailable ? text.secondary : "\(module.title): \(text.primary), \(text.secondary)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(module.title)
        .accessibilityValue("\(text.primary), \(text.secondary)")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows details")
    }
}

struct DashboardView: View {
    let modules: [ModuleID]
    let onOpenDetail: (ModuleID) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(PopupLayout.cardWidth), spacing: PopupLayout.spacing), count: PopupLayout.cardColumns),
                  spacing: PopupLayout.spacing) {
            ForEach(modules) { m in
                ModuleCard(module: m) { onOpenDetail(m) }
            }
        }
    }
}

// MARK: - Detail

enum DetailHeights {
    static func height(for module: ModuleID) -> CGFloat {
        switch module {
        case .cpu: return 330
        case .ram: return 300
        case .disk: return 260
        case .network: return 240
        case .battery: return 230
        case .gpu: return 200
        case .sensors: return 380
        case .bluetooth: return 240
        case .clock: return 240
        }
    }
}

struct BarRow: View {
    var label: String
    var fraction: Double
    var value: String
    var tint: Color = .accentColor
    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).frame(width: 74, alignment: .leading).lineLimit(1)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(tint).frame(width: max(2, g.size.width * CGFloat(min(1, max(0, fraction)))))
                }
            }.frame(height: 8)
            Text(value).font(.caption.monospacedDigit()).frame(width: 62, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

struct KeyValueRow: View {
    var key: String
    var value: String
    var body: some View {
        HStack {
            Text(key).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }
}

struct ProcessRows: View {
    var title: String
    var processes: [ProcessUsage]
    var format: (Double) -> String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if processes.isEmpty {
                Text("Collecting…").font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(processes) { p in
                HStack {
                    Text(p.name).font(.caption).lineLimit(1)
                    Spacer()
                    Text(format(p.value)).font(.caption.monospacedDigit())
                }
            }
        }
    }
}

struct ModuleDetailView: View {
    @EnvironmentObject var store: MetricsStore
    let module: ModuleID
    let onBack: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: PopupLayout.spacing) {
            HStack(spacing: 6) {
                Button(action: onBack) { Image(systemName: "chevron.left") }.buttonStyle(.plain).help("Back (Esc)")
                Image(systemName: module.symbolName).foregroundStyle(.secondary)
                Text(module.title).font(.headline)
                Spacer()
                Button(action: onSettings) { Image(systemName: "gearshape") }.buttonStyle(.plain).help("Monitoring settings")
            }
            .frame(height: PopupLayout.navBarHeight)
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) { body(for: store.reading(module)) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
            }
        }
        .frame(width: PopupLayout.fullWidth - PopupLayout.padding * 2)
    }

    @ViewBuilder private func body(for reading: ModuleReading?) -> some View {
        let unit = store.temperatureUnit
        let bytes = store.byteStyle
        switch reading {
        case nil:
            Text("Waiting for data…").font(.caption).foregroundStyle(.secondary)
        case .unavailable(let reason):
            Label("Not available on this Mac", systemImage: "minus.circle").font(.callout)
            Text(reason).font(.caption).foregroundStyle(.secondary)
        case .cpu(let c):
            Sparkline(series: store.history.values(for: .cpuTotal), range: 0...1).frame(height: 50)
            BarRow(label: "Total", fraction: c.total, value: UnitFormatter.percent(c.total))
            BarRow(label: "User", fraction: c.user, value: UnitFormatter.percent(c.user), tint: .blue)
            BarRow(label: "System", fraction: c.system, value: UnitFormatter.percent(c.system), tint: .orange)
            if let p = c.performanceCores, let e = c.efficiencyCores {
                BarRow(label: "P-cores", fraction: p, value: UnitFormatter.percent(p))
                BarRow(label: "E-cores", fraction: e, value: UnitFormatter.percent(e))
            }
            HStack(spacing: 3) {
                ForEach(Array(c.perCore.enumerated()), id: \.offset) { _, v in
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 1.5).fill(v > 0.8 ? Color.red : (v > 0.5 ? Color.orange : Color.accentColor))
                            .frame(height: max(2, 28 * CGFloat(v)))
                    }.frame(height: 28)
                }
            }.frame(height: 28).accessibilityLabel("Per-core load")
            KeyValueRow(key: "Load average", value: c.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: "  "))
            if let t = c.temperature { KeyValueRow(key: "Temperature", value: UnitFormatter.temperature(t, unit: unit)) }
            ProcessRows(title: "Top processes", processes: c.topProcesses) { UnitFormatter.percent($0) }
        case .ram(let r):
            Sparkline(series: store.history.values(for: .ramUsed), range: 0...1).frame(height: 50)
            BarRow(label: "Used", fraction: r.usedFraction, value: UnitFormatter.bytes(r.used, style: bytes))
            BarRow(label: "App", fraction: Double(r.app) / Double(max(1, r.total)), value: UnitFormatter.bytes(r.app, style: bytes), tint: .blue)
            BarRow(label: "Wired", fraction: Double(r.wired) / Double(max(1, r.total)), value: UnitFormatter.bytes(r.wired, style: bytes), tint: .orange)
            BarRow(label: "Compressed", fraction: Double(r.compressed) / Double(max(1, r.total)), value: UnitFormatter.bytes(r.compressed, style: bytes), tint: .purple)
            BarRow(label: "Cached", fraction: Double(r.cached) / Double(max(1, r.total)), value: UnitFormatter.bytes(r.cached, style: bytes), tint: .gray)
            KeyValueRow(key: "Pressure", value: r.pressure.rawValue.capitalized)
            KeyValueRow(key: "Swap", value: "\(UnitFormatter.bytes(r.swapUsed, style: bytes)) of \(UnitFormatter.bytes(r.swapTotal, style: bytes))")
            ProcessRows(title: "Top apps", processes: r.topProcesses) { UnitFormatter.bytes($0, style: bytes) }
        case .disk(let d):
            ForEach(d.volumes) { v in
                BarRow(label: v.name, fraction: v.usedFraction, value: UnitFormatter.bytes(v.available, style: bytes) + " free")
            }
            KeyValueRow(key: "Read", value: UnitFormatter.rate(bytesPerSecond: d.readRate))
            KeyValueRow(key: "Write", value: UnitFormatter.rate(bytesPerSecond: d.writeRate))
            Sparkline(series: store.history.values(for: .diskRead), tint: .blue).frame(height: 30)
            Sparkline(series: store.history.values(for: .diskWrite), tint: .orange).frame(height: 30)
        case .network(let n):
            Sparkline(series: store.history.values(for: .networkDown), tint: .blue).frame(height: 40)
            Sparkline(series: store.history.values(for: .networkUp), tint: .orange).frame(height: 40)
            KeyValueRow(key: "Download", value: UnitFormatter.rate(bytesPerSecond: n.downloadRate))
            KeyValueRow(key: "Upload", value: UnitFormatter.rate(bytesPerSecond: n.uploadRate))
            KeyValueRow(key: "Interface", value: [n.interfaceName, n.interfaceType].compactMap { $0 }.joined(separator: " · "))
            if let ip = n.localIPv4 { KeyValueRow(key: "Local IPv4", value: ip) }
            if let ip = n.localIPv6 { KeyValueRow(key: "Local IPv6", value: ip) }
            if let ip = n.publicIP { KeyValueRow(key: "Public IP", value: ip) }
            KeyValueRow(key: "Session totals", value: "↓ \(UnitFormatter.bytes(n.totalDownloaded, style: bytes))  ↑ \(UnitFormatter.bytes(n.totalUploaded, style: bytes))")
        case .battery(let b):
            BarRow(label: "Charge", fraction: b.level, value: UnitFormatter.percent(b.level), tint: b.level < 0.2 ? .red : .green)
            KeyValueRow(key: "State", value: b.isCharging ? "Charging" : (b.isPluggedIn ? "Plugged in, not charging" : "On battery"))
            if let m = b.timeToEmptyMinutes { KeyValueRow(key: "Time remaining", value: UnitFormatter.duration(minutes: m)) }
            if let m = b.timeToFullMinutes { KeyValueRow(key: "Time to full", value: UnitFormatter.duration(minutes: m)) }
            if let h = b.health { KeyValueRow(key: "Health", value: UnitFormatter.percent(h)) }
            if let c = b.cycleCount { KeyValueRow(key: "Cycle count", value: "\(c)") }
            if let t = b.temperature { KeyValueRow(key: "Temperature", value: UnitFormatter.temperature(t, unit: unit, decimals: 1)) }
            if let w = b.wattage { KeyValueRow(key: b.isCharging ? "Charging at" : "Power draw", value: UnitFormatter.power(watts: w)) }
            if let a = b.adapterDescription { KeyValueRow(key: "Adapter", value: a) }
        case .gpu(let g):
            KeyValueRow(key: "GPU", value: g.name)
            if let u = g.utilization { BarRow(label: "Utilization", fraction: u, value: UnitFormatter.percent(u)) }
            if let u = g.rendererUtilization { BarRow(label: "Renderer", fraction: u, value: UnitFormatter.percent(u), tint: .blue) }
            if let u = g.tilerUtilization { BarRow(label: "Tiler", fraction: u, value: UnitFormatter.percent(u), tint: .orange) }
            if let used = g.memoryUsed {
                KeyValueRow(key: "Memory in use", value: UnitFormatter.bytes(used, style: bytes) + (g.memoryTotal.map { " of " + UnitFormatter.bytes($0, style: bytes) } ?? ""))
            }
            if let t = g.temperature { KeyValueRow(key: "Temperature", value: UnitFormatter.temperature(t, unit: unit)) }
            Sparkline(series: store.history.values(for: .gpuUtilization), range: 0...1).frame(height: 40)
        case .sensors(let s):
            ForEach(SensorGroup.allCases, id: \.self) { group in
                let items = s.sensors.filter { $0.group == group }
                if !items.isEmpty {
                    Text(group.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(items) { sensor in
                        KeyValueRow(key: sensor.label, value: format(sensor, unit: unit))
                    }
                }
            }
        case .bluetooth(let b):
            if b.devices.isEmpty { Text("No paired devices").font(.caption).foregroundStyle(.secondary) }
            ForEach(b.devices) { d in
                HStack {
                    Circle().fill(d.isConnected ? Color.green : Color.gray.opacity(0.4)).frame(width: 7, height: 7)
                    Text(d.name).font(.caption).lineLimit(1)
                    Spacer()
                    Text(batteryText(d)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        case .clock(let c):
            if c.entries.isEmpty { Text("Add time zones in Settings ▸ Monitoring").font(.caption).foregroundStyle(.secondary) }
            ForEach(c.entries) { e in
                HStack {
                    VStack(alignment: .leading) {
                        Text(e.label).font(.caption)
                        Text(e.date).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(e.time).font(.callout.monospacedDigit())
                        Text(e.offset).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func format(_ s: SensorReading, unit: TemperatureUnit) -> String {
        switch s.unit {
        case .celsius: return UnitFormatter.temperature(s.value, unit: unit)
        case .rpm: return UnitFormatter.rpm(s.value)
        case .watts: return UnitFormatter.power(watts: s.value)
        case .volts: return String(format: "%.2f V", s.value)
        case .amps: return String(format: "%.2f A", s.value)
        case .raw: return String(format: "%.1f", s.value)
        }
    }

    private func batteryText(_ d: BluetoothDevice) -> String {
        var parts: [String] = []
        if let l = d.batteryLeft { parts.append("L " + UnitFormatter.percent(l)) }
        if let r = d.batteryRight { parts.append("R " + UnitFormatter.percent(r)) }
        if let c = d.batteryCase { parts.append("Case " + UnitFormatter.percent(c)) }
        if parts.isEmpty, let b = d.battery { parts.append(UnitFormatter.percent(b)) }
        return parts.isEmpty ? (d.isConnected ? "Connected" : "Not connected") : parts.joined(separator: " · ")
    }
}
