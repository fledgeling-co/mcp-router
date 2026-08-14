import Foundation
import Network
import Synchronization

/// `NWConnection`'s callback API as two `async` calls.
///
/// A separate type rather than free functions so the "resume exactly once" obligation lives in one
/// place: `NWConnection` invokes a completion once per call, and a continuation resumed twice traps
/// the process rather than returning an error.
///
/// It lives in its own file rather than beside `LoopbackHTTPServer` because it is the one piece of
/// that file that knows nothing about HTTP: it moves bytes and owns the resume-once guarantee, and
/// the server above it owns request framing, keep-alive and shutdown. Splitting on that line is
/// also what keeps either file inside the size the linter enforces.
final class HTTPSocket: Sendable {
    /// The largest single read accepted from the peer. A cap rather than an unbounded receive: a
    /// client that keeps sending must not be able to size this process's memory.
    private static let readLimit = 65536

    private let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    /// One chunk, or `nil` when the peer has gone or the deadline passed.
    func read(timeoutNanoseconds: UInt64) async -> Data? {
        await withTaskGroup(of: Data?.self, returning: Data?.self) { group in
            group.addTask { [connection] in await Self.receiveOnce(connection) }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }
            // `next()` yields `Data??`: the outer optional says whether the group had another task
            // to hand back, the inner says whether that task produced bytes. Both absences mean the
            // same thing to the caller — nothing arrived — so they are collapsed here rather than
            // distinguished by a caller that has no different response to either.
            let first = await group.next().flatMap(\.self)
            group.cancelAll()
            return first
        }
    }

    /// A single `receive`, bridged onto a continuation that resumes exactly once.
    ///
    /// Extracted from `read` above so the callback's own parameters fit on the line with its brace,
    /// which is the shape both formatter and linter agree on.
    private static func receiveOnce(_ connection: NWConnection) async -> Data? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            let box = OneShot(continuation)
            connection.receive(minimumIncompleteLength: 1, maximumLength: readLimit) { data, _, done, error in
                if error != nil || (done && (data?.isEmpty ?? true)) {
                    box.settle(nil)
                } else {
                    box.settle(data)
                }
            }
        }
    }

    /// Write, reporting whether it landed. A failed write is not thrown: every caller's response to
    /// one is the same — stop using this connection — and an error type would invite a caller to
    /// try to recover on a socket that has gone.
    func write(_ data: Data) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let box = OneShot(continuation)
            connection.send(content: data, completion: .contentProcessed { error in
                box.settle(error == nil)
            })
        }
    }
}

/// A continuation that can be offered an answer any number of times and resumes exactly once.
///
/// `Mutex`-guarded rather than `@unchecked Sendable` with a bare `var`: `SWIFT_PRACTICES.md` §1
/// forbids the latter, and the guarantee here — resume once, ever — is exactly what a double resume
/// would turn into a process trap.
final class OneShot<Value: Sendable>: Sendable {
    private let state = Mutex<CheckedContinuation<Value, Never>?>(nil)

    init(_ continuation: CheckedContinuation<Value, Never>) {
        state.withLock { $0 = continuation }
    }

    func settle(_ value: Value) {
        let continuation = state.withLock { current -> CheckedContinuation<Value, Never>? in
            defer { current = nil }
            return current
        }
        continuation?.resume(returning: value)
    }
}
