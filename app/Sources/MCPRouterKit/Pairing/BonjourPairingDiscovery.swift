import Foundation
import Network

/// Browses `_mcprouter-pair._tcp` on the local network and resolves each service to a host and port.
///
/// The router advertises that service only while `pairing.enabled` is set
/// (planning/plans/plan-pairing-handshake.md
/// §3). A browse reports what is advertising; it does not say what it is. Identity is the certificate, which
/// `LivePairingService` pins before it trusts an endpoint.
///
/// Not run by a unit test: a browse that really ran would send multicast, and the rediscovery logic is tested
/// against `PairingDiscovery` with a fixed list instead. That leaves this type compile-checked only, until a
/// phone on a LAN exercises it.
public struct BonjourPairingDiscovery: PairingDiscovery {
    static let serviceType = "_mcprouter-pair._tcp"

    /// How long the browse listens before it stops and resolves what it has heard.
    private let window: Duration

    public init(window: Duration = .seconds(3)) {
        self.window = window
    }

    public func browse() async -> [DiscoveredMac] {
        let services = await Self.collect(for: window)
        var found: [DiscoveredMac] = []
        for service in services {
            if let mac = await Self.resolve(service) { found.append(mac) }
        }
        return found
    }

    private static func collect(for window: Duration) async -> [NWBrowser.Result] {
        let box = ResultsBox()
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { results, _ in box.store(results) }
        browser.start(queue: .global(qos: .utility))
        // A cancelled sleep ends the browse early, and that is the same as the window closing.
        try? await Task.sleep(for: window)
        browser.cancel()
        return box.results
    }

    /// Opens a connection to the service only to learn the host and port it resolved to. The connection
    /// carries
    /// nothing, and the bound stops a service that never connects from holding up the browse.
    private static func resolve(_ service: NWBrowser.Result) async -> DiscoveredMac? {
        let name = displayName(of: service)
        return await withCheckedContinuation { (continuation: CheckedContinuation<DiscoveredMac?, Never>) in
            let connection = NWConnection(to: service.endpoint, using: .tcp)
            let once = OnceGate()
            let finish: @Sendable (DiscoveredMac?) -> Void = { mac in
                once.run {
                    connection.cancel()
                    continuation.resume(returning: mac)
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(hostAndPort(name: name, endpoint: connection.currentPath?.remoteEndpoint))
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
            Task {
                try? await Task.sleep(for: resolveBound)
                finish(nil)
            }
        }
    }

    private static let resolveBound: Duration = .seconds(3)

    /// The TXT record's `name`, which the router sets to the Mac's display name, or the service's own name.
    private static func displayName(of service: NWBrowser.Result) -> String {
        if case let .bonjour(txt) = service.metadata, case let .string(name)? = txt.getEntry(for: "name") {
            return name
        }
        if case let .service(name, _, _, _) = service.endpoint {
            return name
        }
        return ""
    }

    private static func hostAndPort(name: String, endpoint: NWEndpoint?) -> DiscoveredMac? {
        guard case let .hostPort(host, port)? = endpoint else { return nil }
        return DiscoveredMac(name: name, host: "\(host)", port: Int(port.rawValue))
    }
}

/// The latest browse results. The browser writes them on its own queue, and the browse reads them after the
/// window.
private final class ResultsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: [NWBrowser.Result] = []

    func store(_ results: Set<NWBrowser.Result>) {
        lock.withLock { current = Array(results) }
    }

    var results: [NWBrowser.Result] {
        lock.withLock { current }
    }
}

/// Lets exactly one of several callbacks run. A connection can report ready, fail, and then time out.
private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var ran = false

    func run(_ body: () -> Void) {
        let first = lock.withLock {
            defer { ran = true }
            return !ran
        }
        if first { body() }
    }
}
