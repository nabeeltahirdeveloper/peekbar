import Foundation

/// The three conceptual zones of the menu bar (SRS §7.1).
public enum Zone: String, Codable, CaseIterable, Sendable {
    /// Always drawn in the real menu bar. Never appears in the popup.
    case pinned
    /// Hidden from the real bar while collapsed. Appears in the popup.
    case pocket
    /// Always hidden. Only shown when the user asks for the vault.
    case vault

    public var title: String {
        switch self {
        case .pinned: return "Pinned"
        case .pocket: return "Pocket"
        case .vault: return "Vault"
        }
    }

    public var summary: String {
        switch self {
        case .pinned: return "Always visible in the menu bar."
        case .pocket: return "Hidden from the bar. Shown in the popup."
        case .vault: return "Hidden from the bar and from the default popup."
        }
    }

    /// Whether extras in this zone are physically hidden by the separator.
    public var isHiddenInBar: Bool { self != .pinned }
}

/// A stable identity for a menu bar extra (SRS F-04): bundle id + title/signature,
/// never an ephemeral window id.
public struct ExtraID: Hashable, Codable, Sendable, CustomStringConvertible, Comparable {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public var description: String { raw }
    public static func < (lhs: ExtraID, rhs: ExtraID) -> Bool { lhs.raw < rhs.raw }
}
