#if os(macOS)
    import Foundation
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// A client that records what the board asked for, and answers with whatever the test staged.
    ///
    /// The recording is the point. "Detail-then-install" is a claim about which calls are *not*
    /// made, and a test that only checks what appears on screen cannot see a stray `add`.
    final class DiscoverRecordingClient: ControlAPIClient, @unchecked Sendable {
        private let inner = FixtureControlAPIClient(.populated)
        private let lock = NSLock()
        private var searches: [String] = []
        private var limits: [Int] = []
        private var adds: [NewServer] = []

        /// Answers handed out in order; the last one repeats. Empty means "the fixture's answer".
        var staged: [Result<RegistrySearchResponse, ControlAPIError>] = []
        var addFailure: ControlAPIError?
        /// Held so a slow first response can be made to land after a faster second one.
        var searchDelayNanoseconds: UInt64 = 0

        private var cursor = 0

        var searchQueries: [String] { lock.withLock { searches } }

        /// The `limit` each search asked for. `/registry/search` caps it at 60 and takes no other
        /// parameter, so what a surface asks for is the whole of its request.
        var searchLimits: [Int] { lock.withLock { limits } }

        var addedServers: [NewServer] { lock.withLock { adds } }

        /// Synchronous on purpose: `NSLock.lock()` is unavailable from an async context, so the
        /// recording happens in a non-async helper the async method calls.
        private func record(
            search query: String,
            limit: Int
        ) -> Result<RegistrySearchResponse, ControlAPIError>? {
            lock.withLock {
                searches.append(query)
                limits.append(limit)
                let answer = staged.isEmpty ? nil : staged[min(cursor, staged.count - 1)]
                cursor += 1
                return answer
            }
        }

        private func record(add server: NewServer) {
            lock.withLock { adds.append(server) }
        }

        func searchRegistry(
            query: String,
            limit: Int
        ) async throws(ControlAPIError) -> RegistrySearchResponse {
            let answer = record(search: query, limit: limit)

            if searchDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: searchDelayNanoseconds)
            }
            switch answer {
            case let .success(response): return response
            case let .failure(error): throw error
            case nil: return try await inner.searchRegistry(query: query, limit: limit)
            }
        }

        func add(_ server: NewServer, force: Bool) async throws(ControlAPIError) -> AddedServer {
            record(add: server)
            if let addFailure { throw addFailure }
            return try await inner.add(server, force: force)
        }

        /// Everything below is the fixture's, unchanged — this double is about the registry.
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

        func skills() async throws(ControlAPIError) -> SkillsResponse {
            try await inner.skills()
        }

        func marketplaces() async throws(ControlAPIError) -> MarketplacesResponse {
            try await inner.marketplaces()
        }

        func remove(_ name: String, keepHistory: Bool) async throws(ControlAPIError) -> RemovedServer {
            try await inner.remove(name, keepHistory: keepHistory)
        }

        func reindex(_ name: String) async throws(ControlAPIError) -> ReindexResult {
            try await inner.reindex(name)
        }

        func patch(server name: String, _ patch: ServerPatch) async throws(ControlAPIError) -> MCPServer {
            try await inner.patch(server: name, patch)
        }

        func approvePendingChange(server name: String) async throws(ControlAPIError) -> ApprovalResult {
            try await inner.approvePendingChange(server: name)
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
