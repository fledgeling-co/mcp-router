import Foundation
import Testing
@testable import MCPRouterKit

/// The merge that stands in for a running-state feed the router does not publish.
///
/// Worth restating, because it is the thing most likely to be "fixed" later by someone who assumes
/// a subscription exists: the router answers `GET /servers` with a snapshot and streams call
/// records on `/usage/stream`. Those two are the whole of what it observes. Anything a surface
/// shows beyond them would be invented, and inventing state is exactly what `DESIGN.md` §6 forbids.
@Suite("Live server state")
struct ServerStateTrackerTests {
    private func server(_ name: String, state: ServerState = .idle) throws -> MCPServer {
        var decoded = try FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)
        decoded.name = name
        decoded.state = state
        return decoded
    }

    private func response(_ servers: [MCPServer]) -> ServersResponse {
        ServersResponse(port: 8879, idleMs: 300_000, since: "2026-08-14T00:00:00.000Z", servers: servers)
    }

    private func record(for server: String) -> CallRecord {
        CallRecord(
            ts: "2026-08-14T00:00:01.000Z", server: server, tool: "t",
            ok: true, ms: 4, cold: false
        )
    }

    @Test("a call record marks an idle server running, until a poll says otherwise")
    func aCallCorrectsTheSnapshot() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        let idle = try server("alpha", state: .idle)

        await tracker.apply(poll: response([idle]))
        var state = await tracker.state()
        #expect(state.servers.first?.state == .idle)

        // A call is proof the server was running at that moment — the one correction the stream
        // can make between polls.
        await tracker.apply(record: record(for: "alpha"))
        state = await tracker.state()
        #expect(state.servers.first?.state == .running, "an arriving call did not correct the snapshot")

        // And the poll is authoritative again: it is the only thing that can move a server back.
        try await tracker.apply(poll: response([server("alpha", state: .idle)]))
        state = await tracker.state()
        #expect(state.servers.first?.state == .idle, "the poll must be able to contradict the stream")
    }

    /// The rule that keeps the merge honest. A record naming something the router never declared
    /// would otherwise conjure a row for a server that does not exist.
    @Test("a call record for a server the router never listed invents nothing")
    func unknownServersAreNotInvented() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        try await tracker.apply(poll: response([server("alpha")]))

        await tracker.apply(record: record(for: "ghost"))

        let state = await tracker.state()
        #expect(state.servers.count == 1, "a row was invented for a server no source reported")
        #expect(state.servers.first?.name == "alpha")
    }

    @Test("a poll removing a server removes it, rather than leaving a stale row behind")
    func pollIsAuthoritativeAboutMembership() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        try await tracker.apply(poll: response([server("alpha"), server("beta")]))
        #expect(await tracker.state().servers.count == 2)

        try await tracker.apply(poll: response([server("alpha")]))
        let state = await tracker.state()
        #expect(state.servers.map(\.name) == ["alpha"])
    }

    @Test("the router's own ordering is preserved rather than re-sorted")
    func orderComesFromTheRouter() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        try await tracker.apply(poll: response([server("zebra"), server("alpha"), server("mid")]))
        #expect(await tracker.state().servers.map(\.name) == ["zebra", "alpha", "mid"])
    }

    @Test("the stream's condition is carried alongside the servers, not folded into them")
    func phaseIsTracked() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        #expect(await tracker.state().phase == .disconnected)

        await tracker.apply(phase: .live)
        #expect(await tracker.state().phase == .live)

        // Losing the stream must not clear the rows already received: deleting history to report a
        // connection problem destroys data the user was reading.
        try await tracker.apply(poll: response([server("alpha")]))
        await tracker.apply(phase: .reconnecting)
        let state = await tracker.state()
        #expect(state.phase == .reconnecting)
        #expect(state.servers.count == 1, "a dropped stream cleared rows it never owned")
    }

    @Test("subscribers see the merged state as it changes")
    func updatesArePublished() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        let updates = await tracker.updates()

        var seen: [Int] = []
        let collector = Task {
            for await state in updates {
                seen.append(state.servers.count)
                if seen.count == 3 { break }
            }
            return seen
        }

        // Give the subscription a moment to register before publishing into it.
        try await Task.sleep(for: .milliseconds(50))
        try await tracker.apply(poll: response([server("alpha")]))
        try await tracker.apply(poll: response([server("alpha"), server("beta")]))

        let counts = await collector.value
        #expect(counts.count == 3, "expected the initial state and two updates, saw \(counts)")
        #expect(counts.last == 2)
    }
}
