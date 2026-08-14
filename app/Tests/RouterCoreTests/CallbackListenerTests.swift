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
private final class RawHTTP: @unchecked Sendable {
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
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [self] data, _, isComplete, error in
            if let data, !data.isEmpty {
                lock.lock()
                buffer.append(data)
                lock.unlock()
            }
            if isComplete || error != nil {
                finishWithBuffer()
                connection.cancel()
                return
            }
            read(connection)
        }
    }

    private func finishWithBuffer() {
        lock.lock()
        let text = String(decoding: buffer, as: UTF8.self)
        lock.unlock()
        finish(.success(text))
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        deadline?.cancel()
        deadline = nil
        lock.unlock()
        guard let continuation else { return }
        continuation.resume(with: result)
    }
}

/// The head and the body, split on the blank line. Neither is normalised.
private func splitResponse(_ raw: String) -> (head: String, body: String) {
    guard let range = raw.range(of: "\r\n\r\n") else { return (raw, "") }
    return (String(raw[raw.startIndex ..< range.lowerBound]), String(raw[range.upperBound...]))
}

// MARK: - The listener, against a real socket

@Suite("R5 auth — the loopback callback listener", .serialized)
struct CallbackListenerTests {
    private let server = JSString("linear")

    /// Begin a flow on a real, ephemeral loopback port and report the port it bound.
    ///
    /// Port 0 rather than 8880: a fixed port makes the suite fail on a machine where the user's own
    /// router is running, which is the machine this is most likely to be run on.
    private func beginFlow(
        _ coordinator: AuthFlowCoordinator,
        listener: LoopbackCallbackListener,
        transport: FakeTransport
    ) async throws -> Int {
        _ = try await coordinator.begin(
            server: server, listener: listener, transport: transport, port: 0,
            authorizationURL: { "https://provider.example/authorize" }
        )
        let port = await listener.boundPort
        #expect(port != nil && port != 0)
        return port ?? 0
    }

    /// Observe the flow's outcome, carrying the rejection's own message — B86 turns on the
    /// difference between the message rendered into the page and the message the rejection carries.
    private func observe(_ coordinator: AuthFlowCoordinator, _ settled: SettledFlag) async throws {
        Task {
            do {
                try await coordinator.awaitCompletion(server: server)
                await settled.set("resolved")
            } catch is AuthAbandoned {
                await settled.set("abandoned")
            } catch {
                await settled.set("rejected:\((error as? AuthFailure)?.message ?? "?")")
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }

    @Test("termination 1 — a real GET /callback?code= exchanges the code and serves the page")
    func codeIsExchangedOverTheWire() async throws {
        let coordinator = AuthFlowCoordinator()
        let listener = LoopbackCallbackListener()
        let transport = FakeTransport()
        let port = try await beginFlow(coordinator, listener: listener, transport: transport)
        let settled = SettledFlag()
        try await observe(coordinator, settled)

        let raw = try await RawHTTP.get(port: port, target: "/callback?code=abc123&state=xyz")
        let (head, body) = splitResponse(raw)

        #expect(head.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(head.contains("content-type: text/html"))
        #expect(body == AuthPages.connected(server: server))
        let exchanged = await transport.finishedWith
        #expect(exchanged == ["abc123"])

        try await Task.sleep(nanoseconds: 150_000_000)
        let outcome = await settled.value()
        #expect(outcome == "resolved")
        let live = await coordinator.currentFlow()
        #expect(live == nil)
    }

    @Test("termination 2 — a provider error renders its detail verbatim and rejects with it")
    func providerErrorOverTheWire() async throws {
        let coordinator = AuthFlowCoordinator()
        let listener = LoopbackCallbackListener()
        let port = try await beginFlow(coordinator, listener: listener, transport: FakeTransport())
        let settled = SettledFlag()
        try await observe(coordinator, settled)

        let raw = try await RawHTTP.get(port: port, target: "/callback?error=access_denied")
        let (head, body) = splitResponse(raw)

        #expect(head.hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
        #expect(head.contains("content-type: text/html"))
        #expect(body == AuthPages.failed(detail: "access_denied"))

        try await Task.sleep(nanoseconds: 150_000_000)
        let outcome = await settled.value()
        #expect(outcome == "rejected:access_denied")
    }

    @Test("termination 3 — B86's two different strings, one rendered and one rejected with")
    func noCodeOverTheWire() async throws {
        let coordinator = AuthFlowCoordinator()
        let listener = LoopbackCallbackListener()
        let port = try await beginFlow(coordinator, listener: listener, transport: FakeTransport())
        let settled = SettledFlag()
        try await observe(coordinator, settled)

        let raw = try await RawHTTP.get(port: port, target: "/callback")
        let (head, body) = splitResponse(raw)

        #expect(head.hasPrefix("HTTP/1.1 400 Bad Request\r\n"))
        #expect(body == AuthPages.failed(detail: AuthPages.noCodePageDetail))
        #expect(body.contains("the provider returned no code"))

        try await Task.sleep(nanoseconds: 150_000_000)
        let outcome = await settled.value()
        // The page says one thing and the rejection says another. A port that reuses one string for
        // both passes every byte assertion above and still logs the wrong line.
        #expect(outcome == "rejected:no authorization code returned")
    }

    @Test("termination 4 — a failing token exchange serves 500 with the thrown message")
    func exchangeFailureOverTheWire() async throws {
        let coordinator = AuthFlowCoordinator()
        let listener = LoopbackCallbackListener()
        let transport = FakeTransport()
        await transport.setFinishAuthError(AuthFailure("the token endpoint refused the code"))
        let port = try await beginFlow(coordinator, listener: listener, transport: transport)
        let settled = SettledFlag()
        try await observe(coordinator, settled)

        let raw = try await RawHTTP.get(port: port, target: "/callback?code=abc123")
        let (head, body) = splitResponse(raw)

        #expect(head.hasPrefix("HTTP/1.1 500 Internal Server Error\r\n"))
        #expect(body == AuthPages.failed(detail: "the token endpoint refused the code"))

        try await Task.sleep(nanoseconds: 150_000_000)
        let outcome = await settled.value()
        #expect(outcome == "rejected:the token endpoint refused the code")
    }

    @Test("termination 5 — the timeout writes no page and releases the socket")
    func timeoutReleasesTheSocket() async throws {
        let coordinator = AuthFlowCoordinator(flowTimeoutMilliseconds: 150)
        let listener = LoopbackCallbackListener()
        let port = try await beginFlow(coordinator, listener: listener, transport: FakeTransport())
        let settled = SettledFlag()
        try await observe(coordinator, settled)

        try await Task.sleep(nanoseconds: 400_000_000)
        let outcome = await settled.value()
        #expect(outcome == "rejected:authorization timed out")

        // No page is rendered because there is no request to render one to — what is observable is
        // that the port stopped answering, which is the cleanup this termination owes.
        await #expect(throws: (any Error).self) {
            _ = try await RawHTTP.get(port: port, target: "/callback?code=late", timeout: 2)
        }
    }

    @Test("B82 — a stray request answers 404 with no content-type and ends nothing")
    func strayRequestOverTheWire() async throws {
        let coordinator = AuthFlowCoordinator()
        let listener = LoopbackCallbackListener()
        let transport = FakeTransport()
        let port = try await beginFlow(coordinator, listener: listener, transport: transport)
        let settled = SettledFlag()
        try await observe(coordinator, settled)

        let raw = try await RawHTTP.get(port: port, target: "/favicon.ico")
        let (head, body) = splitResponse(raw)

        #expect(head.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        #expect(!head.lowercased().contains("content-type"))
        #expect(head.contains("content-length: 0"))
        #expect(body.isEmpty)

        // Nothing settled, nothing was torn down: the flow is still live and the socket still bound.
        try await Task.sleep(nanoseconds: 100_000_000)
        let midOutcome = await settled.value()
        #expect(midOutcome == nil)
        let live = await coordinator.currentFlow()
        #expect(live?.server == server)

        // And the real callback still lands afterwards, on the same still-bound socket.
        let second = try await RawHTTP.get(port: port, target: "/callback?code=late")
        #expect(splitResponse(second).head.hasPrefix("HTTP/1.1 200 OK\r\n"))
        try await Task.sleep(nanoseconds: 150_000_000)
        let outcome = await settled.value()
        #expect(outcome == "resolved")
    }

    @Test("B84 — binding a port already in use throws, and the flow cleans up nothing")
    func bindFailureThrowsWithoutCleanup() async throws {
        let holder = LoopbackCallbackListener()
        try await holder.start(port: 0) { _ in CallbackReply(status: 404, contentType: nil, body: "") }
        let port = await holder.boundPort ?? 0
        #expect(port != 0)
        defer { Task { await holder.stop() } }

        // Directly: the message the app will show for a port that is already taken.
        let second = LoopbackCallbackListener()
        var thrown: String?
        do {
            try await second.start(port: port) { _ in CallbackReply(status: 404, contentType: nil, body: "") }
        } catch {
            thrown = (error as? AuthFailure)?.message
        }
        #expect(thrown == "listen EADDRINUSE: address already in use 127.0.0.1:\(port)")

        // Through the flow: B84's first pre-flow failure performs NO cleanup — the transport is
        // left unclosed, which is what separates it from the URL-race failure below.
        let coordinator = AuthFlowCoordinator()
        let transport = FakeTransport()
        await #expect(throws: AuthFailure.self) {
            _ = try await coordinator.begin(
                server: server, listener: LoopbackCallbackListener(), transport: transport,
                port: port, authorizationURL: { "https://provider.example/authorize" }
            )
        }
        let closed = await transport.closed
        #expect(closed == false)
    }

    @Test("B84 — the URL race cleans up, and the cleanup gives the port back")
    func urlRaceReleasesThePort() async throws {
        let coordinator = AuthFlowCoordinator(urlTimeoutMilliseconds: 100)
        let listener = LoopbackCallbackListener()
        let transport = FakeTransport()
        await #expect(throws: AuthFailure.self) {
            _ = try await coordinator.begin(
                server: server, listener: listener, transport: transport, port: 0,
                authorizationURL: {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                    return "https://provider.example/authorize"
                }
            )
        }
        let port = await listener.boundPort ?? 0
        #expect(port != 0)

        // The socket is genuinely gone, not merely marked stopped: another listener can take it.
        let replacement = LoopbackCallbackListener()
        try await replacement.start(port: port) { _ in
            CallbackReply(status: 404, contentType: nil, body: "")
        }
        await replacement.stop()

        let closed = await transport.closed
        #expect(closed == true)
    }

    @Test("stop() does not return until the socket is free")
    func stopReleasesTheSocket() async throws {
        // Ten cycles rather than one, and the reason is measured: with `stop()` reverted to a bare
        // `NWListener.cancel()` a single rebind fails only about half the time, so a one-shot test
        // would be a guard that passes on the broken code every other run. Ten consecutive rebinds
        // of the same port turn "usually catches it" into "catches it", and cost about a
        // millisecond each.
        var port = 0
        for cycle in 0 ..< 10 {
            let listener = LoopbackCallbackListener()
            try await listener.start(port: port) { _ in
                CallbackReply(status: 404, contentType: nil, body: "")
            }
            if cycle == 0 {
                port = await listener.boundPort ?? 0
                #expect(port != 0)
            }
            // Serve one request first. A listener that has accepted a connection has real teardown
            // to do, which is the state a *completed* flow leaves behind — and the state in which an
            // unwaited cancel loses the race most reliably.
            _ = try await RawHTTP.get(port: port, target: "/x")
            // The very next line, with no sleep and no retry — which is how supersession rebinds.
            await listener.stop()
        }
    }

    @Test("B85 — a second flow takes over the same fixed port and answers on it")
    func supersessionRebindsTheFixedPort() async throws {
        // Borrow a free port and then treat it as *fixed*, which is what production does with 8880:
        // both flows bind the same number, so the first must be off it before the second arrives.
        let probe = LoopbackCallbackListener()
        try await probe.start(port: 0) { _ in CallbackReply(status: 404, contentType: nil, body: "") }
        let port = await probe.boundPort ?? 0
        await probe.stop()

        let coordinator = AuthFlowCoordinator()
        _ = try await coordinator.begin(
            server: JSString("alpha"), listener: LoopbackCallbackListener(),
            transport: FakeTransport(), port: port, authorizationURL: { "https://a.example" }
        )
        let second = LoopbackCallbackListener()
        _ = try await coordinator.begin(
            server: JSString("beta"), listener: second, transport: FakeTransport(),
            port: port, authorizationURL: { "https://b.example" }
        )
        let live = await coordinator.currentFlow()
        #expect(live?.server == JSString("beta"))

        // The socket answering is the new flow's, not a stale one left bound by the old.
        let raw = try await RawHTTP.get(port: port, target: "/callback?code=beta-code")
        #expect(splitResponse(raw).body == AuthPages.connected(server: JSString("beta")))
        await second.stop()
    }

    @Test("a request split across TCP segments is still answered")
    func splitRequestIsAnswered() async throws {
        let listener = LoopbackCallbackListener()
        try await listener.start(port: 0) { target in
            CallbackReply(status: 200, contentType: "text/plain", body: target)
        }
        let port = await listener.boundPort ?? 0
        defer { Task { await listener.stop() } }

        let connection = NWConnection(
            host: .ipv4(.loopback),
            // A test force-unwrap is a deliberate assertion: the port was just bound.
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: .tcp
        )
        let reply = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let box = ResponseBox(continuation)
            connection.stateUpdateHandler = { state in
                guard case .ready = state else {
                    if case let .failed(error) = state { box.fail(error) }
                    return
                }
                // Two segments, with the split mid-target — the head arrives in pieces.
                connection.send(
                    content: Data("GET /callback?co".utf8),
                    completion: .contentProcessed { _ in
                        connection.send(
                            content: Data("de=split HTTP/1.1\r\nHost: x\r\n\r\n".utf8),
                            completion: .contentProcessed { _ in }
                        )
                    }
                )
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                    box.succeed(String(decoding: data ?? Data(), as: UTF8.self))
                    connection.cancel()
                }
            }
            connection.start(queue: .global())
        }
        #expect(splitResponse(reply).body == "/callback?code=split")
    }
}

/// Resume-once box for the split-segment test's continuation.
private final class ResponseBox: @unchecked Sendable {
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

// MARK: - The parts that need no socket

@Suite("R5 auth — the callback listener's wire format")
struct CallbackWireTests {
    @Test("the page responses carry content-type, a byte-counted length, and close")
    func pageResponseBytes() {
        let wire = LoopbackCallbackListener.wire(
            for: CallbackReply(status: 200, contentType: "text/html", body: "<p>hi</p>")
        )
        #expect(wire == "HTTP/1.1 200 OK\r\ncontent-type: text/html\r\ncontent-length: 9\r\n"
            + "connection: close\r\n\r\n<p>hi</p>")
    }

    @Test("B82 — the 404 carries no content-type and no body")
    func notFoundBytes() {
        let wire = LoopbackCallbackListener.wire(
            for: CallbackReply(status: 404, contentType: nil, body: "")
        )
        #expect(wire == "HTTP/1.1 404 Not Found\r\ncontent-length: 0\r\nconnection: close\r\n\r\n")
        #expect(!wire.lowercased().contains("content-type"))
    }

    @Test("content-length counts UTF-8 bytes, not characters")
    func contentLengthIsBytes() {
        // The failure pages render a provider-supplied detail verbatim, and a provider writes in its
        // own language. Counting characters truncates the page in the browser by exactly the number
        // of multi-byte characters in it — which renders as a page that is subtly cut off.
        let wire = LoopbackCallbackListener.wire(
            for: CallbackReply(status: 400, contentType: "text/html", body: "é☃")
        )
        #expect(wire.contains("content-length: 5\r\n"))
    }

    @Test("the status lines are the reference's, and an unmapped status reads 'unknown'")
    func statusReasons() {
        #expect(LoopbackCallbackListener.reason(for: 200) == "OK")
        #expect(LoopbackCallbackListener.reason(for: 400) == "Bad Request")
        #expect(LoopbackCallbackListener.reason(for: 404) == "Not Found")
        #expect(LoopbackCallbackListener.reason(for: 500) == "Internal Server Error")
        #expect(LoopbackCallbackListener.reason(for: 418) == "unknown")
    }

    @Test("the bind is pinned to IPv4 loopback, never every interface")
    func bindIsLoopbackOnly() throws {
        let parameters = try #require(LoopbackCallbackListener.loopbackParameters(port: 8880))
        let endpoint = try #require(parameters.requiredLocalEndpoint)
        guard case let .hostPort(host, port) = endpoint else {
            Issue.record("the local endpoint is not a host/port")
            return
        }
        // Binding every interface would put the callback — and the unescaped page it renders from a
        // provider-supplied `error`, spec §6 — on the LAN.
        #expect(host == .ipv4(.loopback))
        #expect(port.rawValue == 8880)
        #expect(parameters.allowLocalEndpointReuse == false)
    }

    @Test("a port outside the bindable range is refused rather than truncated")
    func unbindablePorts() {
        #expect(LoopbackCallbackListener.loopbackParameters(port: 65536) == nil)
        #expect(LoopbackCallbackListener.loopbackParameters(port: -1) == nil)
        #expect(LoopbackCallbackListener.loopbackParameters(port: 65535) != nil)
    }

    @Test("the request target is read only once the head is terminated")
    func requestTargetNeedsAWholeHead() {
        let partial = Data("GET /callback?code=a HTTP/1.1\r\nHost: 127.0.0.1\r\n".utf8)
        #expect(LoopbackCallbackListener.requestTarget(in: partial) == nil)

        let whole = Data("GET /callback?code=a HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
        #expect(LoopbackCallbackListener.requestTarget(in: whole) == "/callback?code=a")
    }

    @Test("bare-LF line endings are read, as Node's parser reads them")
    func bareLineFeedHead() {
        let whole = Data("GET /callback?code=b HTTP/1.1\nHost: 127.0.0.1\n\n".utf8)
        #expect(LoopbackCallbackListener.requestTarget(in: whole) == "/callback?code=b")
    }

    @Test("a request line with no target is not answered")
    func malformedRequestLine() {
        let whole = Data("GET\r\n\r\n".utf8)
        #expect(LoopbackCallbackListener.requestTarget(in: whole) == nil)
    }

    @Test("any method reaches the handler, as the reference's handler accepts any")
    func methodIsNotFiltered() {
        let whole = Data("POST /callback?code=c HTTP/1.1\r\n\r\n".utf8)
        #expect(LoopbackCallbackListener.requestTarget(in: whole) == "/callback?code=c")
    }
}
