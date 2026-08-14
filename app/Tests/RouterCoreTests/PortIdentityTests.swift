import Foundation
import Testing
@testable import RouterCore

/// S5 and B24 across the **port** seam.
///
/// `ControlDeps.upstream(named:)` already looked servers up by code units. The ports did not: the
/// pool and the credential store took Swift `String`, and Swift compares strings by canonical
/// equivalence, so a decomposed `"café"` and a composed one are the same key to it and two
/// different keys to the reference.
///
/// ## This defect is latent, and saying so is the point
///
/// It cannot be reached through `servers.json` today, and the tests below record why: `ServerParser`
/// refuses any name outside `[A-Za-z0-9_-]+`, so every name that reaches a port is ASCII, and ASCII
/// has one spelling. A request path *can* carry a decomposed name, but it is resolved against the
/// live map by ``ControlDeps/upstream(named:)`` — already code-unit keyed — and a non-matching name
/// 404s before any port is touched.
///
/// The typing is kept anyway, for two reasons that are not "defence in depth". The gate that makes
/// this unreachable exists to keep a name usable as a **tool namespace**, not to make it
/// comparison-safe; it is one clause change away from admitting Unicode, and nothing about that
/// change would advertise that it had re-armed a matching bug three files away. And `UpstreamPoolPort`
/// and `AuthStore` are the seams **R2 and R5 implement against** — a `String` parameter there is an
/// invitation to those items to key their own storage by Swift string equality, where the blast
/// radius is a token record read for the wrong server. The type is the cheapest way to say which
/// comparison is meant.
struct PortIdentityTests {
    /// U+00E9 — one code unit.
    static let composed = "caf\u{00E9}"
    /// U+0065 U+0301 — two code units.
    static let decomposed = "cafe\u{0301}"

    // MARK: - The red half

    @Test("Swift's own comparison conflates the two spellings; JSString does not")
    func swiftStringConflates() {
        // The defect, stated as an assertion. Every `==` on a Swift `String` key would behave this
        // way, and the reference's `===` does not.
        #expect(Self.composed == Self.decomposed)
        #expect(JSString(Self.composed) != JSString(Self.decomposed))
        #expect(JSString(Self.composed).units.count == 4)
        #expect(JSString(Self.decomposed).units.count == 5)
    }

    // MARK: - The seam itself

    struct Pool: UpstreamPoolPort {
        var live: [LiveUpstream] = []
        var pendingRows: [PendingAuthRow] = []
        func status() -> [LiveUpstream] {
            live
        }

        func pending() -> [PendingAuthRow] {
            pendingRows
        }

        func isLive(_: JSString) -> Bool {
            false
        }

        func warmUp() {}
        func clearPending(_: JSString) {}
    }

    @Test("firstStatus does not match a decomposed row against a composed name")
    func statusLookupIsCodeUnitKeyed() {
        let pool = Pool(live: [
            LiveUpstream(name: JSString(Self.decomposed), state: "live", callsServed: 9)
        ])
        #expect(pool.firstStatus(JSString(Self.composed)) == nil)
        #expect(pool.firstStatus(JSString(Self.decomposed))?.callsServed == 9)
    }

    @Test("firstPending does not lend one spelling's authorization URL to the other")
    func pendingLookupIsCodeUnitKeyed() {
        let pool = Pool(pendingRows: [
            PendingAuthRow(server: JSString(Self.decomposed), url: "https://example.invalid/auth")
        ])
        #expect(pool.firstPending(JSString(Self.composed)) == nil)
        #expect(pool.firstPending(JSString(Self.decomposed))?.url == "https://example.invalid/auth")
    }

    @Test("first match wins, not last — B6 and B7")
    func lookupTakesFirstMatch() {
        let pool = Pool(live: [
            LiveUpstream(name: "dup", state: "live", callsServed: 1),
            LiveUpstream(name: "dup", state: "idle", callsServed: 2)
        ])
        #expect(pool.firstStatus("dup")?.callsServed == 1, "last(where:) passes any single-row fixture")
    }

    // MARK: - Why the describe() path cannot reach it

    @Test("a non-ASCII server name is refused by the config layer, which is what makes this latent")
    func nonASCIINamesNeverBecomeUpstreams() throws {
        for name in [Self.composed, Self.decomposed] {
            let parsed = try ServerParser.parse(
                name: name, raw: JSONParser.parse("{\"command\":\"/bin/echo\"}")
            )
            guard case let .skipped(reason) = parsed else {
                Issue.record("""
                \(name) was accepted as an upstream — the name gate has widened, and the pool and \
                auth seams are now reachable with two spellings of one name
                """)
                continue
            }
            #expect(reason.contains("[A-Za-z0-9_-]+"))
        }
    }

    /// Shared by `RawFieldParityTests` — a `ControlDeps` over caller-supplied upstreams, with
    /// every dependency inert so the row is a function of the config alone.
    static func deps(
        upstreams: [(name: JSString, upstream: UpstreamConfig)]
    ) throws -> ControlDeps {
        let clock = ManualClock(milliseconds: 1_770_000_000_000)
        return ControlDeps(
            config: RouterConfig(
                port: 8971, host: "127.0.0.1", idleMs: 300_000, startupTimeoutMs: 60000,
                upstreams: upstreams.map(\.upstream), manifestPath: "/tmp/m.json",
                logPath: "/tmp/r.log", usagePath: "/tmp/mcprouter-none/u.jsonl",
                statsPath: "/tmp/mcprouter-none/s.json", authDir: "/tmp/auth"
            ),
            upstreams: upstreams,
            pool: Pool(),
            indexer: NeverIndexer(),
            auth: NoAuth(),
            usage: UsageStore(
                logPath: "/tmp/mcprouter-none/u.jsonl",
                statsPath: "/tmp/mcprouter-none/s.json", clock: clock
            ),
            manifest: .empty,
            clock: clock,
            tokenPath: "/tmp/control.token",
            configPath: "/tmp/servers.json"
        )
    }

    struct NoAuth: AuthStore {
        func hasTokens(_: JSString) -> Bool {
            false
        }

        func authorizedAt(_: JSString) -> String? {
            nil
        }

        @discardableResult func clear(_: JSString) -> Bool {
            false
        }
    }

    struct NeverIndexer: UpstreamIndexerPort {
        func index(_: UpstreamConfig) async -> IndexOutcome {
            IndexOutcome(tools: 0)
        }
    }

    @Test("an ASCII name round-trips through JSString unchanged, so the typing costs nothing")
    func asciiRoundTrips() {
        for name in ["fixture-stdio", "a_b", "Server1"] {
            #expect(JSString(name).string == name)
            #expect(JSString(JSString(name).string) == JSString(name))
        }
    }
}

/// Header normalisation — the determinism half of B17.
///
/// Headers used to live in a `[String: String]`, and `header(_:)` scanned it with
/// `first(where:)`. `Dictionary` iteration order is not defined, so a request carrying two
/// spellings of one name resolved to whichever the hash seed happened to yield first: the same
/// bytes could authorize on one run and 401 on the next. These pin the Node semantics instead.
struct HeaderNormalizationTests {
    @Test("names are lowercased once, at construction")
    func lowercasesNames() {
        let request = ControlAPIRequest(
            method: "POST", encodedPath: "/servers",
            headers: [(name: "Content-Type", value: "application/json")]
        )
        #expect(request.headers.map(\.name) == ["content-type"])
        #expect(request.header("CONTENT-TYPE") == "application/json")
    }

    @Test("repeated names join with a comma and a space, in arrival order")
    func joinsRepeats() {
        // Node's `req.headers` presents duplicates already joined; a handler never sees two.
        let request = ControlAPIRequest(
            method: "POST", encodedPath: "/servers",
            headers: [
                (name: "Authorization", value: "Bearer one"),
                (name: "authorization", value: "Bearer two")
            ]
        )
        #expect(request.headers.count == 1)
        #expect(request.header("authorization") == "Bearer one, Bearer two")
    }

    @Test("the join is deterministic across constructions of the same request")
    func joinIsDeterministic() {
        // The red half: with a dictionary this assertion passed or failed by hash seed. Repeating
        // it many times is what made the old behaviour visible at all.
        let pairs = [
            (name: "X-A", value: "1"), (name: "x-a", value: "2"),
            (name: "X-B", value: "3"), (name: "x-b", value: "4")
        ]
        let expected = ControlAPIRequest(method: "GET", encodedPath: "/servers", headers: pairs).headers
        for _ in 0 ..< 200 {
            let again = ControlAPIRequest(method: "GET", encodedPath: "/servers", headers: pairs).headers
            #expect(again.map(\.name) == expected.map(\.name))
            #expect(again.map(\.value) == expected.map(\.value))
        }
        #expect(expected.map(\.name) == ["x-a", "x-b"])
        #expect(expected.map(\.value) == ["1, 2", "3, 4"])
    }

    @Test("first arrival sets the position, so order follows the request not the hash")
    func orderFollowsArrival() {
        let request = ControlAPIRequest(
            method: "GET", encodedPath: "/servers",
            headers: [(name: "z", value: "1"), (name: "a", value: "2"), (name: "Z", value: "3")]
        )
        #expect(request.headers.map(\.name) == ["z", "a"])
        #expect(request.header("z") == "1, 3")
    }
}
