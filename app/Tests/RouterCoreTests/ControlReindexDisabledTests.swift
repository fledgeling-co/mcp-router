import Foundation
import Testing
@testable import RouterCore

/// M29, oracle line 5's second half — **`POST /servers/:name/reindex` still works on a disabled
/// server**, through `ControlHandler.handle` rather than by calling the indexer.
///
/// Through the handler for `ControlApproveDispatchTests`' reason: the risk here is not a broken
/// function but a guard added in the wrong place. *Disabled servers are not indexed* is true of the
/// automatic sweeps and false of this route, and a `disabled` check placed at the dispatch arm — or
/// at `ControlDeps`' upstream lookup — would read as an obvious tidy-up and would remove the only
/// way a user has to re-read a switched-off server's tool surface before switching it back on.
@Suite("M29 — reindex reaches a disabled server")
struct ControlReindexDisabledTests {
    typealias Support = ControlAuthSupport

    private static let config = """
    {
      "mcpServers": {
        "off": { "command": "/bin/echo", "args": ["hello"], "disabled": true },
        "on": { "command": "/bin/echo", "args": ["hello"] }
      }
    }
    """

    @Test("a disabled server can still be reindexed, by the user asking for it")
    func reindexReachesADisabledServer() async throws {
        let calls = AuthDispatchCalls()
        var deps = try Support.makeDeps(calls: calls, config: Self.config)
        #expect(
            deps.upstreams.first { $0.name.string == "off" }?.upstream.disabled == true,
            "the fixture's server is not disabled; the assertions below prove nothing"
        )

        let (status, body) = await Support.answer("/servers/off/reindex", &deps)

        #expect(status == 200)
        #expect(calls.indexed == ["off"], "the user's own reindex was refused or silently skipped")
        #expect(body.contains("\"name\": \"off\"") || body.contains("\"name\":\"off\""))
    }

    /// The pair: the same request against a server that is not disabled reaches the indexer too, so
    /// the assertion above measures *reindex ignores the switch* rather than *reindex works*.
    @Test("an enabled server reindexes by the same route, and the two answers agree")
    func bothServersReachTheIndexer() async throws {
        let calls = AuthDispatchCalls()
        var deps = try Support.makeDeps(calls: calls, config: Self.config)

        let off = await Support.answer("/servers/off/reindex", &deps)
        let live = await Support.answer("/servers/on/reindex", &deps)

        #expect(off.status == live.status)
        #expect(calls.indexed == ["off", "on"])
    }

    /// And the route is a **write the user asked for**, so it is still behind the token. A guard
    /// that let it through unauthenticated would be a wider hole than the one this item opened.
    @Test("reindex on a disabled server is still refused without the control token")
    func stillNeedsTheToken() async throws {
        let calls = AuthDispatchCalls()
        var deps = try Support.makeDeps(calls: calls, config: Self.config)

        let (status, _) = await Support.answer("/servers/off/reindex", &deps, authorized: false)

        #expect(status == 401)
        #expect(calls.indexed.isEmpty)
    }
}
