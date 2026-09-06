import Foundation
import CoreGraphics

/// Grid metrics for the popup (SRS §7.3, §10). Kept in the core so sizing is testable.
public struct PopupLayout: Equatable, Sendable {
    public static let tileSize: CGFloat = 56
    public static let labelHeight: CGFloat = 16
    public static let spacing: CGFloat = 8
    public static let padding: CGFloat = 12
    public static let maxColumns = 6
    public static let minColumns = 3
    public static let searchFieldHeight: CGFloat = 34
    public static let headerHeight: CGFloat = 0
    public static let emptyStateSize = CGSize(width: 300, height: 120)

    public var columns: Int
    public var rows: Int
    public var size: CGSize

    public init(columns: Int, rows: Int, size: CGSize) {
        self.columns = columns
        self.rows = rows
        self.size = size
    }

    // Dashboard (monitoring) metrics.
    public static let cardHeight: CGFloat = 64
    public static let cardColumns = 2
    public static let navBarHeight: CGFloat = 28
    public static let emptyFooterHeight: CGFloat = 40
    public static var fullWidth: CGFloat { padding * 2 + CGFloat(maxColumns) * tileSize + CGFloat(maxColumns - 1) * spacing }
    public static var cardWidth: CGFloat { (fullWidth - padding * 2 - CGFloat(cardColumns - 1) * spacing) / CGFloat(cardColumns) }

    public static func dashboardBlockHeight(cards: Int) -> CGFloat {
        guard cards > 0 else { return 0 }
        let rows = Int((Double(cards) / Double(cardColumns)).rounded(.up))
        return CGFloat(rows) * cardHeight + CGFloat(rows - 1) * spacing
    }

    public static func compute(tileCount: Int, showLabels: Bool, showSearch: Bool, maxHeight: CGFloat) -> PopupLayout {
        compute(tileCount: tileCount, showLabels: showLabels, showSearch: showSearch, dashboardCards: 0, detailHeight: nil, maxHeight: maxHeight)
    }

    /// Full sizing: extras grid plus an optional dashboard block, or a detail page.
    public static func compute(tileCount: Int, showLabels: Bool, showSearch: Bool, dashboardCards: Int, detailHeight: CGFloat?, maxHeight: CGFloat) -> PopupLayout {
        if let detail = detailHeight {
            let height = min(maxHeight, padding * 2 + navBarHeight + spacing + detail)
            return PopupLayout(columns: 0, rows: 0, size: CGSize(width: fullWidth, height: height))
        }
        if dashboardCards <= 0 {
            if tileCount <= 0 {
                return PopupLayout(columns: 0, rows: 0, size: emptyStateSize)
            }
            let columns = max(minColumns, min(maxColumns, tileCount))
            let rows = Int((Double(tileCount) / Double(columns)).rounded(.up))
            let tileH = tileSize + (showLabels ? labelHeight : 0)
            let width = padding * 2 + CGFloat(columns) * tileSize + CGFloat(columns - 1) * spacing
            var height = padding * 2 + CGFloat(rows) * tileH + CGFloat(rows - 1) * spacing
            if showSearch { height += searchFieldHeight + spacing }
            height = min(height, maxHeight)
            return PopupLayout(columns: columns, rows: rows, size: CGSize(width: width, height: height))
        }
        // Dashboard present: always full width, block stacked with the grid.
        var height = padding * 2 + dashboardBlockHeight(cards: dashboardCards)
        var rows = 0
        if tileCount > 0 {
            rows = Int((Double(tileCount) / Double(maxColumns)).rounded(.up))
            let tileH = tileSize + (showLabels ? labelHeight : 0)
            height += spacing + CGFloat(rows) * tileH + CGFloat(rows - 1) * spacing
            if showSearch { height += searchFieldHeight + spacing }
        } else {
            height += spacing + emptyFooterHeight
        }
        return PopupLayout(columns: maxColumns, rows: rows, size: CGSize(width: fullWidth, height: min(height, maxHeight)))
    }

    /// F-18: search appears when the pocket count exceeds the threshold.
    public static func shouldShowSearch(tileCount: Int, threshold: Int, userTyped: Bool) -> Bool {
        userTyped || tileCount > threshold
    }
}

/// Keyboard navigation of the tile grid (F-19).
public enum GridNavigation {
    public enum Direction { case left, right, up, down }

    public static func move(from index: Int?, direction: Direction, count: Int, columns: Int) -> Int? {
        guard count > 0, columns > 0 else { return nil }
        guard let i = index else { return 0 }
        switch direction {
        case .left: return max(0, i - 1)
        case .right: return min(count - 1, i + 1)
        case .up: return i - columns >= 0 ? i - columns : i
        case .down: return i + columns < count ? i + columns : i
        }
    }
}

/// F-18 search matching.
public enum SearchFilter {
    public static func matches(name: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return true }
        let haystack = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        for token in q.split(separator: " ") {
            let t = token.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            if !haystack.contains(t) { return false }
        }
        return true
    }
}
