import Foundation
import MCP
import Synchronization
import Testing
@testable import RouterCore

/// The seams R3 plugs into, tested as contracts rather than as declarations.
///
/// Two things are being asserted here. First, that each seam is **sufficient** — a control handler
/// can see a query string, a streaming endpoint can stream, an authorizer can actually be handed to
/// the SDK. Each of those was missing in the first cut, and each would have forced R3 to edit R2's
/// files rather than conform to them. Second, that the inert defaults are correct on their own: an
/// unattached seam has to behave, not merely compile.
@Suite("Router seams")
struct SeamTests {
    // MARK: - Sufficiency

    @Test("a query string reaches the handler without disturbing the path it matches on")
    func queryIsCarriedBesideThePath() async {
        // The failure this prevents: fold the query into `path` and `claims("/usage")` stops
        // recognising `/usage?since=…`, so adding a parameter silently 404s a working endpoint.
        let handler = RecordingControlHandler(claimedPaths: ["/usage"])
        let request = ControlRequest(
            method: "GET",
            path: "/usage",
            rawQuery: "since=2026-08-01&limit=50",
            headers: ["accept": "application/json"]
        )

        #expect(handler.claims(path: request.path))
        let response = await handler.respond(to: request)
        #expect(response?.status == 200)
        #expect(handler.lastQuery == "since=2026-08-01&limit=50")
    }

    @Test("a streaming response delivers chunks as they are produced")
    func streamingResponseDeliversAsProduced() async {
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        let response = ControlResponse(status: 200, body: .stream(stream))

        guard case let .stream(body) = response.body else {
            Issue.record("expected a streaming body")
            return
        }

        continuation.yield(Data("first".utf8))
        var received: [String] = []
        var iterator = body.makeAsyncIterator()
        if let chunk = await iterator.next(), let text = String(bytes: chunk, encoding: .utf8) {
            received.append(text)
        }

        continuation.yield(Data("second".utf8))
        if let chunk = await iterator.next(), let text = String(bytes: chunk, encoding: .utf8) {
            received.append(text)
        }
        continuation.finish()

        #expect(received == ["first", "second"], "a buffered body would deliver both only at the end")
        #expect(await iterator.next() == nil, "finishing the stream ends the response")
    }

    @Test("a producer learns when the client stops reading, without a second cancellation channel")
    func streamProducerLearnsOfDisconnection() async throws {
        let gone = Mutex(false)
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        continuation.onTermination = { _ in gone.withLock { $0 = true } }

        // A disconnect, modelled the way a listener actually experiences one: the task consuming the
        // response is cancelled, which ends the iteration and terminates the stream.
        let consuming = Task {
            for await _ in stream {}
        }
        continuation.yield(Data("chunk".utf8))
        try await Task.sleep(nanoseconds: 30_000_000)
        consuming.cancel()

        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !gone.withLock({ $0 }), ContinuousClock.now < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(gone.withLock { $0 }, "an endless usage stream must stop when nobody is listening")
    }

    @Test("an authorizer from the seam is accepted where the SDK wants one")
    func authorizerIsUsableBySDKTransport() throws {
        // The point of naming the SDK's own protocol on the seam rather than an opaque `Sendable`:
        // an opaque type has to be cast at the point of use, and that cast would fail at the first
        // HTTP upstream rather than here.
        let authority = StubAuthority(authorizer: StubAuthorizer())
        let authorizer = try #require(authority.authorizer(for: "anything"))
        let endpoint = try #require(URL(string: "https://example.invalid/mcp"))

        _ = HTTPClientTransport(endpoint: endpoint, authorizer: authorizer)
        #expect(authorizer.authorizationHeader(for: endpoint) == "Bearer stub")
    }

    // MARK: - The inert defaults

    @Test("an unattached control handler 404s rather than falling through to the relay")
    func inertControlHandlerClaimsNothing() async {
        let handler = NoControlHandling()
        #expect(!handler.claims(path: "/servers"))
        #expect(await handler.respond(to: ControlRequest(method: "GET", path: "/servers")) == nil)
    }

    @Test("an unattached identifier answers unknown rather than failing the call")
    func inertIdentifierAnswersUnknown() async {
        let identifying = NoCallerIdentifying()
        let connection = ConnectionDescriptor(peer: "127.0.0.1:54321", acceptedAtMilliseconds: 0)
        identifying.prefetch(connection)
        #expect(await identifying.identity(for: connection) == .unknown)
    }

    @Test("an unattached observer swallows everything and cannot fail a call")
    func inertObserverSwallows() async {
        let observing = NoCallObserving()
        observing.record(
            CallEvent(
                timestamp: "2026-08-14T00:00:00.000Z",
                server: "a",
                tool: "t",
                ok: true,
                milliseconds: 1,
                cold: false
            )
        )
        await observing.flush()
    }

    @Test("an unattached authority authorizes nothing, which is not the same as failing")
    func inertAuthorityAuthorizesNothing() {
        let authority = NoUpstreamAuthorizing()
        #expect(authority.authorizer(for: "a") == nil)
        authority.challenge(upstreamName: "a", url: "https://example.invalid/authorize")
    }
}

/// A control handler that records what it was given.
private final class RecordingControlHandler: ControlHandling, Sendable {
    private let claimedPaths: Set<String>
    private let seen = Mutex<String?>(nil)

    init(claimedPaths: Set<String>) {
        self.claimedPaths = claimedPaths
    }

    var lastQuery: String? { seen.withLock { $0 } }

    func claims(path: String) -> Bool {
        claimedPaths.contains(path)
    }

    func respond(to request: ControlRequest) async -> ControlResponse? {
        seen.withLock { $0 = request.rawQuery }
        return ControlResponse(status: 200, body: Data())
    }
}

private struct StubAuthority: UpstreamAuthorizing {
    let authorizer: StubAuthorizer
    func authorizer(for upstreamName: String) -> (any HTTPClientAuthorizer)? {
        authorizer
    }

    func challenge(upstreamName: String, url: String) {}
}

/// A class because the SDK's protocol requires `AnyObject`; `Sendable` without `@unchecked` because
/// it stores nothing mutable, which is what the practices document asks for in place of a promise.
private final class StubAuthorizer: HTTPClientAuthorizer {
    let maxAuthorizationAttempts = 1

    func validateEndpointSecurity(for endpoint: URL) throws {}

    func authorizationHeader(for endpoint: URL) -> String? {
        "Bearer stub"
    }

    func handleChallenge(
        statusCode: Int,
        headers: [String: String],
        endpoint: URL,
        operationKey: String?,
        session: URLSession
    ) async throws -> Bool {
        false
    }

    func prepareAuthorization(for endpoint: URL, session: URLSession) async throws {}
}
