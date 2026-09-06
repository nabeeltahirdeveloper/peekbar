import Foundation

public struct WorldClock: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var timeZoneID: String
    public var label: String
    public init(id: UUID = UUID(), timeZoneID: String, label: String) {
        self.id = id; self.timeZoneID = timeZoneID; self.label = label
    }
    public var timeZone: TimeZone? { TimeZone(identifier: timeZoneID) }
}

public enum ClockFormatter {
    public static func entry(for clock: WorldClock, now: Date, local: TimeZone = .current, locale: Locale = .current, showSeconds: Bool = false) -> ClockEntryReading {
        let tz = clock.timeZone ?? local
        let time = DateFormatter()
        time.locale = locale
        time.timeZone = tz
        time.setLocalizedDateFormatFromTemplate(showSeconds ? "jms" : "jm")
        let date = DateFormatter()
        date.locale = locale
        date.timeZone = tz
        date.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return ClockEntryReading(id: clock.id, label: clock.label.isEmpty ? (clock.timeZoneID.split(separator: "/").last.map(String.init) ?? clock.timeZoneID).replacingOccurrences(of: "_", with: " ") : clock.label,
                                 time: time.string(from: now), date: date.string(from: now), offset: offsetText(tz, relativeTo: local, at: now))
    }

    /// "+5h", "−3h 30m", "same time", plus "tomorrow"/"yesterday" when the calendar day differs.
    public static func offsetText(_ tz: TimeZone, relativeTo local: TimeZone, at now: Date) -> String {
        let delta = tz.secondsFromGMT(for: now) - local.secondsFromGMT(for: now)
        var text: String
        if delta == 0 {
            text = "same time"
        } else {
            let h = abs(delta) / 3600, m = (abs(delta) % 3600) / 60
            text = (delta > 0 ? "+" : "−") + "\(h)h" + (m > 0 ? " \(m)m" : "")
        }
        var localCal = Calendar(identifier: .gregorian); localCal.timeZone = local
        var tzCal = Calendar(identifier: .gregorian); tzCal.timeZone = tz
        let a = localCal.dateComponents([.year, .month, .day], from: now)
        let b = tzCal.dateComponents([.year, .month, .day], from: now)
        let localKey = (a.year ?? 0) * 10_000 + (a.month ?? 0) * 100 + (a.day ?? 0)
        let tzKey = (b.year ?? 0) * 10_000 + (b.month ?? 0) * 100 + (b.day ?? 0)
        if tzKey > localKey { text += ", tomorrow" } else if tzKey < localKey { text += ", yesterday" }
        return text
    }
}
