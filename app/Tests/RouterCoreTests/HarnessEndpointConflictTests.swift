import Foundation
import Testing
@testable import RouterCore

/// R7, second pass — **the key `agy` writes, and what to do when an entry declares two.**
///
/// Split out of ``HarnessDialectTests`` rather than added to it: that suite pins the first pass's
/// widening, this one pins the second's, and one struct holding both trips swiftlint's
/// `type_body_length` — which is the honest signal that they are two subjects.
@Suite("Harness dialect — serverUrl, and two spellings that disagree")
struct HarnessEndpointConflictTests {
    static let port = 8879
    static let endpoint = "http://127.0.0.1:8879/mcp"
    static let gemini = HarnessDialect.known(for: .geminiCLI)

    private func entry(_ json: String) -> JSONValue {
        // swiftlint:disable:next force_try
        try! JSONParser.parse(Data(json.utf8))
    }

    private func server(_ name: String, _ json: String) -> DiscoveredServer {
        DiscoveredServer(name: name, raw: entry(json))
    }

    private func upstream(_ name: String, _ json: String) -> UpstreamConfig {
        guard case let .upstream(parsed) = ServerParser.parse(name: name, raw: entry(json)) else {
            fatalError("fixture \(name) is not adoptable")
        }
        return parsed
    }

    private func report(
        _ entries: [DiscoveredServer], against upstreams: [UpstreamConfig], client: MCPClient = .geminiCLI
    ) -> HarnessReport {
        HarnessReconciliation.report(
            client: client, path: "/tmp/fixture", result: .servers(entries),
            upstreams: upstreams, port: Self.port
        )
    }

    // MARK: - the panel's two, and one it raised that the measurement refused

    @Test("a stdio entry keeps its own identity, whatever endpoint key is left lying beside it")
    func aStdioEntryIsNotPromotedToHTTP() {
        // `ServerParser` selects the transport from a truthy `url` whenever `type` is absent, so
        // rewriting a stdio entry's leftover `serverUrl` into `url` would flip its parse to HTTP and
        // send `UpstreamHash` the stale address instead of the command. The router fronts this
        // server over stdio; the comparison has to still see that.
        //
        // The harness entry is deliberately NOT named `fetch`. A name match is settled before an
        // endpoint is resolved at all (`D-r7-y`), so an entry sharing the upstream's name would go
        // on passing this test with the defect restored — which is what the first version of it did.
        let stale = #"{"command":"uvx","args":["mcp-server-fetch"],"serverUrl":"http://127.0.0.1:9999/x"}"#
        let found = report(
            [server("browser", stale)],
            against: [upstream("fetch", #"{"command":"uvx","args":["mcp-server-fetch"]}"#)]
        )
        #expect(found.duplicates.count == 1, "the stdio duplicate is what the entry actually is")
        #expect(found.unparsed.isEmpty)
        #expect(found.route == .notWired, "a stale endpoint on a stdio entry is not a route")
        // The other direction: with no command, the same spelling is still promoted and compared.
        let http = report(
            [server("fetch", #"{"serverUrl":"http://127.0.0.1:9999/x"}"#)],
            against: [upstream("fetch2", #"{"url":"http://127.0.0.1:9999/x"}"#)]
        )
        #expect(http.duplicates.count == 1, "an HTTP entry under a non-standard key is still resolved")
    }

    @Test("two spellings that differ only in a trailing slash are one endpoint, not a disagreement")
    func aTrailingSlashIsNotAConflict() {
        // The conflict rule and the route rule have to use one notion of sameness. `endpointPath`
        // already folds a single trailing slash, so a conflict check comparing raw strings would
        // contradict it and push a readable entry into `unparsed` — B4's own silent zero, arriving
        // through formatting instead of a decoy.
        let agreeing = #"{"url":"http://127.0.0.1:9999/x","serverUrl":"http://127.0.0.1:9999/x/"}"#
        let found = report(
            [server("m", agreeing)],
            against: [upstream("m2", #"{"url":"http://127.0.0.1:9999/x"}"#)]
        )
        #expect(found.unparsed.isEmpty, "nothing here is unreadable")
        #expect(found.duplicates.count == 1)
        // The other direction: two spellings naming different places still conflict.
        let differing = #"{"url":"http://127.0.0.1:9999/x","serverUrl":"http://127.0.0.1:9999/y"}"#
        let split = report(
            [server("m", differing)],
            against: [upstream("m2", #"{"url":"http://127.0.0.1:9999/x"}"#)]
        )
        #expect(split.duplicates.isEmpty)
        #expect(split.unparsed.count == 1)
    }

    @Test("one trailing slash is tolerated and two are not")
    func onlyOneTrailingSlashIsFolded() {
        #expect(RouterEndpoint.endpointPath(of: "http://127.0.0.1:8879/mcp/") == "/mcp")
        #expect(RouterEndpoint.endpointPath(of: "http://127.0.0.1:8879/mcp//") == "/mcp/")
        #expect(RouterEndpoint.isThisRouter(url: "http://127.0.0.1:8879/mcp/", port: Self.port))
        #expect(!RouterEndpoint.isThisRouter(url: "http://127.0.0.1:8879/mcp//", port: Self.port))
    }

    @Test("a URL JSURL refuses is refused by the whole predicate, not half of it")
    func bothHalvesAgreeOnAThirdSlash() {
        // A reviewer read `parts`' two-slash limit as diverging from `JSURL`. Measured: `JSURL`
        // consumes at most two as well, and for `http:///…` that leaves an empty host, which it
        // rejects outright for a special scheme other than `file`. So the predicate refuses at the
        // first guard and the path reader is never consulted — the two halves agree.
        #expect(JSURL("http:///127.0.0.1:8879/mcp") == nil)
        #expect(!RouterEndpoint.isThisRouter(url: "http:///127.0.0.1:8879/mcp", port: Self.port))
        #expect(RouterEndpoint.isThisRouter(url: "http:/127.0.0.1:8879/mcp", port: Self.port))
    }

    // MARK: - serverUrl — the key the harness actually writes

    @Test("a Gemini entry spelling the endpoint serverUrl is wired via HTTP, with no shim")
    func serverURLIsARoute() {
        // `serverUrl` is what `agy` 1.1.17 writes into `~/.gemini/config/mcp_config.json`: its help
        // text names it as the required HTTP key, its error string is `MCP server %q must have
        // either command or serverUrl`, and the router's own entry on this machine is exactly
        // `{"serverUrl": "http://127.0.0.1:8879/mcp"}`. The first pass added `httpUrl` — a struct
        // tag — and left the harness's written spelling unread.
        let found = report([server("router", #"{"serverUrl":"\#(Self.endpoint)"}"#)], against: [])
        #expect(found.route == .directHTTP(name: "router", url: Self.endpoint))
        #expect(found.state == .wiredViaHTTP)
        #expect(found.headline == "wired via HTTP")
        #expect(found.remedy == nil)
        let plan = ReconciliationPlan.from(found)
        #expect(plan.replaceShim == nil, "there is no shim; proposing to replace one is the defect")
        #expect(plan.addRouterEntry == nil)
    }

    @Test("a serverUrl duplicate is caught by identity, so the digest sees the same material")
    func serverURLDuplicateByIdentity() {
        let found = report(
            [
                server("router", #"{"serverUrl":"\#(Self.endpoint)"}"#),
                server("Mobbin", #"{"serverUrl":"https://api.mobbin.com/mcp"}"#)
            ],
            against: [upstream("mobbin", #"{"type":"http","url":"https://api.mobbin.com/mcp"}"#)]
        )
        #expect(found.duplicates.count == 1)
        #expect(found.unparsed.isEmpty)
        #expect(found.duplicates.first?.harnessName == "Mobbin")
    }

    @Test("the second key holds the same line the first one does: serverUrl is Gemini's, not Cursor's")
    func serverURLIsPerClientToo() {
        // F1 inverted a second time is the defect all three panel lanes caught in pass 1, so the
        // per-client rule is asserted under the NEW key as well as the old one. A `serverUrl` in a
        // Cursor or Codex file is an inert member of an object this item merely inspects.
        for client in MCPClient.allCases where client != .geminiCLI {
            #expect(!HarnessDialect.known(for: client).endpointKeys.contains("serverUrl"))
        }
        let raw = #"{"serverUrl":"\#(Self.endpoint)"}"#
        #expect(report([server("router", raw)], against: [], client: .cursor).route == .notWired)
        #expect(report([server("router", raw)], against: [], client: .codexCLI).route == .notWired)
        #expect(report([server("router", raw)], against: [], client: .geminiCLI).route
            == .directHTTP(name: "router", url: Self.endpoint))
    }

    // MARK: - Two spellings that disagree

    @Test("a decoy url beside a real httpUrl is reported, never silently counted as no-duplicate")
    func decoyURLDoesNotEraseADuplicate() {
        let mobbin = upstream("mobbin", #"{"type":"http","url":"https://api.mobbin.com/mcp"}"#)
        let real = report(
            [server("Mobbin", #"{"httpUrl":"https://api.mobbin.com/mcp"}"#)], against: [mobbin]
        )
        #expect(real.duplicates.count == 1, "the control: without the decoy this is a duplicate")

        let decoyed = report(
            [server(
                "Mobbin",
                #"{"httpUrl":"https://api.mobbin.com/mcp","url":"https://decoy.example/mcp"}"#
            )],
            against: [mobbin]
        )
        #expect(
            decoyed.duplicates.count + decoyed.unparsed.count >= 1,
            "spec §4: an entry nobody could read is never silently counted as no-duplicate"
        )
        #expect(decoyed.unparsed.count == 1)
        #expect(decoyed.unparsed.first?.contains("Mobbin") == true)
    }

    @Test("the decoy in the other direction is refused too, rather than resolved by precedence")
    func decoyInTheOtherDirection() {
        // `D-r7-p` recorded the precedence as "the right answer for a yes/no question". It is not:
        // it is the right answer for the ROUTE, which asks yes/no of every spelling, and the wrong
        // answer for the COMPARISON, which has to pick one and had no evidence for the pick. Here
        // the standard key holds the real endpoint and the harness's own key holds the decoy — the
        // shape where precedence happens to be right — and it is still refused, because the
        // instrument cannot tell this apart from the shape where precedence is wrong.
        let mobbin = upstream("mobbin", #"{"type":"http","url":"https://api.mobbin.com/mcp"}"#)
        let found = report(
            [server(
                "Mobbin",
                #"{"url":"https://api.mobbin.com/mcp","httpUrl":"https://decoy.example/mcp"}"#
            )],
            against: [mobbin]
        )
        #expect(found.duplicates.isEmpty)
        #expect(found.unparsed.count == 1)
    }

    @Test("two NON-standard spellings that disagree are refused as well")
    func twoNonStandardSpellingsDisagreeing() {
        // The route nobody has named for this finding. Every case anybody has written down pits the
        // standard `url` against a harness key, so a rule reading "url wins" looks total. With
        // three keys in Gemini's dialect there is a pair with no standard member in it at all, and
        // precedence there is not even wearing the shape of a rule.
        let found = report(
            [server(
                "x",
                #"{"httpUrl":"https://a.example/mcp","serverUrl":"https://b.example/mcp"}"#
            )],
            against: []
        )
        #expect(found.unparsed.count == 1)
        #expect(found.duplicates.isEmpty)
    }

    @Test("two spellings that AGREE are one endpoint, not a conflict")
    func agreeingSpellingsAreNotAConflict() {
        let mobbin = upstream("mobbin", #"{"type":"http","url":"https://api.mobbin.com/mcp"}"#)
        let found = report(
            [server(
                "Mobbin",
                #"{"url":"https://api.mobbin.com/mcp","serverUrl":"https://api.mobbin.com/mcp"}"#
            )],
            against: [mobbin]
        )
        #expect(found.unparsed.isEmpty, "a redundant spelling is not a disagreement")
        #expect(found.duplicates.count == 1)
    }

    @Test("a disagreeing entry still cannot hide a route aimed at this router")
    func aConflictDoesNotHideTheRoute() {
        // Detection and comparison ask different questions of the same bytes, and only the second
        // one has to choose. The route still tests EVERY spelling, so a decoy cannot make a wired
        // harness read unwired and collect a plan offering to wire it.
        let found = report(
            [server("router", #"{"url":"https://decoy.example/mcp","serverUrl":"\#(Self.endpoint)"}"#)],
            against: []
        )
        #expect(found.route == .directHTTP(name: "router", url: Self.endpoint))
    }
}
