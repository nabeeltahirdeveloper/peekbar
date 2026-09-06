import Foundation
import IOKit
import PeekBarCore

/// Read-only AppleSMC user client. The struct layout and selector are the ones every macOS
/// sensor tool has used since 2006; nothing here can write.
final class SMCClient {
    // Mirrors SMCKeyData_t (80 bytes). Nested structs carry explicit trailing padding because
    // Swift packs a nested struct by its size, C by its stride.
    private struct Vers { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0; var reserved: UInt8 = 0; var release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0; var length: UInt16 = 0; var cpu: UInt32 = 0; var gpu: UInt32 = 0; var mem: UInt32 = 0 }
    private struct KeyInfo { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0; var pad: (UInt8, UInt8, UInt8) = (0, 0, 0) }
    private struct KeyData {
        var key: UInt32 = 0
        var vers = Vers()
        var pLimit = PLimit()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private static let selector: UInt32 = 2       // kSMCHandleYPCEvent
    private static let cmdReadBytes: UInt8 = 5
    private static let cmdKeyInfo: UInt8 = 9
    private static let cmdKeyFromIndex: UInt8 = 8

    private var connection: io_connect_t = 0
    private var typeCache: [String: (size: UInt32, type: String)] = [:]

    struct Error: Swift.Error, LocalizedError { let message: String; var errorDescription: String? { message } }

    func open() throws {
        guard connection == 0 else { return }
        assert(MemoryLayout<KeyData>.size == 80, "SMCKeyData_t layout drifted: \(MemoryLayout<KeyData>.size)")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw Error(message: "AppleSMC service not found") }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard kr == KERN_SUCCESS else { throw Error(message: "IOServiceOpen failed (\(kr))") }
    }

    func close() {
        if connection != 0 { IOServiceClose(connection); connection = 0 }
        typeCache.removeAll()
    }

    deinit { close() }

    private static func fourcc(_ s: String) -> UInt32 {
        var v: UInt32 = 0
        for c in s.utf8.prefix(4) { v = v << 8 | UInt32(c) }
        return v
    }

    private static func string(_ v: UInt32) -> String {
        String(bytes: [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)], encoding: .ascii) ?? "????"
    }

    private func call(_ input: KeyData) -> KeyData? {
        guard connection != 0 else { return nil }
        var inp = input
        var out = KeyData()
        var outSize = MemoryLayout<KeyData>.size
        let kr = IOConnectCallStructMethod(connection, Self.selector, &inp, MemoryLayout<KeyData>.size, &out, &outSize)
        guard kr == KERN_SUCCESS, out.result == 0 else { return nil }
        return out
    }

    func keyInfo(_ key: String) -> (size: UInt32, type: String)? {
        if let c = typeCache[key] { return c }
        var input = KeyData()
        input.key = Self.fourcc(key)
        input.data8 = Self.cmdKeyInfo
        guard let out = call(input), out.keyInfo.dataSize > 0, out.keyInfo.dataSize <= 32 else { return nil }
        let info = (out.keyInfo.dataSize, Self.string(out.keyInfo.dataType))
        typeCache[key] = info
        return info
    }

    func readRaw(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard let info = keyInfo(key) else { return nil }
        var input = KeyData()
        input.key = Self.fourcc(key)
        input.keyInfo.dataSize = info.size
        input.data8 = Self.cmdReadBytes
        guard let out = call(input) else { return nil }
        let bytes = withUnsafeBytes(of: out.bytes) { Array($0.prefix(Int(info.size))) }
        return (info.type, bytes)
    }

    func read(_ key: String) -> Double? {
        guard let raw = readRaw(key) else { return nil }
        return SensorCatalog.decode(type: raw.type, bytes: raw.bytes)
    }

    /// Every key the SMC exposes.
    func allKeys() -> [String] {
        guard let count = read("#KEY").map({ Int($0) }), count > 0, count < 10_000 else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(count)
        for i in 0..<count {
            var input = KeyData()
            input.data8 = Self.cmdKeyFromIndex
            input.data32 = UInt32(i)
            guard let out = call(input) else { continue }
            keys.append(Self.string(out.key))
        }
        return keys
    }
}
