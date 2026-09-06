import AppKit
import Combine
import PeekBarCore

enum TileState: Equatable {
    case idle
    case busy
    case error(String)
    case coachMark
}

struct TileItem: Identifiable, Equatable {
    static func == (a: TileItem, b: TileItem) -> Bool { a.id == b.id && a.name == b.name && a.isNew == b.isNew && a.imageVersion == b.imageVersion }
    let id: ExtraID
    var name: String
    var image: NSImage?
    var fallbackIcon: NSImage?
    var imageVersion: Int
    var isTemplate: Bool = false
    var isNew: Bool
    var zone: Zone
}

enum PopupContent: Equatable {
    case tiles
    case empty
    case screenRecordingNeeded
}

/// Which page the single panel shows (extras home, the monitoring dashboard, or one module).
enum PopupPage: Equatable {
    case home
    case dashboard
    case detail(ModuleID)
}

@MainActor
final class PopupModel: ObservableObject {
    @Published var tiles: [TileItem] = []
    @Published var query: String = ""
    @Published var userTyped = false
    @Published var focusedIndex: Int?
    @Published var includeVault = false
    @Published var content: PopupContent = .empty
    @Published var showLabels = false
    @Published var columns = 3
    @Published var tileStates: [ExtraID: TileState] = [:]
    @Published var searchThreshold = 12
    @Published var page: PopupPage = .home
    @Published var dashboardModules: [ModuleID] = []
    @Published var dashboardPlacement: DashboardPlacement = .top

    /// Cards shown on the home page (none when the dashboard lives on its own page).
    var dashboardCardsOnHome: Int { dashboardPlacement == .hidden ? 0 : dashboardModules.count }

    var showSearch: Bool {
        PopupLayout.shouldShowSearch(tileCount: tiles.count, threshold: searchThreshold, userTyped: userTyped)
    }

    var filtered: [TileItem] {
        tiles.filter { SearchFilter.matches(name: $0.name, query: query) }
    }

    func state(for id: ExtraID) -> TileState { tileStates[id] ?? .idle }
}
