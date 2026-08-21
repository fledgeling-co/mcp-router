import Foundation
import Testing
@testable import RouterCore

/// R7 — the harness that spells its endpoint `httpUrl`.
///
/// Its own file rather than more cases in `HarnessReconciliationTests`, because the subject is
/// different: those tests ask what the comparison concludes, these ask whether the reader can see
/// the entry at all. The defect this suite pins was the worst kind available to this item — Gemini
/// is the harness the brief was written about, it is wired directly, and a reader keying on `url`
/// alone reported it `not-wired` and then printed a remedy telling the user to create the state it
/// could not read.
///
/// The evidence for the key is not this file's invention: `agy` 1.1.17's MCP-server config struct
/// carries `json:"httpUrl"`, which is what `planning/specs/spec-R7.md` §1.2 cites and what
/// ``HTTPCapability/known(for:)`` prints for that harness.
@Suite("Harness dialect — httpUrl")
struct HarnessDialectTests {
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

    // MARK: - The route

    @Test("a Gemini entry spelling the endpoint httpUrl is wired via HTTP, not not-wired")
    func httpURLIsARoute() {
        let found = report([server("router", #"{"httpUrl":"\#(Self.endpoint)"}"#)], against: [])
        #expect(found.route == .directHTTP(name: "router", url: Self.endpoint))
        #expect(found.state == .wiredViaHTTP)
        #expect(found.headline == "wired via HTTP")
    }

    @Test("the remedy for an httpUrl-wired harness does not tell the user to wire it")
    func noRemedyForAWiredHarness() {
        let found = report([server("router", #"{"httpUrl":"\#(Self.endpoint)"}"#)], against: [])
        #expect(found.remedy == nil, "it is already wired; the old reader offered to wire it again")
    }

    @Test("an httpUrl on another port is not this router")
    func httpURLOnAnotherPort() {
        let found = report([server("r", #"{"httpUrl":"http://127.0.0.1:9999/mcp"}"#)], against: [])
        #expect(found.route == .notWired)
    }

    @Test("an httpUrl aimed off the machine is not this router")
    func httpURLOffMachine() {
        let found = report([server("r", #"{"httpUrl":"https://example.com/mcp"}"#)], against: [])
        #expect(found.route == .notWired)
    }

    @Test("url wins over httpUrl when an entry carries both")
    func urlTakesPrecedence() {
        let raw = #"{"url":"\#(Self.endpoint)","httpUrl":"http://127.0.0.1:9999/mcp"}"#
        #expect(Self.gemini.endpoint(in: entry(raw)) == Self.endpoint)
    }

    @Test("a decoy url elsewhere does not hide an httpUrl aimed at this router")
    func decoyURLDoesNotHideTheRoute() {
        let raw = #"{"url":"https://example.com/mcp","httpUrl":"\#(Self.endpoint)"}"#
        #expect(Self.gemini.endpoints(in: entry(raw)).count == 2)
        let found = report([server("router", raw)], against: [])
        #expect(
            found.route == .directHTTP(name: "router", url: Self.endpoint),
            "stopping at the first spelling is the same wrong answer one key along"
        )
    }

    @Test("a non-string url is not an endpoint and does not shadow a real one")
    func nonStringURLIsNotAnEndpoint() {
        #expect(Self.gemini.endpoints(in: entry(#"{"url":true}"#)).isEmpty)
        let raw = #"{"url":true,"httpUrl":"\#(Self.endpoint)"}"#
        #expect(Self.gemini.endpoint(in: entry(raw)) == Self.endpoint)
    }

    // MARK: - The dialect belongs to the harness, not to the reader

    @Test("only Gemini reads httpUrl; the same bytes in another harness's file are not a route")
    func theDialectIsPerClient() {
        #expect(HarnessDialect.known(for: .geminiCLI).endpointKeys == ["url", "httpUrl", "serverUrl"])
        for client in MCPClient.allCases where client != .geminiCLI {
            #expect(
                HarnessDialect.known(for: client).endpointKeys == ["url"],
                "\(client) has not been shown to read any other spelling"
            )
        }
        let raw = #"{"httpUrl":"\#(Self.endpoint)"}"#
        #expect(report([server("router", raw)], against: [], client: .geminiCLI).route
            == .directHTTP(name: "router", url: Self.endpoint))
        #expect(
            report([server("router", raw)], against: [], client: .cursor).route == .notWired,
            "reading Gemini's key out of a Cursor file is a claim about Cursor that nothing supports"
        )
    }

    @Test("an httpUrl entry in another harness's file is not canonicalised either")
    func canonicalisationIsPerClientToo() {
        let raw = #"{"httpUrl":"https://api.mobbin.com/mcp"}"#
        let mobbin = upstream("mobbin", #"{"type":"http","url":"https://api.mobbin.com/mcp"}"#)
        let onGemini = report(
            [server("router", #"{"httpUrl":"\#(Self.endpoint)"}"#), server("Mobbin", raw)],
            against: [mobbin], client: .geminiCLI
        )
        #expect(onGemini.duplicates.count == 1)
        let onCursor = report(
            [server("router", #"{"url":"\#(Self.endpoint)"}"#), server("Mobbin", raw)],
            against: [mobbin], client: .cursor
        )
        #expect(onCursor.duplicates.isEmpty, "cursor has not been shown to read httpUrl")
        #expect(onCursor.unparsed.count == 1, "and an entry nobody could read is reported, not dropped")
    }

    @Test("an empty url does not shadow a real httpUrl")
    func emptyURLDoesNotShadow() {
        let raw = #"{"url":"","httpUrl":"\#(Self.endpoint)"}"#
        #expect(Self.gemini.endpoint(in: entry(raw)) == Self.endpoint)
        let found = report([server("router", raw)], against: [])
        #expect(found.route == .directHTTP(name: "router", url: Self.endpoint))
    }

    @Test("an entry declaring neither key has no endpoint")
    func noEndpoint() {
        #expect(Self.gemini.endpoint(in: entry(#"{"command":"npx"}"#)) == nil)
        #expect(Self.gemini.endpoint(in: entry("[]")) == nil, "a non-object declares nothing")
    }

    // MARK: - The comparison

    @Test("an httpUrl duplicate is caught by identity, so the hash sees the same material both sides")
    func httpURLDuplicateByIdentity() {
        let found = report(
            [
                server("router", #"{"httpUrl":"\#(Self.endpoint)"}"#),
                server("Mobbin", #"{"httpUrl":"https://api.mobbin.com/mcp"}"#)
            ],
            against: [upstream("mobbin", #"{"type":"http","url":"https://api.mobbin.com/mcp"}"#)]
        )
        #expect(found.duplicates.count == 1, "canonicalising the raw is what makes the digests match")
        #expect(found.duplicates[0].harnessName == "Mobbin")
        #expect(found.duplicates[0].routerName == "mobbin")
        guard case .identity = found.duplicates[0].basis else {
            Issue.record("expected the identity basis, got \(found.duplicates[0].basis)")
            return
        }
    }

    @Test("an httpUrl entry is no longer reported as an unreadable stdio server with no command")
    func httpURLIsNotUnparsed() {
        let found = report(
            [
                server("router", #"{"httpUrl":"\#(Self.endpoint)"}"#),
                server("elsewhere", #"{"httpUrl":"https://example.com/mcp"}"#)
            ],
            against: []
        )
        #expect(
            found.unparsed.isEmpty,
            "before the widening this read: elsewhere: stdio server has no command"
        )
        #expect(found.entryCount == 1)
    }

    @Test("what leaves resolution declares one endpoint under one key")
    func canonicalDropsTheOtherSpelling() {
        guard case let .entry(rewritten) = Self.gemini.resolve(
            server("x", #"{"httpUrl":"https://example.com/mcp","timeout":5}"#)
        ) else {
            Issue.record("one spelling is not a conflict")
            return
        }
        #expect(rewritten.raw.member("url")?.asString?.string == "https://example.com/mcp")
        #expect(rewritten.raw.member("httpUrl") == nil, "two spellings of one endpoint is not canonical")
        #expect(rewritten.raw.member("timeout") != nil, "and nothing else about the entry is lost")
    }

    @Test("resolution leaves an entry that already spells it url exactly as it was")
    func canonicalIsIdempotent() {
        let original = server("x", #"{"type":"http","url":"https://example.com/mcp"}"#)
        #expect(Self.gemini.resolve(original) == .entry(original))
        let stdio = server("y", #"{"command":"npx","args":["-y","a"]}"#)
        #expect(Self.gemini.resolve(stdio) == .entry(stdio))
    }

    // MARK: - The whole measured shape, end to end

    @Test("the measured Gemini shape: wired on httpUrl, carrying duplicates, and offered no add")
    func theMeasuredShape() {
        let refRaw = #"{"command":"npx","args":["-y","ref-tools-mcp@3.0.3"]}"#
        let found = report(
            [
                server("router", #"{"httpUrl":"\#(Self.endpoint)"}"#),
                server("obscura", #"{"command":"obscura","args":["mcp"]}"#),
                server("Ref", refRaw)
            ],
            against: [
                upstream("obscura", #"{"command":"obscura","args":["mcp"]}"#),
                upstream("ref-tools-mcp", refRaw)
            ]
        )
        #expect(found.state == .wiredWithDuplicates(
            route: .directHTTP(name: "router", url: Self.endpoint), count: 2
        ))
        let plan = ReconciliationPlan.from(found)
        #expect(plan.addRouterEntry == nil, "the harness is wired; proposing to wire it is the defect")
        #expect(plan.replaceShim == nil, "there is no shim to replace")
        #expect(plan.remove == ["obscura", "Ref"])
        #expect(!plan.render().contains("+ add"))
    }
}
