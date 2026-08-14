import Foundation
import Network
import Synchronization

/// The HTTP/1.1 server the router serves on: loopback only, keep-alive, buffered request bodies and
/// streaming responses.
///
/// **Why this is not `LoopbackCallbackListener`.** R5's listener was read first, and three of its
/// decisions are carried over deliberately — the loopback pin through `requiredLocalEndpoint`
/// rather than `NWListener(using:on:)`, a bind failure that *throws* in the reference's
/// `listen EADDRINUSE` wording, and a head deadline so a silent client cannot pin a socket. What
/// does not generalise is everything else about it: it binds once per instance and refuses reuse,
/// it reads only a request line and never a body, it answers exactly one request per connection,
/// and it has no streaming. The router needs all four of those, and bending a single-shot OAuth
/// callback into a general server would have put the flow's proven termination behaviour at risk
/// for no gain.
///
/// **Each connection runs in its own `Task`.** The server actor tracks connections so shutdown can
/// reach them and does nothing else on the request path — a design where every request passed
/// through one actor would serialise the whole router behind the slowest tool call, which is the
/// opposite of what a shared endpoint for ten sessions is for.
public actor LoopbackHTTPServer {
    /// How long a connection may hold the socket without completing a request head. Node's
    /// `headersTimeout` default.
    static let headDeadlineNanoseconds: UInt64 = 60 * 1_000_000_000

    /// How long an idle keep-alive connection is kept before it is closed. Node's
    /// `keepAliveTimeout` default is 5 s, which is what the reference advertises in its own
    /// `Keep-Alive: timeout=5` header — so advertising it and then not honouring it would be a lie
    /// the client acts on.
    static let idleDeadlineNanoseconds: UInt64 = 5 * 1_000_000_000

    public typealias Handler = @Sendable (HTTPWireRequest) async -> HTTPWireResponse

    private let queue = DispatchQueue(
        label: "app.fledgeling.mcp-router.http", attributes: .concurrent
    )
    private var listener: NWListener?
    private var handler: Handler?
    private var onAccept: (@Sendable (ConnectionDescriptor) -> Void)?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var tasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var boundPortValue: Int?
    private var stopped = false

    public init() {}

    /// The port actually bound. Equal to the requested one in production; a test asks for 0 and
    /// reads back the ephemeral one rather than fighting whatever is on 8879.
    public var boundPort: Int? { boundPortValue }

    /// Bind and serve until ``stop()``.
    ///
    /// - Parameter onAccept: called the instant a connection is accepted, before any byte of its
    ///   request has been read. That timing is the whole point of the parameter: identifying the
    ///   caller asks the OS who owns the socket, so it can only answer while that process is alive,
    ///   and a one-shot client that fires a call and exits is lost if the lookup waits for the
    ///   request to finish parsing.
    public func start(
        port: Int,
        onAccept: (@Sendable (ConnectionDescriptor) -> Void)? = nil,
        handler: @escaping Handler
    ) async throws {
        guard listener == nil, !stopped else {
            throw RouterServiceError.alreadyStarted
        }
        guard let parameters = Self.loopbackParameters(port: port) else {
            throw RouterServiceError.listen("\(port) is not a bindable port")
        }

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw Self.listenFailure(port: port, error: error)
        }
        self.listener = listener
        self.handler = handler
        self.onAccept = onAccept

        listener.stateUpdateHandler = { [weak self] state in
            Task { await self?.listenerStateChanged(state, port: port) }
        }
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                startContinuation = continuation
                listener.start(queue: queue)
            }
        } catch {
            // Nothing stays half-bound: a listener that reported `.failed` still holds an intent to
            // bind, and leaving it would retry underneath a caller already told the bind failed.
            listener.cancel()
            self.listener = nil
            self.handler = nil
            throw error
        }
        boundPortValue = listener.port.map { Int($0.rawValue) }
    }

    /// Stop accepting, and close every live connection.
    ///
    /// Unlike R5's listener — which must leave an in-flight response alone, because the OAuth flow
    /// settles inside its own handler — this one closes everything. A router shutting down has no
    /// obligation to finish a tool call it can no longer serve, and leaving a connection open would
    /// hold the process past the point where launchd expects it to be gone.
    public func stop() async {
        stopped = true
        listener?.cancel()
        listener = nil
        let live = connections
        let running = tasks
        connections = [:]
        tasks = [:]
        for connection in live.values { connection.cancel() }
        for task in running.values { task.cancel() }
    }

    // MARK: - Binding

    /// Loopback pinned in the parameters, never `NWListener(using:on:)`, which binds every
    /// interface. This endpoint runs every MCP server the user owns with the user's environment;
    /// putting it on the LAN is the one bind mistake with no recoverable failure mode.
    ///
    /// IPv4 only, matching the reference's `listen(port, '127.0.0.1')`.
    static func loopbackParameters(port: Int) -> NWParameters? {
        guard let raw = UInt16(exactly: port), let endpointPort = NWEndpoint.Port(rawValue: raw) else {
            return nil
        }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback), port: endpointPort
        )
        // Explicit rather than inherited. With reuse allowed a second router binds the same port and
        // each receives half the traffic — two routers each serving some sessions, with no symptom
        // beyond tools intermittently vanishing.
        parameters.allowLocalEndpointReuse = false
        parameters.allowFastOpen = false
        return parameters
    }

    private func listenerStateChanged(_ state: NWListener.State, port: Int) {
        switch state {
        case .ready:
            resumeStart(with: nil)
        case let .failed(error):
            resumeStart(with: Self.listenFailure(port: port, error: error))
        case let .waiting(error):
            // A fixed loopback port has no legitimate transient wait, and a listener left waiting
            // would hang `start` forever rather than reporting the port is taken.
            resumeStart(with: Self.listenFailure(port: port, error: error))
        case .cancelled:
            resumeStart(with: RouterServiceError.listen("the listener was cancelled before it bound"))
        default:
            break
        }
    }

    private func resumeStart(with failure: Error?) {
        guard let continuation = startContinuation else { return }
        startContinuation = nil
        if let failure { continuation.resume(throwing: failure) } else { continuation.resume() }
    }

    /// The reference's message shape — `listen EADDRINUSE: address already in use 127.0.0.1:8879`.
    /// A user shown `nw_error 48` learns nothing about the port already being taken.
    static func listenFailure(port: Int, error: Error) -> RouterServiceError {
        guard case let NWError.posix(posix) = error else {
            return .listen("listen EFAILED: \(error) 127.0.0.1:\(port)")
        }
        let (code, detail): (String, String) = switch posix {
        case .EADDRINUSE: ("EADDRINUSE", "address already in use")
        case .EACCES: ("EACCES", "permission denied")
        case .EADDRNOTAVAIL: ("EADDRNOTAVAIL", "address not available")
        default: ("EPOSIX\(posix.rawValue)", String(describing: posix))
        }
        return .listen("listen \(code): \(detail) 127.0.0.1:\(port)")
    }

    // MARK: - Connections

    private func accept(_ connection: NWConnection) {
        guard listener != nil, let handler else {
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.start(queue: queue)

        let descriptor = ConnectionDescriptor(
            peer: Self.peerDescription(connection),
            acceptedAtMilliseconds: Date().timeIntervalSince1970 * 1000
        )
        onAccept?(descriptor)

        tasks[id] = Task { [weak self] in
            await Self.serve(connection: connection, descriptor: descriptor, handler: handler)
            await self?.forget(id)
        }
    }

    private func forget(_ id: ObjectIdentifier) {
        connections[id]?.cancel()
        connections[id] = nil
        tasks[id] = nil
    }

    static func peerDescription(_ connection: NWConnection) -> String {
        guard case let .hostPort(host, port) = connection.endpoint else {
            return String(describing: connection.endpoint)
        }
        return "\(host):\(port.rawValue)"
    }

    /// One connection's whole life: read a head, read its body, answer, repeat until the client
    /// leaves or a deadline passes.
    private static func serve(
        connection: NWConnection,
        descriptor: ConnectionDescriptor,
        handler: @escaping Handler
    ) async {
        let socket = HTTPSocket(connection: connection)
        var buffer = Data()
        var isFirstRequest = true

        while !Task.isCancelled {
            let deadline = isFirstRequest ? headDeadlineNanoseconds : idleDeadlineNanoseconds
            isFirstRequest = false

            let head: HTTPWire.ParsedHead
            do {
                head = try await readHead(socket: socket, buffer: &buffer, deadline: deadline)
            } catch {
                // A head that will never become a request, a client that went away, or a deadline.
                // None of the three has anyone waiting for an answer, so the connection is simply
                // dropped — which is what Node does for all three.
                break
            }

            let length: Int
            do {
                length = try HTTPWire.bodyLength(of: head)
            } catch {
                await socket.write(refusal(400, "the request framing could not be read"))
                break
            }

            var body = Data()
            if length > 0 {
                guard let read = await readBody(
                    socket: socket, buffer: &buffer, from: head.bodyOffset, length: length
                ) else { break }
                body = read
            }
            buffer.removeSubrange(buffer.startIndex ..< buffer.index(buffer.startIndex, offsetBy: head.bodyOffset + length))

            let request = HTTPWireRequest(
                method: head.method,
                target: head.target,
                httpVersion: head.httpVersion,
                headers: head.headers,
                body: body,
                connection: descriptor
            )
            let response = await handler(request)
            let delivered = await deliver(response, over: socket)
            // A client that asked to close gets closed. Ignoring `Connection: close` leaves the
            // socket open until the idle deadline, and a client that reads until the peer hangs up
            // — which is the simplest correct HTTP client, and the one the CLI verbs use — waits
            // the whole window for a response it already has.
            let asksToClose = (request.first("connection") ?? "").lowercased().contains("close")
            guard delivered, response.keepAlive, !asksToClose,
                  head.httpVersion != "HTTP/1.0" else { break }
        }
        connection.cancel()
    }

    private static func readHead(
        socket: HTTPSocket, buffer: inout Data, deadline: UInt64
    ) async throws -> HTTPWire.ParsedHead {
        let start = ContinuousClock.now
        let limit = ContinuousClock.Duration.nanoseconds(Int64(min(deadline, UInt64(Int64.max))))
        while true {
            do {
                return try HTTPWire.parseHead(buffer)
            } catch HTTPWire.ParseFailure.incomplete {
                guard ContinuousClock.now - start < limit else { throw HTTPWire.ParseFailure.incomplete }
                guard let chunk = await socket.read(timeoutNanoseconds: deadline), !chunk.isEmpty else {
                    throw HTTPWire.ParseFailure.incomplete
                }
                buffer.append(chunk)
            }
        }
    }

    private static func readBody(
        socket: HTTPSocket, buffer: inout Data, from offset: Int, length: Int
    ) async -> Data? {
        while buffer.count < offset + length {
            guard let chunk = await socket.read(timeoutNanoseconds: headDeadlineNanoseconds),
                  !chunk.isEmpty
            else { return nil }
            buffer.append(chunk)
        }
        let start = buffer.index(buffer.startIndex, offsetBy: offset)
        let end = buffer.index(start, offsetBy: length)
        return Data(buffer[start ..< end])
    }

    /// Write a response. Returns whether the whole thing reached the socket — a half-written
    /// response must not be followed by another one on the same connection.
    private static func deliver(_ response: HTTPWireResponse, over socket: HTTPSocket) async -> Bool {
        guard await socket.write(HTTPWire.head(for: response, now: Date())) else { return false }
        switch response.body {
        case let .bytes(data):
            if data.isEmpty { return true }
            return await socket.write(data)
        case let .chunks(stream):
            for await piece in stream where !piece.isEmpty {
                guard await socket.write(HTTPWire.chunk(piece)) else { return false }
            }
            return await socket.write(HTTPWire.lastChunk)
        }
    }

    private static func refusal(_ status: Int, _ message: String) -> Data {
        let body = Data("{\"error\":\"\(message)\"}".utf8)
        var response = HTTPWireResponse.json(status, body)
        response.keepAlive = false
        var out = HTTPWire.head(for: response, now: Date())
        out.append(body)
        return out
    }
}

/// `NWConnection`'s callback API as two `async` calls.
///
/// A separate type rather than free functions so the "resume exactly once" obligation lives in one
/// place: `NWConnection` invokes a completion once per call, and a continuation resumed twice traps
/// the process rather than returning an error.
final class HTTPSocket: Sendable {
    private let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    /// One chunk, or `nil` when the peer has gone or the deadline passed.
    func read(timeoutNanoseconds: UInt64) async -> Data? {
        await withTaskGroup(of: Data?.self, returning: Data?.self) { group in
            group.addTask { [connection] in
                await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
                    let box = OneShot(continuation)
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
                        data, _, isComplete, error in
                        if error != nil || (isComplete && (data?.isEmpty ?? true)) {
                            box.settle(nil)
                        } else {
                            box.settle(data)
                        }
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
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
