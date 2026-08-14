import Foundation
import Network
import Synchronization

/// One request over loopback, written whole, read until the peer closes.
///
/// Small on purpose. The verbs that use it ask for a single JSON body from a router on this machine,
/// and the only failure they distinguish is "nothing answered" — which is the state
/// `DESIGN.md` §5 calls Offline and which, for a loopback product, means *the router is not
/// running*. Every other outcome collapses to `nil`, so the two callers cannot accidentally report
/// a parse failure as a missing daemon.
enum RawLoopbackClient {
    static func send(_ request: Data, port: Int, timeout: TimeInterval = 10) async -> Data? {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(truncatingIfNeeded: port)) else {
            return nil
        }
        let connection = NWConnection(host: .ipv4(.loopback), port: endpointPort, using: .tcp)
        let collected = Collected()

        return await withTaskGroup(of: Data?.self, returning: Data?.self) { group in
            group.addTask {
                await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                    let box = Settle(continuation)
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            connection.send(content: request, completion: .contentProcessed { error in
                                if error != nil { box.settle(nil) } else { read(connection, collected, box) }
                            })
                        case .failed, .cancelled:
                            box.settle(nil)
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global())
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            connection.cancel()
            return first
        }
    }

    /// Reads until the response is **complete by its own framing**, not until the peer hangs up.
    ///
    /// Waiting for the close is what a naive client does, and against a keep-alive server it waits
    /// for the idle timeout with the whole answer already in hand — which the router's own `status`
    /// verb reported as "no router answering", the one state it must never report wrongly.
    private static func read(_ connection: NWConnection, _ collected: Collected, _ box: Settle) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data { collected.append(data) }
            let bytes = collected.bytes
            if error != nil || isComplete || isWhole(bytes) {
                box.settle(bytes)
                return
            }
            read(connection, collected, box)
        }
    }

    /// Whether these bytes are a whole HTTP response: a terminated head, plus as many body bytes as
    /// its `content-length` declares. A response with no `content-length` is only whole when the
    /// peer closes, which the caller above still handles.
    private static func isWhole(_ bytes: Data) -> Bool {
        guard let terminator = bytes.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let head = String(decoding: bytes[bytes.startIndex ..< terminator.lowerBound], as: UTF8.self)
        for line in head.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].lowercased() == "content-length",
                  let length = Int(parts[1].trimmingCharacters(in: .whitespaces))
            else { continue }
            return bytes.distance(from: terminator.upperBound, to: bytes.endIndex) >= length
        }
        return false
    }

    private final class Collected: Sendable {
        private let state = Mutex(Data())
        func append(_ data: Data) { state.withLock { $0.append(data) } }
        var bytes: Data { state.withLock { $0 } }
    }

    /// Resumes exactly once, however many callbacks fire.
    private final class Settle: Sendable {
        private let state = Mutex<CheckedContinuation<Data?, Never>?>(nil)

        init(_ continuation: CheckedContinuation<Data?, Never>) {
            state.withLock { $0 = continuation }
        }

        func settle(_ value: Data?) {
            let continuation = state.withLock { current -> CheckedContinuation<Data?, Never>? in
                defer { current = nil }
                return current
            }
            continuation?.resume(returning: value)
        }
    }
}

/// Waits for SIGINT or SIGTERM and reports which arrived.
///
/// The sources are held here rather than in a local, because a `DispatchSourceSignal` that goes out
/// of scope is cancelled and the process reverts to dying on the signal — a shutdown that never runs
/// and a router that leaves its children behind.
final class SignalWait: @unchecked Sendable {
    private let lock = NSLock()
    private var sources: [any DispatchSourceSignal] = []
    private var name: String?
    private var waiter: CheckedContinuation<String, Never>?

    func hold(_ source: any DispatchSourceSignal) {
        lock.lock()
        sources.append(source)
        lock.unlock()
    }

    func fire(_ signalName: String) {
        lock.lock()
        // The first signal wins. A second SIGTERM while shutdown is under way must not resume a
        // continuation that has already been resumed, which traps the process rather than hurrying
        // it along.
        guard name == nil else { lock.unlock(); return }
        name = signalName
        let waiter = waiter
        self.waiter = nil
        lock.unlock()
        waiter?.resume(returning: signalName)
    }

    func wait() async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            lock.lock()
            if let name {
                lock.unlock()
                continuation.resume(returning: name)
                return
            }
            waiter = continuation
            lock.unlock()
        }
    }
}
