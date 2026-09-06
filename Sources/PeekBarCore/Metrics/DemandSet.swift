import Foundation

/// Which modules must sample right now. Sampling is demand-driven so idle CPU stays ≈ 0.
public struct DemandSet: Equatable, Sendable {
    public var popupModules: Set<ModuleID>
    public var widgetModules: Set<ModuleID>
    public var alertModules: Set<ModuleID>
    public var enabledModules: Set<ModuleID>

    public init(popupModules: Set<ModuleID> = [], widgetModules: Set<ModuleID> = [], alertModules: Set<ModuleID> = [], enabledModules: Set<ModuleID> = Set(ModuleID.allCases)) {
        self.popupModules = popupModules; self.widgetModules = widgetModules
        self.alertModules = alertModules; self.enabledModules = enabledModules
    }

    public var demanded: Set<ModuleID> {
        (popupModules.union(widgetModules).union(alertModules)).intersection(enabledModules)
    }

    /// Alert-only modules can sample slowly.
    public static let alertOnlyMinimumInterval: TimeInterval = 5

    public func interval(for id: ModuleID, base: TimeInterval) -> TimeInterval {
        if popupModules.contains(id) || widgetModules.contains(id) { return base }
        return max(base, Self.alertOnlyMinimumInterval)
    }
}
