import Foundation

/// The transport a flow drives, kept a **parameter** exactly as the reference has it
/// (`makeTransport`), so R2's SDK-backed implementation lands without editing this module. R5 ships
/// the protocol and a double, not a live transport.
public protocol AuthTransport: Sendable {
    /// Expected to fail: the provider redirects rather than returning tokens, and the SDK surfaces
    /// that as an unauthorized error. The authorization URL is the actual output, delivered through
    /// the redirect handler.
    func connect() async throws
    func finishAuth(code: String) async throws
    func close() async
}

/// The loopback listener, behind a protocol so every termination is testable without binding a port.
public protocol CallbackListening: Sendable {
    /// Binds `port` on 127.0.0.1. Throws when the port cannot be bound — the reference's
    /// `callback.once('error', reject)` path, which notably performs **no cleanup** (B84).
    func start(
        port: Int,
        handler: @escaping @Sendable (String) async -> CallbackReply
    ) async throws
    func stop() async
}

/// One in-progress browser authorization.
public struct LiveFlow: Sendable, Equatable {
    public let server: JSString
    public let url: String
}

/// `beginAuth` / `currentFlow` / `cancel`, and the terminations.
///
/// An actor because the reference's `current` is module-global mutable state, which Swift 6 strict
/// concurrency will not allow as a bare `static var`. The actor is the smallest thing that keeps the
/// same single-flow-at-a-time semantics.
public actor AuthFlowCoordinator {
    /// Everything one flow needs to tear itself down, plus the identity `cleanup` is guarded on.
    private struct Running {
        let server: JSString
        var url: String
        let listener: any CallbackListening
        let transport: any AuthTransport
        var timeoutTask: Task<Void, Never>?
        /// Resumed exactly once, or — for a superseded flow — **never** (B85).
        var completion: CheckedContinuation<Void, Error>?
    }

    private var current: Running?
    private let log: RouterLog?
    private let urlTimeoutMilliseconds: Double
    private let flowTimeoutMilliseconds: Double

    public init(
        log: RouterLog? = nil,
        urlTimeoutMilliseconds: Double = 20000,
        flowTimeoutMilliseconds: Double = 300_000
    ) {
        self.log = log
        self.urlTimeoutMilliseconds = urlTimeoutMilliseconds
        self.flowTimeoutMilliseconds = flowTimeoutMilliseconds
    }

    /// `currentFlow()` — the live flow, or nil.
    public func currentFlow() -> LiveFlow? {
        guard let current else { return nil }
        return LiveFlow(server: current.server, url: current.url)
    }

    /// The reference's `cleanup`: clear the timer, close the listener, close the transport, and
    /// clear `current` **only when it is still this flow** (B96).
    ///
    /// It deliberately does **not** settle. That is what makes a superseded flow's completion hang
    /// forever in the reference, and B85 requires the same here.
    private func cleanup(server: JSString) async {
        guard let running = current, running.server == server else {
            // A late cleanup from a flow that has already been replaced. Tear down nothing that
            // belongs to the flow now running — this guard is the whole point of B96.
            return
        }
        running.timeoutTask?.cancel()
        await running.listener.stop()
        await running.transport.close()
        current = nil
    }

    /// Settle the live flow, then clean up. Used by every termination that *does* settle.
    private func settle(server: JSString, with result: Result<Void, Error>) async {
        guard var running = current, running.server == server else { return }
        let continuation = running.completion
        running.completion = nil
        current = running
        switch result {
        case .success: continuation?.resume()
        case let .failure(error): continuation?.resume(throwing: error)
        }
        await cleanup(server: server)
    }

    /// `flow.cancel()` — the **only** path that settles a flow with an error from outside.
    public func cancel() async {
        guard let running = current else { return }
        await settle(server: running.server, with: .failure(AuthFailure("cancelled")))
    }

    /// `beginAuth(serverName, makeTransport, timeoutMs)`.
    ///
    /// Returns the flow once the authorization URL is known. Throws — and the route turns that into
    /// a 502 (B77) — on either pre-flow failure (B84).
    public func begin(
        server: JSString,
        listener: any CallbackListening,
        transport: any AuthTransport,
        port: Int?,
        authorizationURL: @escaping @Sendable () async throws -> String
    ) async throws -> LiveFlow {
        // `current?.close()` — cleanup, NOT cancel. The superseded flow is torn down and its
        // completion is left un-resumed forever, which is precisely the reference's behaviour and
        // why a Swift port using structured cancellation would diverge (B85).
        if let running = current {
            await cleanup(server: running.server)
        }

        guard let port else {
            throw AuthFailure("the callback port is not a bindable port")
        }

        let responder = CallbackResponder(server: server, log: log) { [weak self] code in
            guard let self else { return }
            try await self.exchange(server: server, code: code)
        }

        // Bind first. A failure here performs NO cleanup — no timer has been armed yet, and the
        // transport is left unclosed, matching `callback.once('error', reject)` exactly (B84).
        do {
            try await listener.start(port: port) { [weak self] target in
                guard let self else {
                    return CallbackReply(status: 404, contentType: nil, body: "")
                }
                return await self.handleCallback(server: server, responder: responder, target: target)
            }
        } catch {
            throw AuthFailure((error as? AuthFailure)?.message ?? error.localizedDescription)
        }

        current = Running(
            server: server, url: "", listener: listener, transport: transport,
            timeoutTask: nil, completion: nil
        )

        // `void transport.connect().catch(() => undefined)` — expected to reject; the URL is the
        // real output and arrives by the redirect handler.
        Task { try? await transport.connect() }

        // The 20 s URL race. Distinct from the overall flow timeout, and this one DOES clean up.
        let url: String
        do {
            url = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask { try await authorizationURL() }
                let budget = urlTimeoutMilliseconds
                group.addTask {
                    try await Task.sleep(nanoseconds: UInt64(budget * 1_000_000))
                    throw AuthFailure(AuthPages.noURLRejection)
                }
                guard let first = try await group.next() else {
                    throw AuthFailure(AuthPages.noURLRejection)
                }
                group.cancelAll()
                return first
            }
        } catch {
            await cleanup(server: server)
            throw AuthFailure((error as? AuthFailure)?.message ?? error.localizedDescription)
        }

        guard var running = current, running.server == server else {
            // Superseded while we were waiting for the URL.
            throw AuthFailure("the authorization was superseded")
        }
        running.url = url
        // Arm the overall timeout only once the flow is real, as the reference does.
        let flowBudget = flowTimeoutMilliseconds
        running.timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(flowBudget * 1_000_000))
            guard !Task.isCancelled else { return }
            // The fifth termination renders NO page: the browser is still on the provider.
            await self?.settle(server: server, with: .failure(AuthFailure(AuthPages.timedOutRejection)))
        }
        current = running
        return LiveFlow(server: server, url: url)
    }

    private func exchange(server: JSString, code: String) async throws {
        guard let running = current, running.server == server else {
            throw AuthFailure("no authorization is in flight for \"\(server.string)\"")
        }
        try await running.transport.finishAuth(code: code)
    }

    /// One callback request: reply with the bytes, then apply the outcome.
    ///
    /// `ignored` settles nothing and cleans up nothing (B82) — the listener stays bound and the
    /// timer stays armed, so a stray request cannot end the user's authorization.
    private func handleCallback(
        server: JSString, responder: CallbackResponder, target: String
    ) async -> CallbackReply {
        let (reply, outcome) = await responder.respond(to: target)
        switch outcome {
        case .ignored:
            break
        case .succeeded:
            await settle(server: server, with: .success(()))
        case let .failed(reason):
            await settle(server: server, with: .failure(AuthFailure(reason)))
        }
        return reply
    }

    /// Await the live flow's completion.
    ///
    /// A superseded flow never resumes this, by design (B85). The continuation is retained by the
    /// actor rather than dropped, so a never-settled flow suspends its observer instead of tripping
    /// Swift's continuation-misuse check — the reference leaks the equivalent promise in the same
    /// shape.
    public func awaitCompletion(server: JSString) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard var running = current, running.server == server else {
                continuation.resume(throwing: AuthFailure("no authorization is in flight"))
                return
            }
            running.completion = continuation
            current = running
        }
    }
}
