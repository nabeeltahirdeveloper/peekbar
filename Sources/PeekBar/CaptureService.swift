import AppKit
import ScreenCaptureKit
import PeekBarCore

/// Window-scoped capture of status item windows (SRS §11, §12 CaptureService).
/// Frames live in memory only and are never written to disk.
@MainActor
final class CaptureService {
    private(set) var cache: [ExtraID: NSImage] = [:]
    /// Extras whose captured icon is monochrome (a template image in the bar). They are drawn
    /// tinted with the popup's label color so they match the current appearance.
    private(set) var templateIDs: Set<ExtraID> = []
    private(set) var lastError: String?
    private(set) var lastSuccess: Date?
    /// `SCShareableContent` cache; typed loosely so the class loads on macOS 12.
    private var shareable: Any?
    private var shareableFetched: Date = .distantPast

    /// Screen Recording status. `CGPreflightScreenCaptureAccess` is cached per process and can
    /// stay false after the user grants access, so also check whether other processes' window
    /// titles are readable, which only Screen Recording allows and which never prompts.
    var hasPermission: Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        return Self.windowNamesReadable()
    }

    static func windowNamesReadable() -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let own = ProcessInfo.processInfo.processIdentifier
        return list.contains {
            guard let pid = $0[kCGWindowOwnerPID as String] as? Int, pid_t(pid) != own else { return false }
            return !(($0[kCGWindowName as String] as? String) ?? "").isEmpty
        }
    }

    /// Triggers the system prompt (SRS §11: prompt on first popup open).
    func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    func cachedImage(for id: ExtraID) -> NSImage? { cache[id] }

    func clearCache() { cache.removeAll(); templateIDs.removeAll() }

    func isTemplate(_ id: ExtraID) -> Bool { templateIDs.contains(id) }

    @available(macOS 14.0, *)
    private func shareableContent() async -> SCShareableContent? {
        if let s = shareable as? SCShareableContent, Date().timeIntervalSince(shareableFetched) < 2 { return s }
        do {
            let s = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            shareable = s
            shareableFetched = Date()
            return s
        } catch {
            lastError = "Shareable content: \(error.localizedDescription)"
            return nil
        }
    }

    /// ScreenCaptureKit window screenshot (macOS 14+). Older systems use the legacy path only.
    @available(macOS 14.0, *)
    private func modernCapture(extra: MenuBarExtra, scale: CGFloat) async -> CGImage? {
        guard let content = await shareableContent(), let win = content.windows.first(where: { $0.windowID == extra.windowID }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: win)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(extra.frameCG.width * scale))
        config.height = max(1, Int(extra.frameCG.height * scale))
        config.showsCursor = false
        config.scalesToFit = false
        config.captureResolution = .best
        config.backgroundColor = .clear
        config.shouldBeOpaque = false
        config.ignoreShadowsSingleWindow = true
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            lastError = "SCK: \(error.localizedDescription)"
            return nil
        }
    }

    /// Captures one status item window. Returns nil on failure or when the window is blank
    /// (typical for off-screen windows); callers then fall back to the cache or the app icon.
    func capture(extra: MenuBarExtra, scale: CGFloat) async -> NSImage? {
        guard hasPermission else { return nil }
        var cg: CGImage?
        if #available(macOS 14.0, *) {
            cg = await modernCapture(extra: extra, scale: scale)
        }
        if cg == nil || Self.isBlank(cg!) {
            cg = Self.legacyCapture(windowID: extra.windowID)
        }
        guard let image = cg, !Self.isBlank(image) else {
            if lastError == nil { lastError = "Blank capture for \(extra.displayName)" }
            return nil
        }
        let ns = NSImage(cgImage: image, size: extra.frameCG.size)
        cache[extra.id] = ns
        if Self.isMonochrome(image) { templateIDs.insert(extra.id) } else { templateIDs.remove(extra.id) }
        lastSuccess = Date()
        return ns
    }

    /// Captures every given extra, updating the cache. Rate limited by the caller.
    func refresh(extras: [MenuBarExtra], scale: CGFloat) async -> Int {
        var ok = 0
        for e in extras {
            if await capture(extra: e, scale: scale) != nil { ok += 1 }
        }
        return ok
    }

    /// Fallback for windows ScreenCaptureKit cannot render (deprecated in macOS 14 but still
    /// window-scoped, which is what the privacy rules require).
    private static func legacyCapture(windowID: CGWindowID) -> CGImage? {
        #if compiler(>=5.0)
        @available(macOS, deprecated: 14.0)
        func make() -> CGImage? {
            CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .bestResolution])
        }
        return make()
        #else
        return nil
        #endif
    }

    /// True when every visible pixel is (near) gray, i.e. the extra draws a template image whose
    /// color the menu bar picks from the wallpaper rather than the app.
    static func isMonochrome(_ image: CGImage) -> Bool {
        let w = 32, h = 32
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return false }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var visible = 0, gray = 0
        for i in stride(from: 0, to: w * h * 4, by: 4) {
            let a = Int(px[i + 3])
            guard a > 40 else { continue }
            visible += 1
            let r = Int(px[i]) * 255 / a, g = Int(px[i + 1]) * 255 / a, b = Int(px[i + 2]) * 255 / a
            let chroma = max(abs(r - g), abs(g - b), abs(r - b))
            if chroma < 40 { gray += 1 }
        }
        guard visible > 0 else { return false }
        return Double(gray) / Double(visible) >= 0.92
    }

    /// True when the image has no visible pixels.
    static func isBlank(_ image: CGImage) -> Bool {
        let w = 16, h = 16
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return true }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return true }
        let px = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in stride(from: 3, to: w * h * 4, by: 4) where px[i] > 8 { return false }
        return true
    }
}
