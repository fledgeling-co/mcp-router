import Foundation
import Testing
@testable import RouterCore

/// R31 — the `/caches` family, **through `ControlHandler.handle`**.
///
/// Through the handler rather than by calling the response builders, for the reason
/// `ControlExtensionRoutesTests` gives: `D-j` was never a broken function, it was a missing
/// dispatch arm, and a test that calls the function cannot fail when the arm is deleted. The
/// daemon's own wiring is a third thing again, and `scripts/acceptance/r31-caches.sh` drives the
/// socket for that.
@Suite("R31 control routes")
struct ControlCacheRoutesTests {
    typealias Support = ControlAuthSupport

    /// A config whose one stdio server is an `npx` invocation, because that is the shape the item
    /// is about. The default fixture's `/bin/echo` resolves as a local file and would exercise the
    /// other half.
    private static let config = """
    {
      "mcpServers": {
        "refs": { "command": "npx", "args": ["-y", "ref-tools-mcp@3.0.3"] },
        "p1-http": { "url": "https://example.invalid/mcp", "type": "http", "oauth": true }
      }
    }
    """

    private static func probe() -> StubCacheProbe {
        StubCacheProbe(
            entries: [
                CacheFixture.entry("/npx/aaa", "ref-tools-mcp", spec: "^3.0.3", version: "3.0.3", bytes: 100),
                CacheFixture.entry("/npx/ccc", "vitest", spec: "^4.1.11", version: "4.1.11", bytes: 25),
                NpxEntry(directory: "/npx/ddd", requested: [], bytes: 7)
            ],
            versions: [PluginVersion(
                marketplace: "market", plugin: "plug", version: "1.0.0",
                directory: "/plugins/market/plug/1.0.0", bytes: 9
            )]
        )
    }

    private static func answer(
        _ path: String, method: String = "GET", body: String? = nil, authorized: Bool = true,
        _ deps: inout ControlDeps
    ) async -> (status: Int, body: String) {
        var headers: [(name: String, value: String)] = [
            (name: "content-type", value: "application/json")
        ]
        if authorized { headers.append((name: "x-mcpr-token", value: Support.token)) }
        let response = await ControlHandler(token: Support.token).handle(
            ControlAPIRequest(
                method: method, encodedPath: path, query: [], headers: headers,
                body: body.map { Data($0.utf8) }
            ),
            &deps
        )
        guard case let .bytes(bytes) = response.body else { return (response.status, "") }
        // swiftlint:disable:next optional_data_string_conversion
        return (response.status, String(decoding: bytes, as: UTF8.self))
    }

    @Test("R1 — GET /caches answers all three caches, with what re-fetches each row")
    func inventoryCoversThreeCaches() async throws {
        var deps = try Support.makeDeps(config: Self.config)
        deps.caches = Self.probe()

        let answer = await Self.answer("/caches", &deps)
        #expect(answer.status == 200)
        for cache in CacheName.allCases {
            #expect(answer.body.contains(#""cache":"\#(cache.rawValue)""#))
        }
        #expect(answer.body.contains(#""refetch":"npx -y ref-tools-mcp@^3.0.3""#))
        #expect(answer.body.contains(#""irreplaceable":1"#))
        // The bytes figure carries its own denominator, so a partly-unreadable cache reads as a
        // floor rather than as a total.
        #expect(answer.body.contains(#""unmeasured":0"#))
    }

    @Test("R2 — POST plans by default and changes nothing")
    func planningIsTheDefault() async throws {
        var deps = try Support.makeDeps(config: Self.config)
        let probe = Self.probe()
        deps.caches = probe

        let planned = await Self.answer(
            "/caches/invalidate", method: "POST", body: #"{"server":"refs"}"#, &deps
        )
        #expect(planned.status == 200)
        #expect(planned.body.contains(#""applied":false"#))
        #expect(planned.body.contains(#""effect":"remove-directory""#))
        #expect(planned.body.contains(#""effect":"reindex-server""#))
        // The whole point of a plan: nothing happened.
        #expect(probe.removed.all.isEmpty)
        // And `vitest` is 25 bytes of another package's cache the plan never named.
        #expect(planned.body.contains("/npx/ccc") == false)
    }

    @Test("R3 — apply removes the named trees and names the re-index, and only then")
    func applyIsExplicit() async throws {
        var deps = try Support.makeDeps(config: Self.config)
        let probe = Self.probe()
        deps.caches = probe

        let applied = await Self.answer(
            "/caches/invalidate", method: "POST", body: #"{"server":"refs","apply":true}"#, &deps
        )
        #expect(applied.status == 200)
        #expect(applied.body.contains(#""applied":true"#))
        #expect(probe.removed.all == ["/npx/aaa"])
        #expect(applied.body.contains(#""reindex":["refs"]"#))
        #expect(applied.body.contains(#""failures":[]"#))
    }

    @Test("R4 — the wholesale clear is refused with its cost, and taken once the cost is named")
    func wholesaleAsks() async throws {
        var deps = try Support.makeDeps(config: Self.config)
        let probe = Self.probe()
        deps.caches = probe

        let refused = await Self.answer(
            "/caches/invalidate", method: "POST", body: #"{"everyNpxEntry":true,"apply":true}"#, &deps
        )
        #expect(refused.status == 409)
        #expect(refused.body.contains(#""reason":"cost-not-acknowledged""#))
        #expect(refused.body.contains(#""fallbackBytes":125"#))
        #expect(probe.removed.all.isEmpty)

        let taken = await Self.answer(
            "/caches/invalidate", method: "POST",
            body: #"{"everyNpxEntry":true,"apply":true,"acknowledgeBytes":125}"#, &deps
        )
        #expect(taken.status == 200)
        #expect(probe.removed.all.sorted() == ["/npx/aaa", "/npx/ccc"])
        // `/npx/ddd` names no package, so nothing can be said to re-fetch it, so it stays — even
        // under a request to clear everything.
        #expect(taken.body.contains(#""path":"/npx/ddd""#))
    }

    @Test("R5 — the refusals: no target, unknown target, no probe, and an unauthorized mutation")
    func refusals() async throws {
        var deps = try Support.makeDeps(config: Self.config)
        deps.caches = Self.probe()

        let noTarget = await Self.answer("/caches/invalidate", method: "POST", body: "{}", &deps)
        #expect(noTarget.status == 400)
        #expect(noTarget.body.contains(#""reason":"no-target""#))

        // Two at once is a 400 rather than a guess about which was meant.
        let ambiguous = await Self.answer(
            "/caches/invalidate", method: "POST",
            body: #"{"server":"refs","npxPackage":"vitest"}"#, &deps
        )
        #expect(ambiguous.status == 400)

        let unknown = await Self.answer(
            "/caches/invalidate", method: "POST", body: #"{"server":"ghost"}"#, &deps
        )
        #expect(unknown.status == 404)
        #expect(unknown.body.contains(#""reason":"no-such-server""#))

        let unauthorized = await Self.answer(
            "/caches/invalidate", method: "POST", body: #"{"server":"refs"}"#,
            authorized: false, &deps
        )
        #expect(unauthorized.status == 401)

        var without = try Support.makeDeps(config: Self.config)
        without.caches = nil
        let missing = await Self.answer("/caches", &without)
        #expect(missing.status == 503)
        #expect(missing.body.contains("no cache probe"))
    }
}
