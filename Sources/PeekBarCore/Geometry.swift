import Foundation
import CoreGraphics

/// Conversions between the window server's top-left-origin global space (CGWindowList, AX,
/// CGEvent) and AppKit's bottom-left-origin space (NSScreen, NSWindow).
public enum CoordinateSpace {
    public static func cocoaRect(fromCG rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func cgRect(fromCocoa rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func cgPoint(fromCocoa p: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: primaryScreenHeight - p.y)
    }
}

/// Everything the positioner needs to know about a display. Built from NSScreen in the app,
/// constructed by hand in tests.
public struct ScreenGeometry: Equatable, Sendable {
    /// Full frame in Cocoa coordinates.
    public var frame: CGRect
    /// Frame minus menu bar and Dock, in Cocoa coordinates.
    public var visibleFrame: CGRect
    /// `NSScreen.safeAreaInsets.top`; > 0 only on displays with a camera housing.
    public var safeAreaTop: CGFloat
    /// The camera housing rect in Cocoa coordinates, if any.
    public var notch: CGRect?
    /// `NSStatusBar.system.thickness`.
    public var statusBarThickness: CGFloat

    public init(frame: CGRect, visibleFrame: CGRect, safeAreaTop: CGFloat, notch: CGRect?, statusBarThickness: CGFloat = 22) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaTop = safeAreaTop
        self.notch = notch
        self.statusBarThickness = statusBarThickness
    }

    public var hasNotch: Bool { notch != nil && safeAreaTop > 0 }

    /// Height of the menu bar band at the top of this display. On notched displays this is the
    /// safe-area inset (the full housing height). If the bar is auto-hidden, fall back to the
    /// status bar thickness so the popup still clears the bar once it slides in.
    public var menuBarBandHeight: CGFloat {
        if safeAreaTop > 0 { return safeAreaTop }
        let fromVisible = frame.maxY - visibleFrame.maxY
        return fromVisible > 0 ? fromVisible : statusBarThickness + 2
    }

    /// Cocoa y of the bottom edge of the menu bar band (F-14).
    public var menuBarBottom: CGFloat { frame.maxY - menuBarBandHeight }

    /// Usable width for status items right of the notch, or the whole width when there is none.
    public var statusAreaWidth: CGFloat {
        if let n = notch { return frame.maxX - n.maxX }
        return frame.width
    }
}

/// Popup placement rules (SRS §7.3, F-14, F-15).
public enum PopupPositioner {
    public static let gap: CGFloat = 8
    public static let margin: CGFloat = 8

    /// Largest height the popup may take on this display before it scrolls internally.
    public static func maxHeight(on screen: ScreenGeometry) -> CGFloat {
        let available = screen.menuBarBottom - gap - screen.visibleFrame.minY - margin
        return max(120, min(available, screen.frame.height * 0.6)).rounded(.down)
    }

    /// Frame (Cocoa coordinates) for a popup of `size`, right-aligned to `anchorMaxX`, directly
    /// below the menu bar band, clamped to stay fully on the display.
    public static func frame(anchorMaxX: CGFloat, size: CGSize, on screen: ScreenGeometry) -> CGRect {
        let height = min(size.height, maxHeight(on: screen))
        let width = min(size.width, screen.frame.width - 2 * margin)
        var x = anchorMaxX - width
        let minX = screen.frame.minX + margin
        let maxX = screen.frame.maxX - margin - width
        x = max(minX, min(x, maxX))
        let top = screen.menuBarBottom - gap
        let y = top - height
        return CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }

    /// Mirrors a status item anchor from the display that owns its window to another display.
    /// Menu bar items sit at the same distance from the right edge on every display.
    public static func mirroredAnchorMaxX(anchorMaxX: CGFloat, from source: ScreenGeometry, to target: ScreenGeometry) -> CGFloat {
        let offsetFromRight = source.frame.maxX - anchorMaxX
        return target.frame.maxX - offsetFromRight
    }
}

/// Does a status item window overlap the camera housing or fall off the display? (F-14, §7.4)
public enum VisibilityCheck {
    public static func isFullyVisible(itemFrame: CGRect, on screen: ScreenGeometry) -> Bool {
        guard itemFrame.minX >= screen.frame.minX - 0.5, itemFrame.maxX <= screen.frame.maxX + 0.5 else { return false }
        if let notch = screen.notch {
            let band = CGRect(x: notch.minX, y: screen.frame.minY, width: notch.width, height: screen.frame.height)
            if itemFrame.intersects(band) { return false }
        }
        return true
    }
}

/// Arrange-mode overflow warning (F-42).
public enum NotchFit {
    /// True when the given item widths cannot all be drawn to the right of the notch.
    public static func overflows(itemWidths: [CGFloat], availableWidth: CGFloat, spacing: CGFloat = 0) -> Bool {
        let total = itemWidths.reduce(0, +) + spacing * CGFloat(max(0, itemWidths.count - 1))
        return total > availableWidth
    }
}

/// "Targeted show" math (SRS §7.4, §12): change the collapse length so that one hidden extra,
/// or the PeekBar item's own left edge, lands at a chosen x without expanding the whole bar.
/// The PeekBar item is anchored at its right edge, so shortening it by Δ shifts every hidden
/// extra right by Δ.
public enum RevealMath {
    /// macOS stops drawing status items this close to the camera housing.
    public static let notchMargin: CGFloat = 44

    /// Leftmost x at which the window server still draws status items on this display.
    public static func drawableMinX(on screen: ScreenGeometry) -> CGFloat {
        if let n = screen.notch { return n.maxX + notchMargin }
        return screen.frame.midX
    }

    /// Length that brings a hidden extra currently at `itemMinX` to `targetMinX`.
    public static func length(current: CGFloat, itemMinX: CGFloat, targetMinX: CGFloat, minLength: CGFloat) -> CGFloat {
        max(minLength, (current - (targetMinX - itemMinX)).rounded())
    }

    /// Length that puts the item's own left edge at `x`, given its fixed right edge.
    public static func length(rightEdge: CGFloat, leftEdgeAt x: CGFloat, minLength: CGFloat) -> CGFloat {
        max(minLength, (rightEdge - x).rounded())
    }
}
