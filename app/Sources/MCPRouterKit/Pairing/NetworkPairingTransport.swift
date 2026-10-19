import Foundation
import Network
import os
import Security

/// The phone's production transport: TLS 1.3 over Network.framework, pinned to the fingerprint the QR
/// named.
///
/// **There is no certificate authority.** The Mac's certificate is self-signed, so the handshake does
/// not ask whether anyone trusts it. It asks one question: is this the certificate the QR named? A
/// certificate that answers no ends the handshake, and nothing is written to the connection (plan
/// §2.2).
public struct NetworkPairingTransport: PairingTransport {
    public init() {}

    public func connect(
        host: String,
        port: Int,
        expecting fingerprint: String
    ) async throws -> any PairingChannel {
        guard let value = UInt16(exactly: port), let nwPort = NWEndpoint.Port(rawValue: value) else {
            throw PairingTransportError.connectFailed
        }
        let presented = PresentedCertificate()
        let queue = DispatchQueue(label: "app.fledgeling.mcprouter.pairing.transport")
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: Self.parameters(expecting: fingerprint, presenting: presented, on: queue)
        )
        do {
            try await awaitCompletion(cancelling: connection) { completion in
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        completion.finish(.success(()))
                    case .failed:
                        completion.finish(.failure(handshakeFailure(presented, expecting: fingerprint)))
                    case .waiting:
                        // Network.framework reports a rejected certificate as `waiting`, not `failed`
                        // (measured on loopback: `waiting(bad certificate format)`), so this state checks
                        // for it. Any other wait is left to the exchange's deadline. A phone still being
                        // asked for Local Network access waits here, and failing on that would report
                        // "can't reach" while iOS is asking the user a question.
                        if isMismatch(presented, expecting: fingerprint) {
                            completion.finish(.failure(PairingTransportError.identityMismatch))
                        }
                    case .cancelled:
                        completion.finish(.failure(PairingTransportError.connectFailed))
                    default:
                        break
                    }
                }
                connection.start(queue: queue)
            }
        } catch {
            connection.cancel()
            throw error
        }
        guard let peer = presented.fingerprint else {
            connection.cancel()
            throw PairingTransportError.connectFailed
        }
        return NetworkPairingChannel(connection: connection, peerFingerprint: peer)
    }

    /// TLS 1.3 only, with a verify block in place of trust evaluation. The block records the
    /// fingerprint it was shown, then accepts the handshake only when that fingerprint is the QR's.
    private static func parameters(
        expecting fingerprint: String,
        presenting presented: PresentedCertificate,
        on queue: DispatchQueue
    ) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
        sec_protocol_options_set_verify_block(tls.securityProtocolOptions, { _, trust, complete in
            guard let der = leafCertificateDER(trust) else {
                complete(false)
                return
            }
            presented.record(PairingFingerprint.render(certificateDER: der))
            complete(PairingFingerprint.matches(certificateDER: der, expecting: fingerprint))
        }, queue)
        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }
}

/// The DER bytes of the certificate the handshake presented, if it presented one.
private func leafCertificateDER(_ trust: sec_trust_t) -> Data? {
    let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
    guard let chain = SecTrustCopyCertificateChain(secTrust) as? [SecCertificate],
          let leaf = chain.first
    else { return nil }
    return SecCertificateCopyData(leaf) as Data
}

/// Why a handshake ended without becoming ready. A certificate that was shown and did not match is an
/// identity mismatch. Anything else, including a handshake that showed nothing, is a failed connection.
private func handshakeFailure(_ presented: PresentedCertificate, expecting fingerprint: String) -> any Error {
    isMismatch(presented, expecting: fingerprint)
        ? PairingTransportError.identityMismatch
        : PairingTransportError.connectFailed
}

/// Whether the handshake showed a certificate and it was not the one the QR named.
private func isMismatch(_ presented: PresentedCertificate, expecting fingerprint: String) -> Bool {
    guard let seen = presented.fingerprint else { return false }
    return seen != fingerprint
}

/// One open, pinned connection. An actor, so the connection's mutable state is checked rather than
/// promised.
actor NetworkPairingChannel: PairingChannel {
    nonisolated let peerFingerprint: String
    private let connection: NWConnection

    init(connection: NWConnection, peerFingerprint: String) {
        self.connection = connection
        self.peerFingerprint = peerFingerprint
    }

    func send(_ frame: Data) async throws {
        try await awaitCompletion(cancelling: connection) { (completion: Completion<Void>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error {
                    completion.finish(.failure(error))
                } else {
                    completion.finish(.success(()))
                }
            })
        }
    }

    /// One frame, through the shared gate in `PairingFrame.readFrame`, so an oversized length prefix
    /// is refused before any body is requested.
    func receive() async throws -> Data {
        try await PairingFrame.readFrame { count in
            try await self.receiveExactly(count)
        }
    }

    private func receiveExactly(_ count: Int) async throws -> Data {
        guard count > 0 else { return Data() }
        return try await awaitCompletion(cancelling: connection) { (completion: Completion<Data>) in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error {
                    completion.finish(.failure(error))
                    return
                }
                // A short read is a closed connection, because the caller asked for exactly `count`.
                guard let data, data.count == count else {
                    completion.finish(.failure(PairingTransportError.closed))
                    return
                }
                completion.finish(.success(data))
            }
        }
    }

    func close() async {
        connection.cancel()
    }
}

/// Resolves one Network.framework callback exactly once, whichever arrives first: the callback, or a
/// cancellation. Cancellation is how the exchange's deadline ends a stalled call, so a continuation
/// that is not resumed on that path would hang the exchange with it.
private final class Completion<Value: Sendable>: Sendable {
    private struct State: Sendable {
        var continuation: CheckedContinuation<Value, any Error>?
        var outcome: Result<Value, any Error>?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Hands over the continuation, or resumes at once if the outcome has already arrived.
    func attach(_ continuation: CheckedContinuation<Value, any Error>) {
        let ready: Result<Value, any Error>? = state.withLock { current in
            if let outcome = current.outcome { return outcome }
            current.continuation = continuation
            return nil
        }
        if let ready { continuation.resume(with: ready) }
    }

    /// Records the first outcome and resumes the waiting call, if there is one. Later outcomes are
    /// dropped, so a callback that fires after a cancellation cannot resume twice.
    func finish(_ result: Result<Value, any Error>) {
        let waiting: CheckedContinuation<Value, any Error>? = state.withLock { current in
            guard current.outcome == nil else { return nil }
            current.outcome = result
            let continuation = current.continuation
            current.continuation = nil
            return continuation
        }
        waiting?.resume(with: result)
    }
}

/// The fingerprint the handshake showed, recorded from the verify block before the handshake decides.
private final class PresentedCertificate: Sendable {
    private let lock = OSAllocatedUnfairLock<String?>(initialState: nil)

    var fingerprint: String? {
        lock.withLock { $0 }
    }

    func record(_ fingerprint: String) {
        lock.withLock { $0 = fingerprint }
    }
}

/// Runs one Network.framework operation and waits for its callback. A cancelled task cancels the
/// connection, and the wait ends with `CancellationError` rather than hanging.
private nonisolated(nonsending) func awaitCompletion<Value: Sendable>(
    cancelling connection: NWConnection,
    _ start: (Completion<Value>) -> Void
) async throws -> Value {
    let completion = Completion<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            completion.attach(continuation)
            start(completion)
        }
    } onCancel: {
        connection.cancel()
        completion.finish(.failure(CancellationError()))
    }
}
