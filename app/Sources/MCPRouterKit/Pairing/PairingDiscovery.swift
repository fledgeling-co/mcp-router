import Foundation

/// A Mac the local-network browse found: where it answers now, and the name it advertises.
///
/// The name is a label for a person and orders the probes; it is never an identity. The identity of a
/// Mac is its certificate's fingerprint, and a transport must pin that before an endpoint is trusted
/// with anything (plan §2.2, §3).
public struct DiscoveredMac: Sendable, Equatable {
    public let name: String
    public let host: String
    public let port: Int

    public init(name: String, host: String, port: Int) {
        self.name = name
        self.host = host
        self.port = port
    }
}

/// Finds the Macs advertising the pairing service on the local network.
///
/// The seam the phone's reachability probe uses to find a Mac whose address has moved. Production browses
/// Bonjour; a test supplies a fixed list, so no multicast is sent from a unit test.
public protocol PairingDiscovery: Sendable {
    /// Every endpoint seen in the browse window, or none. It does not throw: a browse that cannot run
    /// leaves a Mac exactly as unreachable as one that was not found, so both take the same path.
    func browse() async -> [DiscoveredMac]
}
