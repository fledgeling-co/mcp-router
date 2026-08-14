import Foundation
import Testing
@testable import MCPRouterKit

/// The board's shape rules — which servers a filter admits, what a search matches, what the header
/// claims, and what a row carries. Split from `ServerPresentationTests`, which owns the two state
/// rules the prototype got wrong; these are the surrounding decisions.
@Suite("Servers board — filters, search, header and row")
struct ServerBoardShapeTests {
    static func server(
        name: String = "s",
        state: ServerState = .idle,
        placard: Placard? = nil,
        indexError: String? = nil,
        projects: [String] = [],
        tools: Int = 0,
        toolNames: [String] = [],
        calls: Int = 0
    ) throws -> MCPServer {
        var s = try FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)
        s.name = name
        s.state = state
        s.placard = placard
        s.indexError = indexError
        s.projects = projects
        s.tools = tools
        s.toolNames = toolNames
        s.usage = ServerUsage(calls: calls, errors: 0)
        return s
    }

    // MARK: - The filter

    @Test("Needs you includes a placarded server, not only needsAttention")
    func needsYouIncludesPlacards() throws {
        let placarded = try Self.server(placard: Placard(reason: "off", substitute: nil, until: nil))
        #expect(placarded.needsAttention == false, "precondition: a bare placard is not needsAttention")
        #expect(ServerFilter.needsYou.matches(placarded))
    }

    @Test("Running and Idle partition the servers exactly")
    func runningAndIdlePartition() throws {
        for state in ServerState.allCases {
            let s = try Self.server(state: state)
            #expect(ServerFilter.running.matches(s) != ServerFilter.idle.matches(s))
            #expect(ServerFilter.all.matches(s))
        }
    }

    /// **A24** — the prototype's single empty string ("Every server is behaving") is false under
    /// `Running`, where the truth is that nothing is up. Each filter answers for itself.
    @Test("A24 — every filter's empty copy is true for that filter")
    func emptyCopyIsPerFilter() {
        let messages = ServerFilter.allCases.map { $0.emptyMessage(totalServers: 8) }
        #expect(Set(messages.map(\.title)).count == ServerFilter.allCases.count)
        #expect(ServerFilter.running.emptyMessage(totalServers: 8).title == "Nothing is running")
        #expect(ServerFilter.idle.emptyMessage(totalServers: 8).title == "Everything is running")
        #expect(ServerFilter.needsYou.emptyMessage(totalServers: 8).title == "Nothing needs you")
        // The one claim that would be wrong under Running must not appear there.
        #expect(!ServerFilter.running.emptyMessage(totalServers: 8).detail.contains("behaving"))
        for message in messages {
            #expect(!message.title.isEmpty)
            #expect(!message.detail.isEmpty)
        }
    }

    // MARK: - Search

    @Test("Search matches a server by name and by any of its tool names")
    func searchMatchesNamesAndTools() throws {
        let s = try Self.server(name: "mobbin", toolNames: ["search_screens", "search_flows"])
        #expect(ServerSearch.matches(s, query: ""))
        #expect(ServerSearch.matches(s, query: "   "))
        #expect(ServerSearch.matches(s, query: "MOB"))
        #expect(ServerSearch.matches(s, query: "screens"))
        #expect(!ServerSearch.matches(s, query: "postgres"))
    }

    // MARK: - A9 · the header, and the figure that goes absent

    @Test("A9 — the running count is absent when the reading is not current")
    func runningCountGoesAbsentOnStale() throws {
        let servers = try [
            Self.server(name: "a", state: .running, tools: 30),
            Self.server(name: "b", state: .idle, tools: 12)
        ]
        let current = ServersBoardHeader(servers: servers, isCurrent: true)
        #expect(current.tools == 42)
        #expect(current.servers == 2)
        #expect(current.running == 1)
        #expect(current.subtitle() == "42 tools from 2 servers · 1 running")

        let stale = ServersBoardHeader(servers: servers, isCurrent: false)
        #expect(stale.running == nil, "a running count is a present-tense claim about a silent router")
        // No duration and no timestamp: nothing observes when the poll answered, so the stale form
        // claims only what is known. An earlier draft read `last read {ago}` from the newest
        // `lastUsed`, which is when a tool was *called* — a different fact wearing the same clothes.
        #expect(stale.subtitle() == "42 tools from 2 servers · last reading, not current")
        #expect(!stale.subtitle().contains("ago"))
        // The figures that are *not* present-tense survive: the declared configuration was observed.
        #expect(stale.tools == 42)
        #expect(stale.servers == 2)
    }

    /// The Partial state's sentence, and the fact behind it: the router reports `tools: 0` for a
    /// server whose index failed, so the total genuinely understates.
    @Test("Partial — an unindexed server is counted and named rather than quietly dropped")
    func partialNoteNamesUnindexedServers() throws {
        let clean = try ServersBoardHeader(servers: [Self.server(tools: 5)], isCurrent: true)
        #expect(clean.partialNote == nil)

        let broken = try ServersBoardHeader(
            servers: [
                Self.server(name: "a", tools: 5),
                Self.server(name: "b", indexError: "spawn ENOENT", tools: 0)
            ],
            isCurrent: true
        )
        #expect(broken.unindexed == 1)
        #expect(broken.partialNote?.contains("One server") == true)
        #expect(broken.partialNote?.contains("missing from this count") == true)
    }

    // MARK: - The row model

    @Test("The row's calls column is the lifetime count, not the current process's")
    func rowUsesLifetimeCalls() throws {
        var s = try Self.server(name: "obscura", state: .running, tools: 31, calls: 1204)
        // `callsServed` is the live child's own counter and resets every time the reaper closes it.
        s.callsServed = 0
        let row = ServerRowModel(server: s, idleMs: 300_000, pendingAuth: nil)
        #expect(row.calls == 1204, "a column reading callsServed would show 0 for a busy server")
        #expect(row.id == "obscura")
        #expect(row.breaker == BreakerState.running)
    }

    @Test("Row identity is the server's name, so a reorder cannot bleed state between rows")
    func rowIdentityIsTheName() throws {
        let a = try ServerRowModel(server: Self.server(name: "alpha"), idleMs: 300_000, pendingAuth: nil)
        let b = try ServerRowModel(server: Self.server(name: "beta"), idleMs: 300_000, pendingAuth: nil)
        #expect(a.id != b.id)
        #expect(a.id == "alpha")
    }
}
