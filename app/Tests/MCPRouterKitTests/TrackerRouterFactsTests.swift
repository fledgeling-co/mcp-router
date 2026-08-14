import Foundation
import Testing
@testable import MCPRouterKit

/// The router-level facts the tracker retains, and the rule that they survive a failed refresh.
///
/// `idleMs` and `pendingAuth` were retained by F4 for a stated reason: a surface rendering a reap
/// countdown has to get the horizon from the router rather than assume one. M8 adds `port` and
/// `since` under the same argument — Settings composes its endpoint row from the observed port, and
/// a hardcoded 8879 points the user at a port nothing is listening on the moment they move it.
///
/// The retention half is the part worth a test of its own. A failure to refresh is **not** evidence
/// that the router changed its configuration, so clearing these on a failed poll would make
/// Settings blank its router card every time a poll blipped.
@Suite("Tracker — router facts")
struct TrackerRouterFactsTests {
    static func server(_ name: String) throws -> MCPServer {
        var decoded = try FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)
        decoded.name = name
        return decoded
    }

    static func response(port: Int, since: String) throws -> ServersResponse {
        ServersResponse(
            port: port,
            idleMs: 300_000,
            since: since,
            servers: [try server("alpha")]
        )
    }

    @Test("a successful poll carries the router's port and counting window onto the state")
    func factsArriveFromThePoll() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        await tracker.apply(poll: try Self.response(port: 9999, since: "2026-08-12T09:14:00.000Z"))

        let state = await tracker.state()
        #expect(state.port == 9999, "the observed port did not reach the state")
        #expect(state.since == "2026-08-12T09:14:00.000Z")
        #expect(state.idleMs == 300_000)
    }

    @Test("a fresh tracker reports no port and no window rather than a plausible default")
    func factsAreAbsentBeforeAnyPoll() async {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        let state = await tracker.state()
        #expect(state.port == nil, "an unpolled tracker invented a port")
        #expect(state.since == nil)
    }

    /// The clause this suite exists for. Break the retention — clear `port`/`since` in
    /// `apply(pollFailure:)` — and this goes red; that red-green was performed and recorded in
    /// `planning/evidence/M8-acceptance.md`.
    @Test("a failed poll after a successful one keeps the port and the counting window")
    func factsSurviveAFailedRefresh() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        await tracker.apply(poll: try Self.response(port: 9999, since: "2026-08-12T09:14:00.000Z"))
        await tracker.apply(pollFailure: .routerNotRunning)

        let state = await tracker.state()
        #expect(state.port == 9999, "a failed refresh discarded the router's port")
        #expect(state.since == "2026-08-12T09:14:00.000Z", "a failed refresh discarded the counting window")
        // And the retention is not a side effect of the load state staying loaded — it went stale.
        #expect(state.load != .loaded([try Self.server("alpha")]))
    }

    @Test("a later successful poll replaces the facts rather than merging them")
    func factsAreReplacedByAFreshPoll() async throws {
        let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
        await tracker.apply(poll: try Self.response(port: 8879, since: "2026-08-12T09:14:00.000Z"))
        await tracker.apply(poll: try Self.response(port: 9999, since: "2026-08-13T10:00:00.000Z"))

        let state = await tracker.state()
        #expect(state.port == 9999)
        #expect(state.since == "2026-08-13T10:00:00.000Z")
    }
}
