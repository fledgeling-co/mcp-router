#if os(macOS)
    import Foundation
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    // Two `ControlAPIClient` doubles, in their own file because they are support rather than
    // assertions — and because the board's two failure stories need a client that fails **only**
    // `/usage`. `FixtureControlAPIClient`'s failing scenarios refuse every operation at once, which
    // cannot express "the history is unreadable and the feed is fine".

    /// Records what the board asked `/usage` for.
    actor RecordingUsageClient: ControlAPIClient {
        struct Call: Sendable { let limit: Int?; let server: String?; let cwd: String? }
        private(set) var calls: [Call] = []
        private let inner = FixtureControlAPIClient(.populated)

        func usage(
            limit: Int?,
            server: String?,
            cwd: String?
        ) async throws(ControlAPIError) -> UsageResponse {
            calls.append(Call(limit: limit, server: server, cwd: cwd))
            return try await inner.usage(limit: limit, server: server, cwd: cwd)
        }

        func servers() async throws(ControlAPIError) -> ServersResponse {
            try await inner.servers()
        }

        func server(named name: String) async throws(ControlAPIError) -> MCPServer {
            try await inner.server(named: name)
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

        func add(_ server: NewServer, force: Bool) async throws(ControlAPIError) -> AddedServer {
            try await inner.add(server, force: force)
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

    /// Fails `/usage` and nothing else, so the history's failure can be tested independently of the
    /// feed's — which is the whole reason the board has two failure stories.
    struct FailingUsageClient: ControlAPIClient {
        private let inner = FixtureControlAPIClient(.populated)

        func usage(
            limit _: Int?,
            server _: String?,
            cwd _: String?
        ) async throws(ControlAPIError) -> UsageResponse {
            throw .server(status: 500, message: "usage log unreadable", hint: nil)
        }

        func servers() async throws(ControlAPIError) -> ServersResponse {
            try await inner.servers()
        }

        func server(named name: String) async throws(ControlAPIError) -> MCPServer {
            try await inner.server(named: name)
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

        func add(_ server: NewServer, force: Bool) async throws(ControlAPIError) -> AddedServer {
            try await inner.add(server, force: force)
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
