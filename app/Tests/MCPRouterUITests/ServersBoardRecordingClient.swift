#if os(macOS)
    import Foundation
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// A client that records rather than connects, and answers plausibly.
    ///
    /// It encodes each patch through `ServerPatch.encodedBody()` — the one sanctioned path, and
    /// the same one `LiveControlAPIClient` uses — so a forbidden or unpermitted key throws here
    /// exactly as it would in the app rather than being quietly serialised by a test's own
    /// encoder.
    final class ServersBoardRecordingClient: ControlAPIClient, @unchecked Sendable {
        /// One recorded call: which operation, against which server, and the encoded body where the
        /// operation has one. The body is the field that matters — a request asserted by name proves
        /// only that something was sent.
        struct Recorded: Equatable {
            let operation: String
            let server: String
            let body: String?
        }

        /// `@unchecked Sendable` is honest and narrow here: every access happens on the test's
        /// own task, and the lock below guards the one mutable field regardless.
        private let lock = NSLock()
        private var recorded: [Recorded] = []

        var patchResponse: MCPServer?
        var addFailure: ControlAPIError?
        var reindexError: String?
        /// A refusal for `patch` to throw, **carrying its own payload**.
        ///
        /// `patchResponse = nil` throws `.routerNotRunning`, which has no associated values — so a
        /// test asserting that the board passes the router's own words through has nothing the
        /// board could have dropped, and cannot fail. A `.server(status:message:hint:)` set here
        /// does.
        var patchFailure: ControlAPIError?
        /// Run inside `patch`, before it answers, so a caller can observe the board **mid-write**.
        ///
        /// The in-flight mark is inserted before the operation and removed in a `defer` after it,
        /// so every assertion made once `patch` has returned sees the cleared state — which is
        /// equally true of a mechanism that never sets the mark at all. This is the only seam from
        /// which the set state is observable.
        var duringPatch: (@Sendable () async -> Void)?

        var calls: [Recorded] {
            lock.lock(); defer { lock.unlock() }
            return recorded
        }

        private func record(_ entry: Recorded) {
            lock.lock(); defer { lock.unlock() }
            recorded.append(entry)
        }

        private func base() throws -> MCPServer {
            try FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)
        }

        func servers() async throws(ControlAPIError) -> ServersResponse {
            ServersResponse(port: 1, idleMs: 300_000, since: "", pendingAuth: nil, servers: [])
        }

        func server(named name: String) async throws(ControlAPIError) -> MCPServer {
            guard let patchResponse else { throw ControlAPIError.routerNotRunning }
            _ = name
            return patchResponse
        }

        func usage(
            limit _: Int?,
            server _: String?,
            cwd _: String?
        ) async throws(ControlAPIError) -> UsageResponse {
            UsageResponse(since: "", records: [])
        }

        func usageSummary() async throws(ControlAPIError) -> UsageSummary {
            UsageSummary(since: "", servers: [])
        }

        /// This double stands in for the SERVERS surface and serves no skills. It says so rather
        /// than answering with an empty list: a double that returns `[]` teaches a test that "no
        /// skills" is a normal answer, which is the silent-empty failure this protocol is written
        /// against.
        func skills() async throws(ControlAPIError) -> SkillsResponse {
            throw .malformedResponse(detail: "this double serves no skills")
        }

        func marketplaces() async throws(ControlAPIError) -> MarketplacesResponse {
            throw .malformedResponse(detail: "this double serves no marketplaces")
        }

        func heldChanges(for name: String) async throws(ControlAPIError) -> HeldChanges {
            record(Recorded(operation: "heldChanges", server: name, body: nil))
            return HeldChanges(server: name, pending: true, seenAt: nil, changes: [])
        }

        func searchRegistry(
            query _: String,
            limit _: Int
        ) async throws(ControlAPIError) -> RegistrySearchResponse {
            throw ControlAPIError.routerNotRunning
        }

        func add(_ server: NewServer, force: Bool) async throws(ControlAPIError) -> AddedServer {
            record(
                Recorded(
                    operation: force ? "add(force)" : "add",
                    server: server.name,
                    // The one request that legitimately carries a command line. Recorded as the
                    // encoded body so the test can say so explicitly rather than by omission.
                    body: (try? JSONEncoder().encode(server))
                        .flatMap { String(data: $0, encoding: .utf8) }
                )
            )
            if let addFailure { throw addFailure }
            return AddedServer(added: server.name, tools: 0, error: nil, needsAuth: nil)
        }

        func remove(_ name: String, keepHistory: Bool) async throws(ControlAPIError) -> RemovedServer {
            record(
                Recorded(
                    operation: keepHistory ? "remove(keepHistory)" : "remove",
                    server: name, body: nil
                )
            )
            return RemovedServer(removed: name)
        }

        func reindex(_ name: String) async throws(ControlAPIError) -> ReindexResult {
            record(Recorded(operation: "reindex", server: name, body: nil))
            return ReindexResult(name: name, tools: 0, error: reindexError)
        }

        func patch(server name: String, _ patch: ServerPatch) async throws(ControlAPIError) -> MCPServer {
            // `encodedBody()` rather than a local encoder: it fixes the encoder configuration and
            // checks the key set of the bytes it returns, which is the check A13 depends on.
            let encoded: String
            do {
                encoded = try String(data: patch.encodedBody(), encoding: .utf8) ?? ""
            } catch {
                throw ControlAPIError.malformedResponse(detail: "\(error)")
            }
            record(Recorded(operation: "patch", server: name, body: encoded))
            if let duringPatch { await duringPatch() }
            if let patchFailure { throw patchFailure }
            guard let patchResponse else { throw ControlAPIError.routerNotRunning }
            return patchResponse
        }

        func approvePendingChange(server name: String) async throws(ControlAPIError) -> ApprovalResult {
            record(Recorded(operation: "approve", server: name, body: nil))
            return ApprovalResult(server: name, approved: 1)
        }

        func beginAuthorization(for name: String) async throws(ControlAPIError) -> AuthorizationStart {
            record(Recorded(operation: "auth", server: name, body: nil))
            return AuthorizationStart(server: name, authorizationURL: "https://auth.example/go")
        }

        func signOut(_ name: String) async throws(ControlAPIError) -> SignedOut {
            record(Recorded(operation: "signOut", server: name, body: nil))
            return SignedOut(server: name, signedOut: true)
        }

        func resetUsage() async throws(ControlAPIError) -> UsageReset {
            UsageReset(ok: true, since: "")
        }
    }

#endif
