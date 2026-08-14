import Foundation
import Synchronization

/// A non-`Sendable`-crossing handle, so the listener's `@Sendable` handler can reach the actor.
struct Handler: Sendable {
    let service: RouterService

    func respond(to request: HTTPWireRequest) async -> HTTPWireResponse {
        await service.respond(to: request)
    }
}

/// Identities resolved at accept time, looked up again when a call is recorded.
///
/// A process-wide store rather than state on the service, because the lookup happens on a detached
/// task started by the listener's accept callback and has to be readable from whichever request
/// arrives on that connection afterwards.
final class PeerIdentities: Sendable {
    static let shared = PeerIdentities()
    static let capacity = 512

    private struct State {
        var byPeer: [String: ClientIdentity] = [:]
        var order: [String] = []
    }

    private let state = Mutex(State())

    func store(_ identity: ClientIdentity, for descriptor: ConnectionDescriptor) {
        state.withLock { current in
            if current.byPeer[descriptor.peer] == nil { current.order.append(descriptor.peer) }
            current.byPeer[descriptor.peer] = identity
            while current.order.count > Self.capacity {
                let oldest = current.order.removeFirst()
                current.byPeer[oldest] = nil
            }
        }
    }

    /// The identity for this connection, or `unknown`. An unattributed record is worth far more
    /// than a dropped one, so this is a value rather than an error.
    func identity(for descriptor: ConnectionDescriptor) -> ClientIdentity {
        state.withLock { $0.byPeer[descriptor.peer] ?? .unknown }
    }
}

/// Holds a non-`Sendable` unsubscribe closure so a `@Sendable` termination handler can call it.
///
/// `@unchecked Sendable` with the reason `SWIFT_PRACTICES.md` §1 asks for: the closure is written
/// once at construction and read once at termination, guarded by a mutex, and `AsyncStream`
/// guarantees `onTermination` runs at most once.
final class UnsubscribeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (() -> Void)?

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func cancel() {
        lock.lock()
        let handler = handler
        self.handler = nil
        lock.unlock()
        handler?()
    }
}
