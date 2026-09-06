import Foundation
import CoreGraphics

/// Derives zones from geometry. Zones are physical: an extra left of the PeekBar separator is
/// hidden by the collapse; an extra right of it is pinned. The vault is a flag on hidden extras.
public enum ZoneResolver {
    /// An item is hidden when its left edge is left of the separator's left edge. This holds in
    /// both the collapsed and expanded states because the separator grows to the right.
    public static func isHidden(itemMinX: CGFloat, separatorMinX: CGFloat) -> Bool {
        itemMinX < separatorMinX
    }

    /// Combines physical placement with the stored intent.
    public static func effectiveZone(physicallyHidden: Bool, storedZone: Zone?) -> Zone {
        guard physicallyHidden else { return .pinned }
        return storedZone == .vault ? .vault : .pocket
    }

    /// Decides what to store after observing an extra.
    /// - A pinned extra always stores `.pinned` (physical truth wins).
    /// - A hidden extra keeps `.vault` if the user asked for it, otherwise `.pocket`.
    public static func storedZone(afterObserving physicallyHidden: Bool, previous: Zone?) -> Zone {
        effectiveZone(physicallyHidden: physicallyHidden, storedZone: previous)
    }
}
