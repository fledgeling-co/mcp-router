import Foundation
import Network
import Testing
@testable import RouterCore

/// Binding, rebinding and teardown — the half of the listener that has no page to render.
@Suite("R5 auth — the loopback callback listener's lifecycle", .serialized)
struct CallbackLifecycleTests {
    private let server = JSString("linear")

    private func beginFlow(
        _ coordinator: AuthFlowCoordinator,
        listener: LoopbackCallbackListener,
        transport: FakeAuthTransport
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
        let transport = FakeAuthTransport()
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
        let transport = FakeAuthTransport()
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
            transport: FakeAuthTransport(), port: port, authorizationURL: { "https://a.example" }
        )
        let second = LoopbackCallbackListener()
        _ = try await coordinator.begin(
            server: JSString("beta"), listener: second, transport: FakeAuthTransport(),
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

        let endpointPort = try #require(NWEndpoint.Port(rawValue: UInt16(port)))
        let connection = NWConnection(host: .ipv4(.loopback), port: endpointPort, using: .tcp)
        let reply: String = try await withCheckedThrowingContinuation { continuation in
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
                    box.succeed(String(bytes: data ?? Data(), encoding: .utf8) ?? "")
                    connection.cancel()
                }
            }
            connection.start(queue: .global())
        }
        #expect(splitResponse(reply).body == "/callback?code=split")
    }

    @Test("a connection accepted before stop() is still answered after it")
    func lateRequestOnAnOpenConnectionIsAnswered() async throws {
        let listener = LoopbackCallbackListener()
        try await listener.start(port: 0) { target in
            CallbackReply(status: 200, contentType: "text/plain", body: "late:\(target)")
        }
        let port = await listener.boundPort ?? 0
        let endpointPort = try #require(NWEndpoint.Port(rawValue: UInt16(port)))
        let connection = NWConnection(host: .ipv4(.loopback), port: endpointPort, using: .tcp)

        // Connect, and let the accept land on the actor before anything else happens.
        let ready: String = try await withCheckedThrowingContinuation { continuation in
            let box = ResponseBox(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: box.succeed("ready")
                case let .failed(error): box.fail(error)
                case let .waiting(error): box.fail(error)
                default: break
                }
            }
            connection.start(queue: .global())
        }
        #expect(ready == "ready")
        try await Task.sleep(nanoseconds: 50_000_000)

        // The listener stops with the connection open — which is exactly what a settle does, since
        // cleanup runs while the browser is still holding the socket it will send on.
        await listener.stop()

        // Node's `server.close()` stops accepting and still hands this request to the handler.
        let reply: String = try await withCheckedThrowingContinuation { continuation in
            let box = ResponseBox(continuation)
            connection.send(
                content: Data("GET /callback?code=late HTTP/1.1\r\nHost: x\r\n\r\n".utf8),
                completion: .contentProcessed { _ in }
            )
            connection.receiveWholeResponse { data, _, _ in
                box.succeed(String(bytes: data ?? Data(), encoding: .utf8) ?? "")
            }
        }
        #expect(splitResponse(reply).body == "late:/callback?code=late")
        connection.cancel()
    }
}
