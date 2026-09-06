import AppKit
import UserNotifications
import PeekBarCore

/// Posts threshold alerts as macOS notifications (SRS: no other network/telemetry).
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    var onOpenModule: ((ModuleID) -> Void)?
    var temperatureUnit: TemperatureUnit = .celsius
    private(set) var authorized = false
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier != nil ? UNUserNotificationCenter.current() : nil
    }

    override init() {
        super.init()
        center?.delegate = self
        refreshStatus()
    }

    func refreshStatus(_ completion: ((Bool) -> Void)? = nil) {
        guard let center else { completion?(false); return }
        center.getNotificationSettings { s in
            let ok = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
            Task { @MainActor in self.authorized = ok; completion?(ok) }
        }
    }

    func requestAuthorization(_ completion: ((Bool) -> Void)? = nil) {
        guard let center else { completion?(false); return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in self.authorized = granted; completion?(granted) }
        }
    }

    static func valueText(_ key: MetricKey, _ value: Double, unit: TemperatureUnit) -> String {
        if key.isFraction { return UnitFormatter.percent(value) }
        if key.metric == "temperature" { return UnitFormatter.temperature(value, unit: unit) }
        if key.module == .network || key.module == .disk { return UnitFormatter.rate(bytesPerSecond: value) }
        return String(format: "%.1f", value)
    }

    func title(for event: AlertEvent) -> String {
        let r = event.rule
        let threshold = Self.valueText(r.metric, r.threshold, unit: temperatureUnit)
        return event.isFired ? "\(r.metric.title) \(r.comparator.title) \(threshold)" : "\(r.metric.title) back to normal"
    }

    func body(for event: AlertEvent) -> String {
        let r = event.rule
        let v = Self.valueText(r.metric, event.value, unit: temperatureUnit)
        if event.isFired {
            return r.duration > 0 ? "\(v) for \(Int(r.duration)) s" : v
        }
        return "Now \(v)"
    }

    func post(_ event: AlertEvent) {
        guard let center else { return }
        let id = "peekbar.alert.\(event.rule.id.uuidString)"
        if !event.isFired {
            center.removeDeliveredNotifications(withIdentifiers: [id])
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title(for: event)
        content.body = body(for: event)
        content.sound = .default
        content.categoryIdentifier = "peekbar.alert"
        content.userInfo = ["module": event.rule.metric.module.rawValue]
        content.interruptionLevel = .timeSensitive
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func postTest(module: ModuleID) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = "PeekBar test alert"
        content.body = "Notifications are working. Click to open the \(module.title) page."
        content.sound = .default
        content.userInfo = ["module": module.rawValue]
        center.add(UNNotificationRequest(identifier: "peekbar.alert.test", content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let raw = response.notification.request.content.userInfo["module"] as? String
        let module = raw.flatMap(ModuleID.init(rawValue:))
        await MainActor.run { if let m = module { self.onOpenModule?(m) } }
    }
}
