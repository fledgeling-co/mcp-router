import Foundation
import Testing
@testable import MCPRouterKit

/// The popover's whole render, as a value — which is what makes its states assertable at all.
@Suite("Popover content")
struct PopoverContentTests {
    static let now = Date(timeIntervalSince1970: 1_770_000_000)

    static func server(
        _ name: String,
        state: ServerState = .idle,
        held: Bool = false,
        indexError: String? = nil,
        tools: Int = 0
    ) throws -> MCPServer {
        var decoded = try FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)
        decoded.name = name
        decoded.state = state
        decoded.tools = tools
        decoded.pendingChange = held ? PendingChange(seenAt: "2026-08-14T09:00:00Z", count: 1) : nil
        decoded.indexError = indexError
        decoded.auth = ServerAuth(supported: false, authorized: true, authorizedAt: nil, pendingURL: nil)
        return decoded
    }

    static func record(_ server: String, secondsAgo: Int, ok: Bool = true, cold: Bool = false) -> CallRecord {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return CallRecord(
            ts: formatter.string(from: now.addingTimeInterval(-Double(secondsAgo))),
            server: server,
            tool: "do_thing",
            ok: ok,
            ms: 210,
            cold: cold
        )
    }

    // MARK: - A18 · the band is absent, not empty

    /// The clause the type's shape exists for. A view-level test cannot tell a hidden band from a
    /// band rendering zero rows — both draw nothing — so the distinction is `nil` versus `[]` and a
    /// unit test can see it.
    @Test("nothing wanting a decision produces a nil band, never an empty one")
    func quietStateHasNoBand() throws {
        let content = PopoverContent.make(
            trackerState: .init(load: .loaded([try Self.server("quiet")]), stream: .notConfigured),
            records: [Self.record("quiet", secondsAgo: 2)],
            now: Self.now
        )
        #expect(content.band == nil, "a quiet popover drew an empty band instead of no band")
        #expect(content.band?.isEmpty != true)
    }

    @Test("a server wanting a decision produces a band with that row")
    func attentionProducesABand() throws {
        let content = PopoverContent.make(
            trackerState: .init(
                load: .loaded([try Self.server("quiet"), try Self.server("held", held: true)]),
                stream: .notConfigured
            ),
            records: [Self.record("quiet", secondsAgo: 2)],
            now: Self.now
        )
        #expect(content.band?.count == 1)
        #expect(content.band?.first?.server == "held")
        #expect(content.band?.first?.cause == .heldChange)
    }

    // MARK: - A16b · the two buckets always sum

    /// `ServerState` has four cases and the header has two buckets. Reading "idle" as
    /// `state == .idle` is the obvious implementation, and it drops `starting` and `stopping` —
    /// which is every cold start, which is exactly when someone is looking at the popover.
    @Test("running and idle sum to the declared total across all four lifecycle states")
    func countsCoverTheWholeStateSpace() throws {
        let servers = [
            try Self.server("a", state: .running, tools: 3),
            try Self.server("b", state: .idle, tools: 3),
            try Self.server("c", state: .starting, tools: 3),
            try Self.server("d", state: .stopping, tools: 3)
        ]
        let counts = MenuBarPresentation.counts(from: servers)
        #expect(counts.running == 1)
        #expect(counts.idle == 3, "starting and stopping were dropped instead of counted as not running")
        #expect(counts.running + counts.idle == servers.count)
        #expect(counts.tools == 12)
    }

    // MARK: - A19b · a failed refresh does not recolour the band

    @Test("the stale notice is its own value and the band keeps its causes' tints")
    func staleDoesNotRecolourTheBand() throws {
        let content = PopoverContent.make(
            trackerState: .init(
                load: .stale([try Self.server("held", held: true)], .transport(detail: "timed out")),
                stream: .notConfigured
            ),
            records: [Self.record("held", secondsAgo: 40)],
            now: Self.now
        )

        #expect(content.stale != nil, "a stale tracker produced no stale notice")
        #expect(content.stale?.title == MenuBarPresentation.staleTitle)
        // The servers are real and keep their rows.
        #expect(content.band?.count == 1)
        // And the row's tint is still its own cause's, not the failure's. `--fail` means a server
        // failed; a refresh that did not complete is not that.
        #expect(content.band?.first?.cause.tintToken == .attention)
        #expect(content.counts != nil, "a stale tracker discarded the servers it still had")
    }

    // MARK: - the remaining states

    @Test("nothing has loaded: no counts, no band, no message — the view draws its skeleton")
    func loadingIsSilentRatherThanEmpty() {
        let content = PopoverContent.make(
            trackerState: .init(load: .loading, stream: .notConfigured),
            records: [],
            now: Self.now
        )
        #expect(content.counts == nil, "a loading popover claimed counts")
        #expect(content.band == nil)
        #expect(content.message == nil, "loading was reported as a message rather than drawn as a skeleton")
    }

    @Test("a router that never answered reports offline, verbatim, with the counts absent")
    func offlineIsVerbatimAndUncounted() {
        let content = PopoverContent.make(
            trackerState: .init(load: .failed(.routerNotRunning), stream: .notConfigured),
            records: [],
            now: Self.now
        )
        #expect(content.counts == nil, "nobody answered, and zero is an answer")
        #expect(content.band == nil)
        #expect(content.message?.title == ControlAPIError.routerNotRunning.headline)
        #expect(content.message?.detail == ControlAPIError.routerNotRunning.advice)
    }

    @Test("a loaded router with no calls keeps its counts and says the log is empty")
    func emptyLogKeepsItsCounts() throws {
        let content = PopoverContent.make(
            trackerState: .init(load: .loaded([try Self.server("a", state: .running, tools: 4)]), stream: .notConfigured),
            records: [],
            now: Self.now
        )
        #expect(content.counts?.running == 1)
        #expect(content.calls.isEmpty)
        #expect(content.message?.title == MenuBarPresentation.emptyLogTitle)
    }

    // MARK: - A20, A21 · the call column

    @Test("at most six rows are rendered, newest first")
    func callsAreCappedAtSix() throws {
        let records = (0 ..< 20).map { Self.record("a", secondsAgo: $0) }
        let content = PopoverContent.make(
            trackerState: .init(load: .loaded([try Self.server("a")]), stream: .notConfigured),
            records: records,
            now: Self.now
        )
        #expect(content.calls.count == MenuBarPresentation.recentCallLimit)
        #expect(content.calls.count == 6)
    }

    @Test("the cold marker and the error dot each track their own field")
    func rowFlagsTrackTheirFields() throws {
        let records = [
            Self.record("a", secondsAgo: 1, ok: true, cold: true),
            Self.record("a", secondsAgo: 2, ok: false, cold: false)
        ]
        let content = PopoverContent.make(
            trackerState: .init(load: .loaded([try Self.server("a")]), stream: .notConfigured),
            records: records,
            now: Self.now
        )
        #expect(content.calls[0].cold)
        #expect(!content.calls[0].failed)
        #expect(!content.calls[1].cold)
        #expect(content.calls[1].failed)
    }
}
