import Foundation
import Network
import Testing
@testable import RouterCore

/// The five terminations and the one non-termination, each driven over a real socket.
@Suite("R5 auth — the loopback callback listener's terminations", .serialized)
struct CallbackListenerTests {
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

    @Test("termination 1 — a real GET /callback?code= exchanges the code and serves the page")
    func codeIsExchangedOverTheWire() async throws {
        let coordinator = AuthFlowCoordinator()
        let listener = LoopbackCallbackListener()
        let transport = FakeAuthTransport()
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
        let port = try await beginFlow(coordinator, listener: listener, transport: FakeAuthTransport())
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
        let port = try await beginFlow(coordinator, listener: listener, transport: FakeAuthTransport())
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
        let transport = FakeAuthTransport()
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
        let port = try await beginFlow(coordinator, listener: listener, transport: FakeAuthTransport())
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
        let transport = FakeAuthTransport()
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
}
