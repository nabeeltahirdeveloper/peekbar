import Foundation
import CoreGraphics

/// Raw facts about a discovered status-item window used to derive a stable identity.
public struct IdentitySource: Equatable, Sendable {
    public var bundleID: String?
    public var title: String?
    public var windowName: String?
    public var width: CGFloat
    public var minX: CGFloat

    public init(bundleID: String? = nil, title: String? = nil, windowName: String? = nil, width: CGFloat, minX: CGFloat) {
        self.bundleID = bundleID
        self.title = title
        self.windowName = windowName
        self.width = width
        self.minX = minX
    }
}

public enum ExtraIdentity {
    /// The key before duplicate disambiguation.
    public static func baseKey(_ s: IdentitySource) -> String {
        let bundle = s.bundleID?.trimmingCharacters(in: .whitespaces) ?? ""
        let title = (s.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let window = (s.windowName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !bundle.isEmpty {
            if !title.isEmpty { return "\(bundle)|\(title)" }
            if !window.isEmpty { return "\(bundle)|\(window)" }
            return "\(bundle)|item"
        }
        if !window.isEmpty { return "unknown|\(window)" }
        return "unknown|w\(Int(s.width.rounded()))"
    }

    /// Produces one id per source, in the same order as the input. Sources whose base key
    /// collides get an ordinal suffix assigned in left-to-right (minX) order so the result is
    /// deterministic for a given bar layout.
    public static func makeIDs(for sources: [IdentitySource]) -> [ExtraID] {
        let keys = sources.map(baseKey)
        var groups: [String: [Int]] = [:]
        for (i, k) in keys.enumerated() { groups[k, default: []].append(i) }
        var result = [ExtraID](repeating: ExtraID(""), count: sources.count)
        for (key, indices) in groups {
            if indices.count == 1 {
                result[indices[0]] = ExtraID(key)
                continue
            }
            let ordered = indices.sorted { sources[$0].minX < sources[$1].minX }
            for (n, idx) in ordered.enumerated() {
                result[idx] = ExtraID("\(key)#\(n + 1)")
            }
        }
        return result
    }

    /// Best human-readable name for an extra.
    public static func displayName(bundleID: String?, appName: String?, title: String?, windowName: String?, siblingCount: Int) -> String {
        let app = (appName ?? "").trimmingCharacters(in: .whitespaces)
        let t = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let w = (windowName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = !t.isEmpty ? t : (w.isEmpty || w.hasPrefix("Item-") ? "" : w)
        if !app.isEmpty {
            if siblingCount > 1 && !detail.isEmpty && detail.caseInsensitiveCompare(app) != .orderedSame {
                return "\(app) · \(detail)"
            }
            return app
        }
        if !detail.isEmpty { return detail }
        if let b = bundleID, !b.isEmpty { return b }
        return "Unknown extra"
    }
}
