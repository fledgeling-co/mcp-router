#if os(macOS)
    import Foundation
    @testable import MCPRouterKit

    /// K3 · a client that keeps the requests it was handed, so a write can be read on the wire.
    ///
    /// **Why the wire and not the board.** The census counts a control as actuated only when the
    /// effect is read somewhere other than the control that was struck, and the boards this file
    /// serves all redraw from a model they already hold. An Inbox accept clears `acceptState`,
    /// closes the sheet and drops the row *before* the router is spoken to and *whether or not*
    /// anything reaches it — so every one of those observables is the app's own report that it did
    /// something, which is the acknowledgement-only shape `references/inert-ui.md` §3 names. The
    /// request this recorded is the only reading that separates a working control from an empty
    /// closure.
    ///
    /// It forwards to a real fixture rather than answering canned values, so the surface under test
    /// is talking to the same client it would talk to anyway and the recording is a side effect —
    /// `RecordingControlAPIClient`'s argument for a decorator, applied to the payloads rather than
    /// to a count. Counting alone cannot say *what* was declared, and "a declaration went out"
    /// passes on a handler that sends a fixed one for every row.
    ///
    /// `harnesses()` is staged rather than forwarded because the Harnesses board's one control is a
    /// re-read: a fixture that answers identically twice cannot tell a second request from a
    /// redraw of the first answer. Staging a *different* second answer makes the row set the
    /// observable rather than the round trip.
    ///
    /// `@unchecked Sendable` with the mutable state behind an `NSLock` and a scoped `withLock`,
    /// which is the only shape in which that annotation is honest (`SWIFT_PRACTICES.md` §1) —
    /// `lock()`/`unlock()` are unavailable from an async context, so the recording happens in a
    /// non-async helper the async method calls.
    final class ActuationRecordingClient: ControlAPIClient, @unchecked Sendable {
        /// One declaration as it went out, with the flag that decides whether it may replace an
        /// existing server. Held together because "was anything forced" is unanswerable from a
        /// list of names.
        struct Declaration: Sendable {
            let server: NewServer
            let force: Bool
        }

        private let inner: FixtureControlAPIClient
        private let lock = NSLock()
        private var sent: [Declaration] = []
        private var removed: [String] = []
        private var harnessReads = 0
        private var stagedHarnesses: [HarnessesResponse]

        init(
            _ scenario: FixtureControlAPIClient.Scenario = .populated,
            harnesses staged: [HarnessesResponse] = []
        ) {
            inner = FixtureControlAPIClient(scenario)
            stagedHarnesses = staged
        }

        /// Every declaration the router was handed, in order.
        var declarations: [Declaration] { lock.withLock { sent } }

        /// The names it was asked to remove. Read by the decline case, whose whole claim is that
        /// this stays empty.
        var removals: [String] { lock.withLock { removed } }

        /// How many `/harnesses` reads it has served. The board's own state cannot distinguish a
        /// second read from a redraw, and this can.
        var harnessRequests: Int { lock.withLock { harnessReads } }

        private func record(_ declaration: Declaration) {
            lock.withLock { sent.append(declaration) }
        }

        private func record(removal name: String) {
            lock.withLock { removed.append(name) }
        }

        /// The staged answer for this read, or `nil` to forward. The last staged answer repeats, so
        /// a third read is not a different claim from the second.
        private func nextHarnesses() -> HarnessesResponse? {
            lock.withLock {
                harnessReads += 1
                guard !stagedHarnesses.isEmpty else { return nil }
                return stagedHarnesses[min(harnessReads - 1, stagedHarnesses.count - 1)]
            }
        }

        // MARK: - The operations this file reads

        func add(_ server: NewServer, force: Bool) async throws(ControlAPIError) -> AddedServer {
            record(Declaration(server: server, force: force))
            return try await inner.add(server, force: force)
        }

        func remove(_ name: String, keepHistory: Bool) async throws(ControlAPIError) -> RemovedServer {
            record(removal: name)
            return try await inner.remove(name, keepHistory: keepHistory)
        }

        func harnesses() async throws(ControlAPIError) -> HarnessesResponse {
            if let staged = nextHarnesses() { return staged }
            return try await inner.harnesses()
        }

        // MARK: - Straight passthrough

        func servers() async throws(ControlAPIError) -> ServersResponse {
            try await inner.servers()
        }

        func server(named name: String) async throws(ControlAPIError) -> MCPServer {
            try await inner.server(named: name)
        }

        func usage(
            limit: Int?,
            server: String?,
            cwd: String?
        ) async throws(ControlAPIError) -> UsageResponse {
            try await inner.usage(limit: limit, server: server, cwd: cwd)
        }

        func usageSummary() async throws(ControlAPIError) -> UsageSummary {
            try await inner.usageSummary()
        }

        func heldChanges(for name: String) async throws(ControlAPIError) -> HeldChanges {
            try await inner.heldChanges(for: name)
        }

        func searchRegistry(
            query: String,
            limit: Int
        ) async throws(ControlAPIError) -> RegistrySearchResponse {
            try await inner.searchRegistry(query: query, limit: limit)
        }

        func skills() async throws(ControlAPIError) -> SkillsResponse {
            try await inner.skills()
        }

        func marketplaces() async throws(ControlAPIError) -> MarketplacesResponse {
            try await inner.marketplaces()
        }

        func insights(period: InsightsPeriod) async throws(ControlAPIError) -> InsightsResponse {
            try await inner.insights(period: period)
        }

        func reindex(_ name: String) async throws(ControlAPIError) -> ReindexResult {
            try await inner.reindex(name)
        }

        func patch(server name: String, _ patch: ServerPatch) async throws(ControlAPIError) -> MCPServer {
            try await inner.patch(server: name, patch)
        }

        func approvePendingChange(server name: String, expectedDigest: String) async throws(ControlAPIError) -> ApprovalResult {
            try await inner.approvePendingChange(server: name, expectedDigest: expectedDigest)
        }

        func beginAuthorization(for name: String) async throws(ControlAPIError) -> AuthorizationStart {
            try await inner.beginAuthorization(for: name)
        }

        func signOut(_ name: String) async throws(ControlAPIError) -> SignedOut {
            try await inner.signOut(name)
        }

        func resetUsage() async throws(ControlAPIError) -> UsageReset {
            try await inner.resetUsage()
        }
    }
#endif
