import Foundation

/// A global keyboard shortcut in Carbon terms (F-50).
public struct KeyCombo: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt32
    /// Carbon modifier mask: cmdKey (256), shiftKey (512), optionKey (2048), controlKey (4096).
    public var modifiers: UInt32

    public static let cmd: UInt32 = 1 << 8
    public static let shift: UInt32 = 1 << 9
    public static let option: UInt32 = 1 << 11
    public static let control: UInt32 = 1 << 12
    public static let relevantMask: UInt32 = cmd | shift | option | control

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers & Self.relevantMask
    }

    /// Default popup shortcut: ⌥⌘B ("bar").
    public static let defaultCombo = KeyCombo(keyCode: 11, modifiers: cmd | option)
    /// Default Arrange shortcut: ⌥⌘A ("arrange").
    public static let defaultArrangeCombo = KeyCombo(keyCode: 0, modifiers: cmd | option)
    /// Default dashboard shortcut: ⌥⌘S ("stats").
    public static let defaultDashboardCombo = KeyCombo(keyCode: 1, modifiers: cmd | option)

    /// A combo needs at least one modifier that is not just Shift, so it cannot swallow typing.
    public var isUsable: Bool {
        (modifiers & (Self.cmd | Self.option | Self.control)) != 0
    }

    public var displayString: String {
        var s = ""
        if modifiers & Self.control != 0 { s += "⌃" }
        if modifiers & Self.option != 0 { s += "⌥" }
        if modifiers & Self.shift != 0 { s += "⇧" }
        if modifiers & Self.cmd != 0 { s += "⌘" }
        s += KeyCodeNames.name(for: keyCode)
        return s
    }
}

public enum KeyCodeNames {
    static let table: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
        35: "P", 36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋", 96: "F5", 97: "F6", 98: "F7",
        99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13", 107: "F14", 109: "F10", 111: "F12",
        113: "F15", 118: "F4", 120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 116: "⇞", 117: "⌦", 119: "↘", 121: "⇟",
    ]
    public static func name(for keyCode: UInt32) -> String {
        table[keyCode] ?? "Key \(keyCode)"
    }
}

/// One entry from the system's symbolic hot key table (CopySymbolicHotKeys).
public struct SystemHotKey: Equatable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var enabled: Bool
    public init(keyCode: UInt32, modifiers: UInt32, enabled: Bool) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.enabled = enabled
    }
}

/// F-50 conflict detection against system shortcuts.
public enum HotKeyConflictChecker {
    public static func conflicts(_ combo: KeyCombo, with system: [SystemHotKey]) -> Bool {
        system.contains { entry in
            entry.enabled
                && entry.keyCode == combo.keyCode
                && (entry.modifiers & KeyCombo.relevantMask) == combo.modifiers
        }
    }
}
