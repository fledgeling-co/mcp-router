import Foundation

/// How the phone reaches the Mac.
///
/// The production implementation (TLS 1.3, pinned to the QR's `fp`) is not in this module. B5 wires
/// one; until then the only transport is a fake in the test target, and `LivePairingService` cannot
/// reach a network.
public protocol PairingTransport: Sendable {
    /// Connect and complete the TLS handshake. Nothing is sent before this returns.
    func connect(host: String, port: Int) async throws -> any PairingChannel
}

/// One open connection. The codec in `PairingFrame` turns its bytes into messages.
public protocol PairingChannel: Sendable {
    /// The SHA-256 fingerprint of the certificate the handshake presented, in the form the QR's `fp`
    /// field uses. The service compares the two; a transport never decides the match itself.
    var peerFingerprint: String { get }

    /// Writes one encoded frame.
    func send(_ frame: Data) async throws

    /// Returns one complete frame. An implementation must read the length prefix and refuse anything
    /// over `PairingFrame.maxBodyLength` before buffering the body. `PairingFrame.decode` checks the
    /// same limit again, so a transport that skips it fails closed rather than open.
    func receive() async throws -> Data

    func close() async
}

public enum PairingTransportError: Error, Equatable, Sendable {
    case connectFailed
    case closed
}
