import Foundation
import Network
import Testing
@testable import RouterCore

/// The findings an adversarial completeness critic raised against the first cut of the listener,
/// each turned into the test that would have caught it.
///
/// Kept in one suite on purpose: a reader asking "what did the review actually change?" gets an
/// answer, and each test names the input that used to break.
@Suite("R5 auth — the listener's hostile inputs", .serialized)
struct CallbackHostileInputTests {
    private let server = JSString("linear")

    // MARK: - Absolute-form request targets

    @Test("an absolute-form target resolves to /callback, as the reference's URL parsing does")
    func absoluteFormPathname() {
        #expect(CallbackResponder.split("http://127.0.0.1:8880/callback?code=a").path == "/callback")
        #expect(CallbackResponder.pathname("http://127.0.0.1:8880/callback") == "/callback")
        #expect(CallbackResponder.pathname("http://127.0.0.1:8880") == "/")
        #expect(CallbackResponder.pathname("/callback") == "/callback")
        // The query still parses off the absolute form.
        let parsed = CallbackResponder.split("http://127.0.0.1:8880/callback?code=a&state=b")
        #expect(CallbackResponder.firstValue(of: "code", in: parsed.query) == "a")
    }

    @Test("a proxied browser's absolute-form callback completes the flow rather than 404ing")
    func absoluteFormCompletesTheFlow() async throws {
        let coordinator = AuthFlowCoordinator()
        let listener = LoopbackCallbackListener()
        let transport = FakeAuthTransport()
        _ = try await coordinator.begin(
            server: server, listener: listener, transport: transport, port: 0,
            authorizationURL: { "https://provider.example/authorize" }
        )
        let port = await listener.boundPort ?? 0

        // RFC 9112 §3.2.2: an origin server must accept this form, and a browser with a system
        // proxy and no localhost bypass sends it. Answering 404 would not fail the authorization —
        // B82 makes a 404 a non-termination — it would hang it until the five-minute timeout.
        let raw = try await RawHTTP.get(
            port: port, target: "http://127.0.0.1:\(port)/callback?code=proxied"
        )
        #expect(splitResponse(raw).head.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(splitResponse(raw).body == AuthPages.connected(server: server))
        let exchanged = await transport.finishedWith
        #expect(exchanged == ["proxied"])
    }

    // MARK: - Heads that never become a request

    @Test("a terminated head with no request line is unparseable, not merely incomplete")
    func unparseableHeads() {
        #expect(LoopbackCallbackListener.readTarget(in: Data("GET\r\n\r\n".utf8)) == .unparseable)
        #expect(LoopbackCallbackListener.readTarget(in: Data("\r\n\r\n".utf8)) == .unparseable)
        #expect(
            LoopbackCallbackListener.readTarget(in: Data("GET /x HTTP/1.1\r\n".utf8)) == .incomplete
        )
    }

    @Test("RFC 9112 §2.2 — a leading empty line is skipped, not treated as the request line")
    func leadingEmptyLineIsSkipped() {
        let head = Data("\r\nGET /callback?code=x HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n".utf8)
        // This is a real callback wearing a leading CRLF. Reading the empty line as the request
        // line loses it — and losing it is a hang, not a failure.
        #expect(LoopbackCallbackListener.readTarget(in: head) == .target("/callback?code=x"))
    }

    @Test("an unanswerable request is closed promptly instead of pinning the socket for 60 s")
    func unanswerableRequestIsClosed() async throws {
        let listener = LoopbackCallbackListener()
        try await listener.start(port: 0) { _ in
            CallbackReply(status: 200, contentType: "text/plain", body: "unreachable")
        }
        let port = await listener.boundPort ?? 0
        defer { Task { await listener.stop() } }

        let started = Date()
        let raw = try await RawHTTP.raw(port: port, request: "GET\r\n\r\n", timeout: 5)
        let elapsed = Date().timeIntervalSince(started)
        #expect(raw.isEmpty)
        // The head deadline is 60 s. Anything near it means both ends are waiting on each other,
        // which from outside looks exactly like a hung router.
        #expect(elapsed < 2)
    }

    // MARK: - The bind, proved against a socket rather than a configuration object

    @Test("the loopback pin is enforced by the socket, not merely requested in the parameters")
    func loopbackPinIsEnforcedBySocket() async throws {
        let listener = LoopbackCallbackListener()
        try await listener.start(port: 0) { _ in
            CallbackReply(status: 200, contentType: "text/plain", body: "reachable")
        }
        let port = await listener.boundPort ?? 0
        defer { Task { await listener.stop() } }

        // Loopback reaches it — otherwise the negative below proves nothing.
        let loopbackReached = await RawHTTP.canConnect(host: .loopback, port: port)
        #expect(loopbackReached)

        guard let lanAddress = firstNonLoopbackIPv4() else {
            // Recorded rather than passed silently: on a machine with no network interface this
            // question cannot be asked, and a vacuous pass is how a security property rots.
            Issue.record("no non-loopback IPv4 on this machine, so the negative case was not proved")
            return
        }
        let lanReached = await RawHTTP.canConnect(host: lanAddress, port: port)
        // The whole security argument for rendering provider-supplied `error` text unescaped
        // (spec §6) rests on this being false.
        #expect(!lanReached)
    }

    // MARK: - A request body

    @Test("a request with an unread body still receives its response")
    func requestWithABodyIsAnswered() async throws {
        let listener = LoopbackCallbackListener()
        try await listener.start(port: 0) { target in
            CallbackReply(status: 200, contentType: "text/plain", body: "answered:\(target)")
        }
        let port = await listener.boundPort ?? 0
        defer { Task { await listener.stop() } }

        // Closing a socket with unread bytes in the receive buffer can make the kernel send RST
        // rather than FIN, and a peer that receives RST first discards the response. Measured here
        // rather than reasoned about: a `response_mode=form_post` provider POSTs a body, and the
        // failure would be an invisible blank page.
        let body = "code=posted&state=xyz"
        let request = "POST /callback?code=posted HTTP/1.1\r\nHost: 127.0.0.1\r\n"
            + "Content-Type: application/x-www-form-urlencoded\r\n"
            + "Content-Length: \(body.utf8.count)\r\n\r\n" + body
        let raw = try await RawHTTP.raw(port: port, request: request)
        #expect(splitResponse(raw).head.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(splitResponse(raw).body == "answered:/callback?code=posted")
    }
}
