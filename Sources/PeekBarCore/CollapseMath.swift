import Foundation
import CoreGraphics

/// Collapse geometry (SRS F-80, F-81, §12).
public enum CollapseMath {
    /// The system caps NSStatusItem.length at 10,000 points.
    public static let systemCap: CGFloat = 10_000
    /// Never go below this so a tiny or misreported screen cannot leave extras visible.
    public static let floor: CGFloat = 1_000
    /// Separator length while expanded / in Arrange mode.
    public static let expandedSeparatorLength: CGFloat = 10

    /// Length that pushes every extra left of the separator off the widest attached screen.
    public static func collapseLength(screenWidths: [CGFloat], cap: CGFloat = systemCap) -> CGFloat {
        let widest = screenWidths.max() ?? 0
        return min(cap, max(floor, widest.rounded(.up)))
    }
}
