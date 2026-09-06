import SwiftUI
import PeekBarCore

struct AlertsSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var state: AppState
    @EnvironmentObject var metrics: MetricsStore

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: state.notificationAuthorized ? "checkmark.circle.fill" : "bell.slash").foregroundStyle(state.notificationAuthorized ? .green : .secondary)
                    Text(state.notificationAuthorized ? "Notifications allowed" : "Notifications not allowed yet")
                    Spacer()
                    if !state.notificationAuthorized { Button("Allow…") { AppDelegate.shared.requestNotifications() } }
                    Button("System Settings") { SystemSettingsPane.notifications.open() }
                    Button("Send test") { AppDelegate.shared.sendTestNotification() }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Alerts fire when a reading stays past its threshold for the chosen time, clear once it comes back, and repeat at most every 5 minutes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                if settings.alertRules.isEmpty {
                    Text("No rules yet.").foregroundStyle(.secondary)
                }
                ForEach(settings.alertRules) { rule in
                    AlertRuleRow(rule: binding(for: rule), onDelete: { settings.alertRules.removeAll { $0.id == rule.id } })
                }
                Button("Add rule") { settings.alertRules.append(AlertRule.defaultRule.withNewID()) }
            } header: {
                Text("Rules")
            }
        }
        .groupedForm()
        .onAppear { AppDelegate.shared.refreshNotificationStatus() }
    }

    private func binding(for rule: AlertRule) -> Binding<AlertRule> {
        Binding(
            get: { settings.alertRules.first { $0.id == rule.id } ?? rule },
            set: { new in
                if let i = settings.alertRules.firstIndex(where: { $0.id == rule.id }) { settings.alertRules[i] = new }
            })
    }
}

extension AlertRule {
    func withNewID() -> AlertRule { var r = self; r.id = UUID(); return r }
}

struct AlertRuleRow: View {
    @Binding var rule: AlertRule
    var onDelete: () -> Void
    @EnvironmentObject var metrics: MetricsStore

    private var thresholdUnit: String {
        if rule.metric.isFraction { return "%" }
        if rule.metric.metric == "temperature" { return metrics.temperatureUnit == .celsius ? "°C" : "°F" }
        return "MB/s"
    }

    /// Threshold shown in user units; stored as fraction / °C / bytes per second.
    private var displayThreshold: Binding<Double> {
        Binding(
            get: {
                if rule.metric.isFraction { return (rule.threshold * 100).rounded() }
                if rule.metric.metric == "temperature" { return metrics.temperatureUnit == .celsius ? rule.threshold : rule.threshold * 9 / 5 + 32 }
                return rule.threshold / 1_000_000
            },
            set: { v in
                if rule.metric.isFraction { rule.threshold = min(1, max(0, v / 100)) }
                else if rule.metric.metric == "temperature" { rule.threshold = metrics.temperatureUnit == .celsius ? v : (v - 32) * 5 / 9 }
                else { rule.threshold = max(0, v) * 1_000_000 }
                rule.hysteresis = AlertRule.defaultHysteresis(for: rule.metric, threshold: rule.threshold)
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("", isOn: $rule.enabled).labelsHidden()
                Picker("", selection: $rule.metric) {
                    ForEach(MetricKey.alertable, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 170)
                .onChange(of: rule.metric) { m in
                    rule.threshold = m.isFraction ? 0.9 : (m.metric == "temperature" ? 90 : 50_000_000)
                    rule.hysteresis = AlertRule.defaultHysteresis(for: m, threshold: rule.threshold)
                }
                Picker("", selection: $rule.comparator) {
                    ForEach(AlertComparator.allCases, id: \.self) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 90)
                TextField("", value: displayThreshold, format: .number).frame(width: 60).multilineTextAlignment(.trailing)
                Text(thresholdUnit).foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "minus.circle") }.buttonStyle(.plain)
            }
            HStack {
                Text("for").foregroundStyle(.secondary)
                Picker("", selection: $rule.duration) {
                    Text("immediately").tag(0.0)
                    Text("10 seconds").tag(10.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("5 minutes").tag(300.0)
                }.labelsHidden().frame(width: 130)
                if metrics.isAlertActive(rule.id) {
                    Label("Active", systemImage: "bell.fill").font(.caption).foregroundStyle(.orange)
                }
            }
            .padding(.leading, 30)
        }
    }
}
