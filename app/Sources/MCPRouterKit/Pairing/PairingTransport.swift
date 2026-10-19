import Foundation

/// How the phone reaches the Mac.
///
/// The production implementation is `NetworkPairingTransport`: TLS 1.3, pinned to the QR's `fp`.
public protocol PairingTransport: Sendable {
    /// Connect and complete the TLS handshake. Nothing is sent before this returns.
    ///
    /// The handshake is pinned to `fingerprint`: a transport that sees a certificate with any other
    /// fingerprint refuses the handshake and throws `identityMismatch`. The service checks
    /// `peerFingerprint` again before it writes a frame, so a transport that does not pin still
    /// cannot send to the wrong Mac.
    func connect(host: String, port: Int, expecting fingerprint: String) async throws -> any PairingChannel
}

/// One open connection. The codec in `PairingFrame` turns its bytes into messages.
public protocol PairingChannel: Sendable {
    /// The SHA-256 fingerprint of the certificate the handshake presented, rendered by
    /// `PairingFingerprint.render` as the QR's `fp` field carries it (plan §2.4). The service compares
    /// it with the QR's value before any frame is written.
    var peerFingerprint: String { get }

    /// Writes one encoded frame.
    func send(_ frame: Data) async throws

    /// Returns one complete frame, read with `PairingFrame.readFrame`, which refuses a length prefix over
    /// `PairingFrame.maxBodyLength` before the body is requested. `PairingFrame.decode` checks the same
    /// limit again, so a transport that skips it fails closed rather than open.
    func receive() async throws -> Data

    func close() async
}

public enum PairingTransportError: Error, Equatable, Sendable {
    case connectFailed
    case closed
    /// The handshake presented a certificate other than the one the QR named.
    case identityMismatch
}
