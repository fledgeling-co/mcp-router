import Foundation

/// A client backed by responses recorded from a real router.
///
/// Its reason to exist is that every UI surface in this product has nine states to get right, and
/// eight of them are difficult to produce on demand against a live router — you cannot easily make
/// a real daemon return a partial index, or drop a stream, or hand back a name too long for its
/// column. A surface tested only against a healthy router is a surface tested in its easiest state.
///
/// Scenarios are **named** rather than assembled by the caller. `FixtureControlAPIClient(.offline)`
/// is a condition a test asks for; a pile of constructor arguments is a condition a test has to
/// build correctly, and one built slightly wrong silently tests something else.
public struct FixtureControlAPIClient: ControlAPIClient {
    /// The conditions a surface has to render: `DESIGN.md` §5's nine states, plus `unauthorized`
    /// — not one of the nine, but the other refusal that replaces a whole screen and so needs its
    /// own recording — and the live stream's three phases.
    public enum Scenario: String, Sendable, CaseIterable {
        /// The ideal, populated case.
        case populated
        /// The router answered and has nothing declared.
        case empty
        /// A request that never returns, for testing the placeholder.
        case loading
        /// Some servers reported their tools; some failed, with a reason.
        case partial
        /// The router refused the operation.
        case error
        /// A write that succeeded.
        case success
        /// The router is not running.
        case offline
        /// Reached, but the token is wrong or rotated away.
        case unauthorized
        /// A server whose name is wider than its column.
        case overflow
        /// A server the router has declared inoperative, with the reason it gives.
        ///
        /// The Disabled state as *data*. A placard is the router's own "this one is off, and here
        /// is why, and here is what to use instead" — which is what a surface dims in place and
        /// explains. A scenario that only named itself disabled would let a surface invent its own
        /// reason, and an invented reason is the thing `DESIGN.md` §6 exists to prevent.
        case disabled
        /// The stream is delivering.
        case streamLive
        /// The stream dropped and is retrying.
        case streamReconnecting
        /// The stream gave up.
        case streamDisconnected
    }

    public let scenario: Scenario

    public init(_ scenario: Scenario = .populated) {
        self.scenario = scenario
    }

    // MARK: - Loading the recordings

    /// Fixtures are read from the library's own bundle, so a consumer needs no test resources.
    public static func fixtureData(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle.module.url(forResource: name, withExtension: "json")
        else {
            throw ControlAPIError.malformedResponse(detail: "missing fixture \(name).json")
        }
        return try Data(contentsOf: url)
    }

    public static func decodeFixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: fixtureData(name))
    }

    private func decode<T: Decodable>(_ name: String, as type: T.Type) throws(ControlAPIError) -> T {
        do {
            return try Self.decodeFixture(name, as: type)
        } catch let error as ControlAPIError {
            throw error
        } catch {
            throw ControlAPIError.malformedResponse(detail: "fixture \(name): \(error)")
        }
    }

    /// The failure this scenario answers every call with, if it is a failing one.
    private var failure: ControlAPIError? {
        switch scenario {
        case .offline: .routerNotRunning
        case .unauthorized: .unauthorized
        case .error:
            .server(
                status: 422,
                message: "spawn /nonexistent/binary-that-cannot-start ENOENT",
                hint: "retry with ?force=1 to add it anyway"
            )
        default: nil
        }
    }

    private func guardFailure() throws(ControlAPIError) {
        if let failure { throw failure }
    }

    // MARK: - Reading

    public func servers() async throws(ControlAPIError) -> ServersResponse {
        try guardFailure()
        if scenario == .loading {
            // Never returns. A loading state is the absence of an answer, so the honest way to
            // hold a surface in it is to not answer.
            try await Self.forever()
        }
        // The populated case uses the recording that carries an in-flight authorization, because a
        // surface that only ever sees the quiet shape is a surface that has never rendered the
        // busiest one it will meet.
        var response = try decode("servers-pending-auth", as: ServersResponse.self)
        switch scenario {
        case .empty:
            response.servers = []
            response.pendingAuth = nil
        case .partial:
            response.servers = response.servers.enumerated().map { index, server in
                var copy = server
                if index.isMultiple(of: 2) {
                    copy.indexError = "spawn ENOENT — the command is not on PATH"
                }
                return copy
            }
        case .overflow:
            response.servers = response.servers.map { server in
                var copy = server
                copy.name = "plugin_pixel-plugin_aseprite_headless_render_worker_arm64"
                return copy
            }
        case .disabled:
            // The placarded server is a real recording, so the reason a surface renders is one the
            // router actually served rather than one this double made up.
            let placarded = try decode("server-placarded", as: MCPServer.self)
            response.servers = response.servers.map { $0.name == placarded.name ? placarded : $0 }
        default:
            break
        }
        return response
    }

    public func server(named name: String) async throws(ControlAPIError) -> MCPServer {
        try guardFailure()
        var server = try decode("server-stdio", as: MCPServer.self)
        server.name = name
        return server
    }

    public func usage() async throws(ControlAPIError) -> UsageResponse {
        try guardFailure()
        if scenario == .loading { try await Self.forever() }
        return try decode("usage", as: UsageResponse.self)
    }

    public func usageSummary() async throws(ControlAPIError) -> UsageSummary {
        try guardFailure()
        return try decode("usage-summary", as: UsageSummary.self)
    }

    public func heldChanges(for name: String) async throws(ControlAPIError) -> HeldChanges {
        try guardFailure()
        // `.populated` is the *interesting* case: a change actually held, carrying an added tool, a
        // removed one, and a description rewritten to hide a zero-width space. A double that only
        // ever reports "nothing pending" cannot exercise the surface it exists for.
        let fixture = scenario == .empty ? "changes-none" : "changes-pending"
        var changes = try decode(fixture, as: HeldChanges.self)
        changes.server = name
        return changes
    }

    public func searchRegistry(
        query _: String,
        limit _: Int
    ) async throws(ControlAPIError) -> RegistrySearchResponse {
        try guardFailure()
        if scenario == .loading { try await Self.forever() }
        return try decode("registry-search", as: RegistrySearchResponse.self)
    }

    // MARK: - Writing

    public func add(_ server: NewServer, force _: Bool) async throws(ControlAPIError) -> AddedServer {
        try guardFailure()
        var added = try decode("added", as: AddedServer.self)
        added.added = server.name
        return added
    }

    public func remove(_ name: String, keepHistory _: Bool) async throws(ControlAPIError) -> RemovedServer {
        try guardFailure()
        var removed = try decode("removed", as: RemovedServer.self)
        removed.removed = name
        return removed
    }

    public func reindex(_ name: String) async throws(ControlAPIError) -> ReindexResult {
        try guardFailure()
        var result = try decode("reindex-failure", as: ReindexResult.self)
        result.name = name
        if scenario == .success { result.error = nil; result.tools = 14 }
        return result
    }

    public func patch(server name: String, _ patch: ServerPatch) async throws(ControlAPIError) -> MCPServer {
        try guardFailure()
        var server = try decode("patch-response", as: MCPServer.self)
        server.name = name
        if let warm = patch.warm { server.warm = warm }
        if let projects = patch.projects { server.projects = projects }
        return server
    }

    public func approvePendingChange(server name: String) async throws(ControlAPIError) -> ApprovalResult {
        try guardFailure()
        var approval = try decode("approve", as: ApprovalResult.self)
        approval.server = name
        return approval
    }

    public func beginAuthorization(for name: String) async throws(ControlAPIError) -> AuthorizationStart {
        try guardFailure()
        var start = try decode("auth-start", as: AuthorizationStart.self)
        start.server = name
        return start
    }

    public func signOut(_ name: String) async throws(ControlAPIError) -> SignedOut {
        try guardFailure()
        var out = try decode("signout", as: SignedOut.self)
        out.server = name
        return out
    }

    public func resetUsage() async throws(ControlAPIError) -> UsageReset {
        try guardFailure()
        return try decode("usage-reset", as: UsageReset.self)
    }

    // MARK: - The stream

    /// The events this scenario's stream produces, ending in its phase.
    public func streamEvents() throws(ControlAPIError) -> [StreamEvent] {
        let records: [CallRecord]
        do {
            records = try Self.decodeFixture("usage", as: UsageResponse.self).records
        } catch let error as ControlAPIError {
            throw error
        } catch {
            throw ControlAPIError.malformedResponse(detail: "fixture usage: \(error)")
        }

        switch scenario {
        case .streamLive:
            return [.phase(.live)] + records.prefix(4).map { .record($0) }
        case .streamReconnecting:
            return [.phase(.live)] + records.prefix(2).map { .record($0) } + [.phase(.reconnecting)]
        case .streamDisconnected:
            return [.phase(.live)] + records.prefix(2).map { .record($0) }
                + [.phase(.reconnecting), .phase(.disconnected)]
        default:
            return [.phase(.live)]
        }
    }

    /// Suspends until cancelled, and then refuses.
    ///
    /// The refusal matters. Falling out of the wait and returning the populated response would mean
    /// a cancelled load quietly delivers data — so a surface that navigated away, or a test that
    /// gave up waiting, would still receive an answer it no longer has anywhere to put.
    private static func forever() async throws(ControlAPIError) -> Never {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
        throw ControlAPIError.transport(detail: "the request was cancelled while loading")
    }
}
