import AppKit
import os
import PeekBarCore

let log = Logger(subsystem: "com.peekbar.app", category: "app")

enum AppInfo {
    static let bundleID = Bundle.main.bundleIdentifier ?? "com.peekbar.app"
    static var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("PeekBar", isDirectory: true)
    }
    static var isDebugBridgeEnabled: Bool {
        CommandLine.arguments.contains("--debug-bridge")
    }
}

extension NSScreen {
    /// The display whose top-left is the window server origin.
    static var primary: NSScreen? {
        screens.first { $0.frame.origin == .zero } ?? screens.first
    }

    static var primaryHeight: CGFloat { primary?.frame.height ?? 0 }

    static var underMouse: NSScreen? {
        let p = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(p, $0.frame, false) }
    }

    var geometry: ScreenGeometry {
        var notch: CGRect?
        let top = safeAreaInsets.top
        if top > 0, let l = auxiliaryTopLeftArea, let r = auxiliaryTopRightArea {
            notch = CGRect(x: l.maxX, y: frame.maxY - top, width: max(0, r.minX - l.maxX), height: top)
        }
        return ScreenGeometry(
            frame: frame,
            visibleFrame: visibleFrame,
            safeAreaTop: top,
            notch: notch,
            statusBarThickness: NSStatusBar.system.thickness
        )
    }

    var hasNotch: Bool { safeAreaInsets.top > 0 && auxiliaryTopLeftArea != nil }
}

enum SystemSettingsPane {
    case screenRecording, accessibility, loginItems, notifications

    var url: URL {
        switch self {
        case .screenRecording: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        case .accessibility: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .loginItems: return URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
        case .notifications: return URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        }
    }

    func open() { NSWorkspace.shared.open(url) }
}

/// Code-drawn template glyphs so the app has no asset catalog dependency.
enum Glyphs {
    /// The PeekBar affordance: a compact rounded rectangle with a "tray" of dots, Control Center
    /// adjacent, deliberately not a chevron (SRS §7.2).
    static let toggle: NSImage = {
        let size = NSSize(width: 18, height: 14)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let outer = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3.5, yRadius: 3.5)
            outer.lineWidth = 1.6
            outer.stroke()
            let dotY = rect.midY - 1.25
            for x in [5.0, 9.0, 13.0] {
                NSBezierPath(ovalIn: NSRect(x: x - 1.25, y: dotY, width: 2.5, height: 2.5)).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }()

    /// Divider shown in Arrange mode.
    static let separator: NSImage = {
        let size = NSSize(width: 10, height: 16)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: NSRect(x: rect.midX - 1, y: 1, width: 2, height: rect.height - 2), xRadius: 1, yRadius: 1).fill()
            return true
        }
        img.isTemplate = true
        return img
    }()

    /// Chevron glyphs for the reveal modes (down = popup below, left = expand sideways).
    static func chevron(_ direction: String) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        let img = NSImage(systemSymbolName: "chevron.\(direction)", accessibilityDescription: "PeekBar")?.withSymbolConfiguration(config) ?? toggle
        img.isTemplate = true
        return img
    }

    /// Expanded / Arrange glyph: the icon with a dashed hide-boundary on its left.
    static let toggleDivider: NSImage = {
        let size = NSSize(width: 28, height: 14)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 1.5, y: 0.5))
            line.line(to: NSPoint(x: 1.5, y: rect.height - 0.5))
            line.lineWidth = 1.5
            line.setLineDash([2.5, 2], count: 2, phase: 0)
            line.stroke()
            let box = NSRect(x: 8, y: 1, width: 18, height: 12)
            let outer = NSBezierPath(roundedRect: box, xRadius: 3.5, yRadius: 3.5)
            outer.lineWidth = 1.6
            outer.stroke()
            let dotY = box.midY - 1.25
            for x in [12.0, 16.0, 20.0] {
                NSBezierPath(ovalIn: NSRect(x: x - 1.25, y: dotY, width: 2.5, height: 2.5)).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }()

    static let toggleActive: NSImage = {
        let size = NSSize(width: 18, height: 14)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 3.5, yRadius: 3.5).fill()
            NSColor.white.setFill()
            let dotY = rect.midY - 1.25
            for x in [5.0, 9.0, 13.0] {
                NSBezierPath(ovalIn: NSRect(x: x - 1.25, y: dotY, width: 2.5, height: 2.5)).fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }()
}

extension NSImage {
    /// Writes a PNG. Used by the debug bridge for UI snapshots.
    func writePNG(to url: URL) throws {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PeekBar", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
        }
        try data.write(to: url)
    }
}

extension NSView {
    func snapshotImage() -> NSImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let img = NSImage(size: bounds.size)
        img.addRepresentation(rep)
        return img
    }
}

import SwiftUI

extension View {
    /// `.formStyle(.grouped)` where available (macOS 13+); plain form on Monterey.
    @ViewBuilder func groupedForm() -> some View {
        if #available(macOS 13.0, *) { self.formStyle(.grouped) } else { self.padding() }
    }
}

/// A key/value row that works on macOS 12 (no `LabeledContent`).
struct LabeledRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.secondary) }
    }
}

@MainActor
func sleepMs(_ ms: Int) async {
    try? await Task.sleep(nanoseconds: UInt64(ms) * 1_000_000)
}
