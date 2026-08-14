#if os(macOS)
    import Foundation
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    // Two `ControlAPIClient` doubles, in their own file because they are support rather than
    // assertions — and because the board's two failure stories need a client that fails **only**
    // `/usage`. `FixtureControlAPIClient`'s failing scenarios refuse every operation at once, which
    // cannot express "the history is unreadable and the feed is fine".

    /// Serves a fixed call log, so a test can control the backfill's size exactly — which is what
    /// the capacity-boundary merge needs and no recording can provide.
    ///
    /// `init(windows:)` serves a **different** window per call, which is the only way to express the
    /// thing a reconnect actually meets: a router whose ring has rolled forward since the last
    /// fetch. A double that answers the same records twice can never produce a response whose window
    /// has moved, and that is exactly the case the merge gets wrong.
    struct StaticUsageClient: ControlAPIClient {
        let records: [CallRecord]
        private let cursor: Cursor
        private let inner = FixtureControlAPIClient(.populated)

        /// Reference-typed because the protocol's methods are not mutating and the point is that the
        /// second call sees a different answer from the first.
        final class Cursor: @unchecked Sendable {
            private let lock = NSLock()
            private var index = 0
            private let windows: [[CallRecord]]

            init(windows: [[CallRecord]]) {
                self.windows = windows
            }

            /// The next window, then the last one for every call after it.
            func next(fallback: [CallRecord]) -> [CallRecord] {
                guard !windows.isEmpty else { return fallback }
                lock.lock()
                defer { lock.unlock() }
                let window = windows[min(index, windows.count - 1)]
                index += 1
                return window
            }
        }

        init(records: [CallRecord]) {
            self.records = records
            cursor = Cursor(windows: [])
        }

        init(windows: [[CallRecord]]) {
            records = windows.first ?? []
            cursor = Cursor(windows: windows)
        }

        func usage(
            limit: Int?,
            server _: String?,
            cwd _: String?
        ) async throws(ControlAPIError) -> UsageResponse {
            let window = cursor.next(fallback: records)
            return UsageResponse(
                since: "2026-08-14T09:12:04.118Z",
                records: limit.map { Array(window.prefix($0)) } ?? window
            )
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

        /// M4 added these to `ControlAPIClient` after these doubles were written. An Activity
        /// double serves no skills, and saying so is more useful than an empty response that
        /// would let a skills-shaped assertion pass here by accident.
        func skills() async throws(ControlAPIError) -> SkillsResponse {
            throw .malformedResponse(detail: "this double serves no skills")
        }

        func marketplaces() async throws(ControlAPIError) -> MarketplacesResponse {
            throw .malformedResponse(detail: "this double serves no marketplaces")
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

        /// M4 added these to `ControlAPIClient` after these doubles were written. An Activity
        /// double serves no skills, and saying so is more useful than an empty response that
        /// would let a skills-shaped assertion pass here by accident.
        func skills() async throws(ControlAPIError) -> SkillsResponse {
            throw .malformedResponse(detail: "this double serves no skills")
        }

        func marketplaces() async throws(ControlAPIError) -> MarketplacesResponse {
            throw .malformedResponse(detail: "this double serves no marketplaces")
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

        /// M4 added these to `ControlAPIClient` after these doubles were written. An Activity
        /// double serves no skills, and saying so is more useful than an empty response that
        /// would let a skills-shaped assertion pass here by accident.
        func skills() async throws(ControlAPIError) -> SkillsResponse {
            throw .malformedResponse(detail: "this double serves no skills")
        }

        func marketplaces() async throws(ControlAPIError) -> MarketplacesResponse {
            throw .malformedResponse(detail: "this double serves no marketplaces")
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

    /// A feed that opens, reports, and then **stays open** — which is what the real one does.
    ///
    /// `ReplayActivityEventSource` finishes its continuation after the last recorded event, so a
    /// consumer of it always returns. `ControlEventStream` does not: it loops until its retry ladder
    /// is exhausted and finishes only then, so over a healthy connection the consumer never returns
    /// at all. Every reconnect test in this repository was written against the replay, and the
    /// difference between the two is exactly the gap a dead reconnect button lived in.
    ///
    /// It ends only when the consuming task is cancelled, which is what `stopFeed()` does.
    struct LiveForeverEventSource: ActivityEventSource {
        private let opening: [StreamEvent]

        init(_ opening: [StreamEvent]) {
            self.opening = opening
        }

        func events() -> AsyncStream<StreamEvent> {
            AsyncStream { continuation in
                for event in opening {
                    continuation.yield(event)
                }
                // Deliberately no `finish()`.
            }
        }
    }
#endif
