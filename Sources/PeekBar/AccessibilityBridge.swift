import AppKit
import ApplicationServices

/// One entry of an app's "extras menu bar" as reported by the Accessibility API.
struct AXExtraItem {
    let element: AXUIElement
    /// Frame in the window server's top-left space.
    let frame: CGRect
    let title: String?
    let descriptionText: String?
    let pid: pid_t
}

/// Thin wrapper over the Accessibility API (SRS §11: used only to enumerate and click extras).
enum AccessibilityBridge {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private static func attribute(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, name as CFString, &value)
        return err == .success ? value : nil
    }

    private static func string(_ el: AXUIElement, _ name: String) -> String? {
        guard let v = attribute(el, name) else { return nil }
        return v as? String
    }

    private static func point(_ el: AXUIElement, _ name: String) -> CGPoint? {
        guard let v = attribute(el, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    private static func size(_ el: AXUIElement, _ name: String) -> CGSize? {
        guard let v = attribute(el, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    /// Returns the status items an application publishes, or nil when the app exposes none
    /// (or cannot be reached). Safe to call for any pid; uses a short messaging timeout.
    static func extrasMenuBarItems(pid: pid_t, timeout: Float = 0.25) -> [AXExtraItem]? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let barRef = attribute(app, "AXExtrasMenuBar"), CFGetTypeID(barRef) == AXUIElementGetTypeID() else { return nil }
        let bar = barRef as! AXUIElement
        guard let childrenRef = attribute(bar, kAXChildrenAttribute), let children = childrenRef as? [AXUIElement] else { return nil }
        var items: [AXExtraItem] = []
        for child in children {
            guard let p = point(child, kAXPositionAttribute), let s = size(child, kAXSizeAttribute) else { continue }
            items.append(AXExtraItem(
                element: child,
                frame: CGRect(origin: p, size: s),
                title: string(child, kAXTitleAttribute),
                descriptionText: string(child, kAXDescriptionAttribute),
                pid: pid
            ))
        }
        return items
    }

    static func actions(of el: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(el, &names) == .success, let arr = names as? [String] else { return [] }
        return arr
    }

    @discardableResult
    static func press(_ el: AXUIElement) -> Bool {
        AXUIElementPerformAction(el, kAXPressAction as CFString) == .success
    }

    @discardableResult
    static func showMenu(_ el: AXUIElement) -> Bool {
        AXUIElementPerformAction(el, kAXShowMenuAction as CFString) == .success
    }
}
