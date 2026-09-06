import AppKit
import Carbon
import PeekBarCore

/// Global hotkeys via Carbon's RegisterEventHotKey (F-50). Supports several shortcuts, each
/// identified by a small integer id.
final class HotKeyManager {
    enum ID: UInt32 { case popup = 1, arrange = 2, dashboard = 3 }

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private(set) var registered: [UInt32: KeyCombo] = [:]

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let userData, let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            let id = hotKeyID.id
            DispatchQueue.main.async { manager.handlers[id]?() }
            return noErr
        }, 1, &spec, selfPtr, &eventHandler)
    }

    func setHandler(_ id: ID, _ handler: @escaping () -> Void) {
        handlers[id.rawValue] = handler
    }

    @discardableResult
    func register(_ combo: KeyCombo, id: ID) -> Bool {
        unregister(id)
        guard combo.isUsable else { return false }
        let hotKeyID = EventHotKeyID(signature: OSType(0x504B4252), id: id.rawValue) // "PKBR"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[id.rawValue] = ref
            registered[id.rawValue] = combo
            return true
        }
        log.error("RegisterEventHotKey(\(id.rawValue)) failed: \(status)")
        return false
    }

    func unregister(_ id: ID) {
        if let ref = refs.removeValue(forKey: id.rawValue) { UnregisterEventHotKey(ref) }
        registered[id.rawValue] = nil
    }

    /// The system's own shortcuts, for conflict detection.
    static func systemHotKeys() -> [SystemHotKey] {
        var arr: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&arr) == noErr, let list = arr?.takeRetainedValue() as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            guard let code = d["kHISymbolicHotKeyCode"] as? Int, let mods = d["kHISymbolicHotKeyModifiers"] as? Int else { return nil }
            let enabled = d["kHISymbolicHotKeyEnabled"] as? Bool ?? false
            return SystemHotKey(keyCode: UInt32(code), modifiers: UInt32(mods), enabled: enabled)
        }
    }

    static func conflicts(_ combo: KeyCombo) -> Bool {
        HotKeyConflictChecker.conflicts(combo, with: systemHotKeys())
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= KeyCombo.cmd }
        if flags.contains(.option) { m |= KeyCombo.option }
        if flags.contains(.control) { m |= KeyCombo.control }
        if flags.contains(.shift) { m |= KeyCombo.shift }
        return m
    }

    /// Debug: type a combo through the HID tap so the registered hotkey fires as if pressed.
    static func press(_ combo: KeyCombo) {
        var flags: CGEventFlags = []
        if combo.modifiers & KeyCombo.cmd != 0 { flags.insert(.maskCommand) }
        if combo.modifiers & KeyCombo.option != 0 { flags.insert(.maskAlternate) }
        if combo.modifiers & KeyCombo.control != 0 { flags.insert(.maskControl) }
        if combo.modifiers & KeyCombo.shift != 0 { flags.insert(.maskShift) }
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(combo.keyCode), keyDown: down) else { continue }
            e.flags = flags
            e.post(tap: .cghidEventTap)
        }
    }
}
