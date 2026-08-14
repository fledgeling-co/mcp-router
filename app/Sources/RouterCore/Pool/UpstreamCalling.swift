import Foundation
import Logging
import MCP
import Synchronization

/// Calling a live upstream, with the response's **bytes** preserved.
///
/// The problem this solves is specific and was measured rather than anticipated. The pinned SDK
/// decodes every result into `MCP.Value`, whose object case is `[String: Value]` — an unordered
/// dictionary. A `tools/call` result therefore comes back with its member order destroyed, and
/// re-serialising it produces bytes the reference does not produce. Since the whole point of §4.3
/// is that the relay's output can be diffed against the reference **byte for byte** rather than
/// after key-sorting, losing order at the upstream boundary would defeat it one layer down.
///
/// So the SDK keeps everything it is good at — framing, the `initialize` handshake, request
/// correlation, timeouts — and this adds one thing: a transport decorator that keeps a copy of each
/// response's raw bytes, looked up afterwards by the request id we chose ourselves. The bytes are
/// then parsed by R1's ``JSONParser``, which preserves member order, and travel to the wire through
/// ``JSStringify``.
/// A `tools/list` or `tools/call` request whose parameters and result are both dynamic.
///
/// `Value` on both sides so the SDK neither validates nor reshapes what an upstream sends. The
/// decoded value is discarded — it exists only to make the SDK's request machinery run — and the
/// answer is read out of the tap instead.
struct RawMethod<Name: RawMethodName>: MCP.Method {
    typealias Parameters = Value
    typealias Result = Value
    static var name: String { Name.methodName }
}

protocol RawMethodName: Sendable {
    static var methodName: String { get }
}

enum RawListTools: RawMethodName {
    static let methodName = "tools/list"
}

enum RawCallTool: RawMethodName {
    static let methodName = "tools/call"
}

/// Keeps the raw bytes of each JSON-RPC response, keyed by its id.
///
/// Bounded on purpose: a long-lived upstream answering thousands of calls would otherwise grow this
/// map forever. Every entry is removed as soon as it is claimed, and an unclaimed entry — a response
/// to a request whose caller was cancelled — is evicted oldest-first past the cap.
final class ResponseTap: Sendable {
    static let capacity = 64

    private struct State {
        var bytes: [String: Data] = [:]
        var order: [String] = []
    }

    private let state = Mutex(State())

    func record(_ data: Data) {
        guard let id = Self.identifier(in: data) else { return }
        state.withLock { current in
            if current.bytes[id] == nil { current.order.append(id) }
            current.bytes[id] = data
            while current.order.count > Self.capacity {
                let oldest = current.order.removeFirst()
                current.bytes[oldest] = nil
            }
        }
    }

    /// Take the bytes for this id, removing them.
    func claim(_ id: String) -> Data? {
        state.withLock { current in
            current.order.removeAll { $0 == id }
            return current.bytes.removeValue(forKey: id)
        }
    }

    /// The `id` member, read with R1's parser so a string id and a numeric one are distinguished
    /// the way the wire distinguishes them.
    private static func identifier(in data: Data) -> String? {
        guard case let .object(members)? = try? JSONParser.parse(data) else { return nil }
        guard let id = members.first(where: { $0.key == JSString("id") })?.value else { return nil }
        switch id {
        case let .string(text): return "s:\(text.string)"
        case let .number(value): return "n:\(JSNumber.string(value))"
        default: return nil
        }
    }

    /// The same key, derived from the id we are about to send.
    static func key(for id: ID) -> String {
        switch id {
        case let .string(text): "s:\(text)"
        case let .number(value): "n:\(JSNumber.string(Double(value)))"
        }
    }
}

/// A `Transport` that forwards everything and keeps a copy of each response.
///
/// An actor because `Transport` requires one. It owns no framing of its own: `send` and `connect`
/// pass straight through, and `receive` re-publishes the wrapped stream so the SDK sees exactly what
/// it would have seen.
actor TappingTransport: Transport {
    nonisolated let logger: Logger
    private let wrapped: any Transport
    nonisolated let tap: ResponseTap

    /// The wrapped transport's `logger` is actor-isolated and cannot be read from here, so this
    /// carries its own. It is the no-op handler the SDK's own transports default to, which is what
    /// keeps upstream traffic out of the router's log — `SWIFT_PRACTICES.md` §6 forbids logging a
    /// whole payload, and an MCP frame can carry a credential an upstream was configured with.
    init(wrapping transport: any Transport, tap: ResponseTap) {
        wrapped = transport
        self.tap = tap
        logger = Logger(label: "mcp-router.upstream", factory: { _ in SwiftLogNoOpLogHandler() })
    }

    func connect() async throws {
        try await wrapped.connect()
    }

    func disconnect() async {
        await wrapped.disconnect()
    }

    func send(_ data: Data) async throws {
        try await wrapped.send(data)
    }

    nonisolated func receive() -> AsyncThrowingStream<Data, Swift.Error> {
        let upstream = wrapped
        let tap = tap
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await message in await upstream.receive() {
                        tap.record(message)
                        continuation.yield(message)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Issuing one raw request and reading its answer out of the tap.
enum RawRequest {
    /// The `result` member of the response, with member order intact.
    ///
    /// The SDK's decoded value is deliberately ignored: awaiting it is what makes the exchange
    /// happen and what surfaces a JSON-RPC error as a thrown Swift error, but the value it carries
    /// has already lost the ordering this router needs.
    static func perform<Name: RawMethodName>(
        _: Name.Type,
        client: Client,
        tap: ResponseTap,
        parameters: JSONValue
    ) async throws -> JSONValue {
        let id = ID.random
        let request = RawMethod<Name>.request(id: id, Self.value(parameters))
        let context = try await client.send(request)
        _ = try await context.value

        guard let bytes = tap.claim(ResponseTap.key(for: id)) else {
            throw PoolError.spawnFailed(
                name: Name.methodName,
                reason: "the upstream's response was not captured"
            )
        }
        guard case let .object(members) = try JSONParser.parse(bytes),
              let result = members.first(where: { $0.key == JSString("result") })?.value
        else {
            throw PoolError.spawnFailed(
                name: Name.methodName,
                reason: "the upstream's response carried no result"
            )
        }
        return result
    }

    /// R1's value into the SDK's. Member order is lost here and it does not matter: this direction
    /// is a request **this** router composes, and the reference composes its own independently, so
    /// there is no byte to agree on.
    static func value(_ json: JSONValue) -> Value {
        switch json {
        case .null: .null
        case let .bool(flag): .bool(flag)
        case let .number(number):
            // Whole numbers inside the range a Double represents exactly go across as integers;
            // everything else stays a double rather than being silently truncated.
            if number == number.rounded(), abs(number) < 9.007e15 {
                .int(Int(number))
            } else {
                .double(number)
            }
        case let .string(text): .string(text.string)
        case let .array(items): .array(items.map(value))
        case let .object(members):
            .object(Dictionary(members.map { ($0.key.string, value($0.value)) }) { _, last in last })
        }
    }
}
