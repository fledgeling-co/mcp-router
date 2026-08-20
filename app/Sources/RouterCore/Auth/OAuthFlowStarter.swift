import Foundation

/// The production ``AuthFlowStarting``: what `RouterService` hands `ControlDeps` so a non-stdio
/// `POST /servers/:name/auth` has a flow to begin.
///
/// Until this existed the only conformer to ``AuthTransport`` anywhere was a fake in the test
/// target, so `ControlAuthDispatch.authorize` took its `deps.authFlow == nil` guard and the route
/// answered 405 — the whole of the `control-auth-post-http` parity row.
///
/// It owns one ``AuthFlowCoordinator`` for the life of the process, which is what makes "at most
/// one flow, and a second supersedes the first" true across requests rather than within one.
public struct OAuthFlowStarter: AuthFlowStarting {
    private let coordinator: AuthFlowCoordinator
    private let store: FileAuthStore
    private let http: any OAuthHTTPPerforming
    private let clock: any RouterClock
    private let makeListener: @Sendable () -> any CallbackListening

    public init(
        coordinator: AuthFlowCoordinator,
        store: FileAuthStore,
        http: any OAuthHTTPPerforming = URLSessionOAuthHTTP(),
        clock: any RouterClock = SystemClock(),
        makeListener: @escaping @Sendable () -> any CallbackListening = {
            LoopbackCallbackListener()
        }
    ) {
        self.coordinator = coordinator
        self.store = store
        self.http = http
        self.clock = clock
        self.makeListener = makeListener
    }

    public func begin(server: JSString, upstream: UpstreamConfig) async throws -> LiveFlow {
        guard let url = upstream.url, !url.isEmpty else {
            throw AuthFailure("no url configured for \"\(server.string)\"")
        }
        // The reference's `urlReady` promise: `connect()` produces the authorization URL as a side
        // effect through the provider's redirect handler, and the coordinator races that against
        // its own 20-second budget. A box rather than a continuation because the coordinator may
        // ask for the value after it has already been produced.
        let box = AuthorizationURLBox()
        let transport = OAuthClient(
            server: server,
            serverURL: url,
            requestHeaders: upstream.headers,
            store: store,
            http: http,
            clock: clock,
            redirect: { await box.deliver($0) }
        )
        return try await coordinator.begin(
            server: server,
            listener: makeListener(),
            transport: transport,
            port: AuthPaths.bindablePort,
            authorizationURL: { try await box.value() }
        )
    }

    public func awaitCompletion(server: JSString) async throws {
        try await coordinator.awaitCompletion(server: server)
    }
}

/// One authorization URL, delivered once and readable afterwards.
///
/// The reference's `urlReady` is a promise, so a `.then` attached after it resolved still sees the
/// value. A bare `CheckedContinuation` would not: the coordinator arms the URL race *after* it has
/// already started `connect()`, so a fast provider can deliver the URL before anybody is waiting.
/// Losing it there would turn a working authorization into the 20-second "the server never produced
/// an authorization URL" rejection, intermittently and only under load.
///
/// **It also has to answer cancellation, and the first version did not.** ``AuthFlowCoordinator``
/// races this against a 20-second sleep inside a `withThrowingTaskGroup`; when the sleep wins, the
/// group cancels the remaining child and then **awaits** it. A continuation that cancellation
/// cannot resume is never resumed, so the group never returns and the whole control request hangs
/// — measured at 91 seconds and still going, against a route whose own budget is 20. Every path
/// where the provider does not produce a URL runs through that: an unreachable authorization
/// server, a refused registration, and the refresh branch this was found on.
actor AuthorizationURLBox {
    private var delivered: String?
    // swift-wire-exempt: an in-memory waiter table keyed by a UUID this file mints; nothing here is
    // serialised, ordered or sent anywhere.
    private var waiting: [UUID: CheckedContinuation<String, Error>] = [:]

    func deliver(_ url: String) {
        guard delivered == nil else { return }
        delivered = url
        let pending = waiting
        waiting = [:]
        for continuation in pending.values {
            continuation.resume(returning: url)
        }
    }

    func value() async throws -> String {
        if let delivered { return delivered }
        let ticket = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if let delivered {
                    continuation.resume(returning: delivered)
                } else {
                    waiting[ticket] = continuation
                }
            }
        } onCancel: {
            Task { await abandon(ticket) }
        }
    }

    private func abandon(_ ticket: UUID) {
        waiting.removeValue(forKey: ticket)?.resume(throwing: CancellationError())
    }
}
