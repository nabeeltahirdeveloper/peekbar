import Foundation
import Darwin
import Network
import PeekBarCore

final class NetworkModule: MetricModule {
    let id: ModuleID = .network
    private var rates = RateTracker(wrapAt: UInt64(UInt32.max) + 1)
    private var monitor: NWPathMonitor?
    private let lock = NSLock()
    private var activeName: String?
    private var activeType: String?
    /// User-chosen interface; nil = follow the system's active path.
    var preferredInterface: String?
    var publicIPEnabled = false
    private var publicIP: String?
    private var publicIPFetched: Date = .distantPast
    private var publicIPTask: Task<Void, Never>?

    func start() throws {
        rates.reset()
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let iface = path.availableInterfaces.first
            let type: String? = iface.map {
                switch $0.type {
                case .wifi: return "Wi‑Fi"
                case .wiredEthernet: return "Ethernet"
                case .cellular: return "Cellular"
                case .loopback: return "Loopback"
                default: return "Other"
                }
            }
            self.lock.lock()
            self.activeName = iface?.name
            self.activeType = type
            self.lock.unlock()
        }
        m.start(queue: DispatchQueue(label: "com.peekbar.netpath", qos: .utility))
        monitor = m
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        rates.reset()
        publicIPTask?.cancel()
    }

    func resetBaselines() { rates.reset() }

    private struct Interfaces {
        var counters: [String: (rx: UInt64, tx: UInt64)] = [:]
        var ipv4: [String: String] = [:]
        var ipv6: [String: String] = [:]
    }

    private func readInterfaces() -> Interfaces {
        var result = Interfaces()
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return result }
        defer { freeifaddrs(addrs) }
        var p = addrs
        while let a = p {
            let ifa = a.pointee
            p = ifa.ifa_next
            let name = String(cString: ifa.ifa_name)
            guard let addr = ifa.ifa_addr else { continue }
            let family = Int32(addr.pointee.sa_family)
            if family == AF_LINK, let data = ifa.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                result.counters[name] = (UInt64(d.ifi_ibytes), UInt64(d.ifi_obytes))
            } else if family == AF_INET || family == AF_INET6 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    var text = String(cString: host)
                    if let pct = text.firstIndex(of: "%") { text = String(text[..<pct]) }
                    if family == AF_INET { result.ipv4[name] = result.ipv4[name] ?? text }
                    else if !text.hasPrefix("fe80") { result.ipv6[name] = result.ipv6[name] ?? text }
                }
            }
        }
        return result
    }

    func sample() -> ModuleReading {
        let now = Date()
        let ifaces = readInterfaces()
        lock.lock()
        let name = preferredInterface ?? activeName
        let type = preferredInterface == nil ? activeType : nil
        lock.unlock()
        var rx: UInt64 = 0, tx: UInt64 = 0
        if let name, let c = ifaces.counters[name] {
            rx = c.rx; tx = c.tx
        } else {
            for (n, c) in ifaces.counters where !n.hasPrefix("lo") && !n.hasPrefix("utun") && !n.hasPrefix("awdl") && !n.hasPrefix("llw") {
                rx &+= c.rx; tx &+= c.tx
            }
        }
        let down = rates.update("rx", bytes: rx, at: now) ?? 0
        let up = rates.update("tx", bytes: tx, at: now) ?? 0
        refreshPublicIPIfNeeded(now: now)
        return .network(NetworkReading(interfaceName: name, interfaceType: type, downloadRate: down, uploadRate: up,
                                       totalDownloaded: rx, totalUploaded: tx,
                                       localIPv4: name.flatMap { ifaces.ipv4[$0] }, localIPv6: name.flatMap { ifaces.ipv6[$0] },
                                       publicIP: publicIPEnabled ? publicIP : nil))
    }

    /// Opt-in only (SRS §11: no network calls by default). Refreshed every 10 minutes.
    private func refreshPublicIPIfNeeded(now: Date) {
        guard publicIPEnabled, now.timeIntervalSince(publicIPFetched) > 600, publicIPTask == nil else { return }
        publicIPFetched = now
        publicIPTask = Task { [weak self] in
            defer { self?.publicIPTask = nil }
            guard let url = URL(string: "https://api.ipify.org") else { return }
            if let (data, _) = try? await URLSession.shared.data(from: url), let text = String(data: data, encoding: .utf8) {
                self?.publicIP = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    /// Interface names for the Settings picker.
    static func interfaceNames() -> [String] {
        var names: Set<String> = []
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return [] }
        defer { freeifaddrs(addrs) }
        var p = addrs
        while let a = p {
            let n = String(cString: a.pointee.ifa_name)
            if n.hasPrefix("en") || n.hasPrefix("bridge") || n.hasPrefix("utun") || n.hasPrefix("ppp") { names.insert(n) }
            p = a.pointee.ifa_next
        }
        return names.sorted()
    }
}
