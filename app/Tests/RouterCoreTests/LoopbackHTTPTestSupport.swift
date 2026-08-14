import Foundation
import Network
import Testing
@testable import RouterCore

// MARK: - A raw HTTP client, because the assertions are about bytes

/// One HTTP/1.1 request over loopback, returning the response exactly as it arrived.
///
/// Deliberately not `URLSession`. Two of this suite's assertions are about what the response does
/// **not** contain — B82's 404 carries no `content-type` and no body — and a client that normalises
/// headers into a dictionary cannot testify to the bytes on the wire. This one hands back the head
/// and the body as they were sent.
///
/// `@unchecked Sendable` with a stated reason, per `SWIFT_PRACTICES.md` §1: every mutable field is
/// guarded by `lock`, Network.framework delivers on its own queue, and a lock is the smallest honest
/// synchronisation for that.
final class RawHTTP: @unchecked Sendable {
    enum Failure: Error, Equatable {
        case unreachable(String)
        case timedOut
    }

    private let lock = NSLock()
    private var buffer = Data()
    private var continuation: CheckedContinuation<String, Error>?
    private var connection: NWConnection?
    private var deadline: DispatchWorkItem?

    /// `GET <target>` against 127.0.0.1:`port`, resolved when the server closes the connection.
    static func get(port: Int, target: String, timeout: TimeInterval = 5) async throws -> String {
        try await RawHTTP().perform(port: port, target: target, timeout: timeout)
    }

    private func perform(port: Int, target: String, timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(truncatingIfNeeded: port)) else {
                finish(.failure(Failure.unreachable("not a port")))
                return
            }
            let connection = NWConnection(host: .ipv4(.loopback), port: endpointPort, using: .tcp)
            lock.lock()
            self.connection = connection
            lock.unlock()

            let deadline = DispatchWorkItem { [self] in
                finish(.failure(Failure.timedOut))
                connection.cancel()
            }
            lock.lock()
            self.deadline = deadline
            lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)

            connection.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    let request = "GET \(target) HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
                    connection.send(content: Data(request.utf8), completion: .contentProcessed { _ in })
                    read(connection)
                case let .failed(error):
                    finish(.failure(Failure.unreachable(String(describing: error))))
                    connection.cancel()
                // A refused port makes `NWConnection` *wait and retry*, so a test that only handled
                // `.failed` would hang rather than assert "nothing is listening".
                case let .waiting(error):
                    finish(.failure(Failure.unreachable(String(describing: error))))
                    connection.cancel()
                case .cancelled:
                    finishWithBuffer()
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    private func read(_ connection: NWConnection) {
        connection.receiveWholeResponse { [self] data, isComplete, failed in
            if let data, !data.isEmpty {
                lock.lock()
                buffer.append(data)
                lock.unlock()
            }
            if isComplete || failed {
                finishWithBuffer()
                connection.cancel()
                return
            }
            read(connection)
        }
    }

    private func finishWithBuffer() {
        lock.lock()
        let text = String(bytes: buffer, encoding: .utf8) ?? ""
        lock.unlock()
        finish(.success(text))
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        deadline?.cancel()
        deadline = nil
        lock.unlock()
        guard let continuation else { return }
        continuation.resume(with: result)
    }
}

/// The head and the body, split on the blank line. Neither is normalised.
func splitResponse(_ raw: String) -> (head: String, body: String) {
    guard let range = raw.range(of: "\r\n\r\n") else { return (raw, "") }
    return (String(raw[raw.startIndex ..< range.lowerBound]), String(raw[range.upperBound...]))
}

/// Resume-once box for the split-segment test's continuation.
final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func succeed(_ value: String) {
        take()?.resume(returning: value)
    }

    func fail(_ error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<String, Error>? {
        lock.lock(); defer { lock.unlock() }
        let held = continuation
        continuation = nil
        return held
    }
}

/// `receive` with the arguments this client never varies, so the completion's parameters fit on the
/// line with its brace — which the linter requires and the four-argument call leaves no room for.
private extension NWConnection {
    func receiveWholeResponse(_ handler: @escaping @Sendable (Data?, Bool, Bool) -> Void) {
        receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            handler(data, isComplete, error != nil)
        }
    }
}
