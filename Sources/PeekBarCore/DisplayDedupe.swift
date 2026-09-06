import Foundation
import CoreGraphics

/// Minimal facts about a status-item window, for duplicate detection.
public struct StatusWindowStub: Equatable, Sendable {
    public var id: UInt32
    public var minX: CGFloat
    public var width: CGFloat
    public var name: String?
    public var isOnScreen: Bool
    public init(id: UInt32, minX: CGFloat, width: CGFloat, name: String? = nil, isOnScreen: Bool) {
        self.id = id; self.minX = minX; self.width = width; self.name = name; self.isOnScreen = isOnScreen
    }
}

/// A non-primary display whose menu bar shares the primary display's band (same top edge).
public struct SecondaryDisplay: Equatable, Sendable {
    public var minX: CGFloat
    public var maxX: CGFloat
    /// `secondary.maxX - primary.maxX`: menu bar items repeat at this x offset.
    public var delta: CGFloat
    public init(minX: CGFloat, maxX: CGFloat, delta: CGFloat) { self.minX = minX; self.maxX = maxX; self.delta = delta }
}

/// macOS draws every status item once per display. The primary display's windows are the
/// canonical ones; copies on other displays must not become tiles (they cannot be clicked).
public enum DisplayDedupe {
    public static func copies(in windows: [StatusWindowStub], secondaries: [SecondaryDisplay]) -> Set<UInt32> {
        var out: Set<UInt32> = []
        guard !secondaries.isEmpty else { return out }
        for w in windows {
            for s in secondaries where s.delta != 0 {
                // Drawn inside a secondary display: a hidden primary item is never on screen, so
                // an on-screen window inside that display's range is that display's copy.
                if w.isOnScreen, w.minX >= s.minX - 0.5, w.minX + w.width <= s.maxX + 0.5 {
                    out.insert(w.id); break
                }
                // Off-screen copies (hidden items) sit exactly `delta` away from their primary.
                let twin = windows.first { p in
                    p.id != w.id && abs(p.minX - (w.minX - s.delta)) <= 1.5 && abs(p.width - w.width) <= 1.5
                        && (p.name == nil || w.name == nil || p.name == w.name)
                }
                if twin != nil { out.insert(w.id); break }
            }
        }
        return out
    }
}
