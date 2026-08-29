import Foundation
import Testing
@testable import RouterCore

/// R26 — the auth-expiry routes, **through `ControlHandler.handle`**.
///
/// Through the handler rather than by calling the response builders, for the reason
/// `ControlHealthRoutesTests` gives: `D-j` was never a broken function, it was a missing dispatch
/// arm, and a test that calls the builder directly cannot fail when the arm is deleted. The
/// daemon's own wiring is a third thing again, and `scripts/acceptance/r26-auth-expiry.sh` drives
/// the socket for that.
@Suite("R26 control routes")
struct ControlAuthExpiryRoutesTests {
    typealias Support = ControlAuthSupport

    /// The clock `ControlAuthSupport.makeDeps` fixes, so a record seeded here can be placed
    /// relative to the moment the route will read.
    private static let now: Double = 1_770_000_000_000
    private static let authDir = "/router/auth"

    private static func monitor(
        _ records: [String: String],
        policy: AuthExpiryPolicy = .standard,
        refusals: [AuthExpiryRefusal] = []
    ) -> AuthExpiryMonitor {
        let fileSystem = AuthTestFileSystem()
        for (server, json) in records {
            fileSystem.memory.seed(
                json, atPath: AuthPaths.recordPath(authDir: authDir, server: JSString(server))
            )
        }
        return AuthExpiryMonitor(
            upstreams: [stdioUpstream("p1-stdio"), httpUpstream("p1-http")],
            policy: policy,
            refusals: refusals,
            auth: FileAuthStore(authDir: authDir, fileSystem: fileSystem),
            verb: "mcp-router"
        )
    }

    private static func token(expiresIn seconds: Double?, authorizedAgoMs: Double) -> String {
        var members = "\"access_token\":\"a\""
        if let seconds { members += ",\"expires_in\":\(seconds)" }
        let stamp = JSDate.iso8601(milliseconds: now - authorizedAgoMs)
        return "{\"tokens\":{\(members)},\"authorizedAt\":\"\(stamp)\"}"
    }

    private static func answer(
        _ path: String,
        method: String = "GET",
        body: String? = "{}",
        authorized: Bool = true,
        contentType: Bool = true,
        _ deps: inout ControlDeps
    ) async -> (status: Int, body: String) {
        var headers: [(name: String, value: String)] = []
        if contentType { headers.append((name: "content-type", value: "application/json")) }
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

    // MARK: - The inventory

    @Test("E20 — the report covers every upstream, in configuration order")
    func inventoryCoversEveryUpstream() async throws {
        var deps = try Support.makeDeps()
        deps.authExpiry = Self.monitor(
            ["p1-http": Self.token(expiresIn: 3600, authorizedAgoMs: 1_800_000)]
        )

        let answer = await Self.answer("/upstreams/auth-expiry", &deps)
        #expect(answer.status == 200)
        #expect(answer.body.contains(#""count":2"#))
        let stdio = try #require(answer.body.range(of: #""server":"p1-stdio""#))
        let http = try #require(answer.body.range(of: #""server":"p1-http""#))
        #expect(stdio.lowerBound < http.lowerBound, "configuration order, not dictionary order")
        #expect(answer.body.contains(#""state":"not-applicable""#))
        #expect(answer.body.contains(#""state":"expiring""#))
        #expect(answer.body.contains(#""warnWithinMs":86400000"#))
    }

    @Test("E21 — a token with no declared lifetime reports `unknown` and says what is missing")
    func unknownIsOnTheWireAsUnknown() async throws {
        var deps = try Support.makeDeps()
        deps.authExpiry = Self.monitor(
            ["p1-http": Self.token(expiresIn: nil, authorizedAgoMs: 1000)]
        )

        let answer = await Self.answer("/upstreams/auth-expiry", &deps)
        #expect(answer.status == 200)
        #expect(answer.body.contains(#""state":"unknown""#))
        #expect(answer.body.contains(#""unknownReason":"no-lifetime-declared""#))
        // Absent rather than null. A caller reading `expiresAt: null` beside an unknown state is
        // one step from treating both as "fine"; there is nothing here to round.
        #expect(answer.body.contains("expiresAt") == false)
        #expect(answer.body.contains(#""state":"valid""#) == false)
    }

    @Test("E22 — a refused configured value is reported with its scope rather than clamped")
    func refusalsReachTheWire() async throws {
        // Resolved from the file's own text rather than handed in as a literal, and that is the
        // difference between an assertion about JSON shape and one about behaviour: an earlier
        // draft injected the refusal, so a `readGlobal` that CLAMPED instead of refusing left this
        // test green. `planning/test-campaign/bin/arm-r26-auth-expiry.py`'s `clamp` arm is what
        // found that, and it is why this reads the configuration.
        let resolved = try AuthExpiryPolicy.readGlobal(
            JSONParser.parse(#"{"warnWithinMs": 500}"#)
        )
        var deps = try Support.makeDeps()
        deps.authExpiry = Self.monitor([:], policy: resolved.policy, refusals: resolved.refusals)

        let answer = await Self.answer("/upstreams/auth-expiry", &deps)
        #expect(answer.body.contains(#""key":"warnWithinMs""#))
        #expect(answer.body.contains(#""scope":"global""#))
        #expect(answer.body.contains(#""value":500"#))
        // And the policy actually in force is the default, not the number that was refused.
        #expect(answer.body.contains(#""warnWithinMs":86400000"#))
    }

    // MARK: - Claiming

    @Test("E23 — the notify route hands over the notice, with the words and the command")
    func noticesCarryTheirCopy() async throws {
        var deps = try Support.makeDeps()
        deps.authExpiry = Self.monitor(
            ["p1-http": Self.token(expiresIn: 3600, authorizedAgoMs: 7_200_000)]
        )

        let answer = await Self.answer(
            "/upstreams/auth-expiry/notify", method: "POST", &deps
        )
        #expect(answer.status == 200)
        #expect(answer.body.contains(#""count":1"#))
        #expect(answer.body.contains(#""kind":"expired""#))
        #expect(answer.body.contains(#""command":"mcp-router auth p1-http""#))
    }

    @Test("E24 — reading the report does not consume the notice; claiming it does")
    func theGetDoesNotAdvanceTheThrottle() async throws {
        var deps = try Support.makeDeps()
        deps.authExpiry = Self.monitor(
            ["p1-http": Self.token(expiresIn: 3600, authorizedAgoMs: 7_200_000)]
        )

        _ = await Self.answer("/upstreams/auth-expiry", &deps)
        _ = await Self.answer("/upstreams/auth-expiry", &deps)
        let first = await Self.answer("/upstreams/auth-expiry/notify", method: "POST", &deps)
        #expect(first.body.contains(#""count":1"#), "two reads must not have spent the notice")

        let second = await Self.answer("/upstreams/auth-expiry/notify", method: "POST", &deps)
        #expect(second.body.contains(#""count":0"#), "and the claim must actually spend it")
    }

    // MARK: - The refusals

    @Test("E25 — with no monitor both routes name the missing capability")
    func absentMonitorIsA503() async throws {
        var deps = try Support.makeDeps()
        deps.authExpiry = nil

        let inventory = await Self.answer("/upstreams/auth-expiry", &deps)
        #expect(inventory.status == 503)
        #expect(inventory.body.contains("no auth expiry monitor"))
        let notify = await Self.answer("/upstreams/auth-expiry/notify", method: "POST", &deps)
        #expect(notify.status == 503)
        #expect(notify.body.contains("no auth expiry monitor"))
    }

    @Test("E26 — the method, the token, the content type, and the paths that are not these")
    func theWireRefusals() async throws {
        var deps = try Support.makeDeps()
        deps.authExpiry = Self.monitor([:])

        #expect(await Self.answer("/upstreams/auth-expiry", method: "POST", &deps).status == 405)
        #expect(await Self.answer("/upstreams/auth-expiry/notify", &deps).status == 405)
        let untokened = await Self.answer(
            "/upstreams/auth-expiry/notify", method: "POST", authorized: false, &deps
        )
        #expect(untokened.status == 401)
        let untyped = await Self.answer(
            "/upstreams/auth-expiry/notify", method: "POST", contentType: false, &deps
        )
        #expect(untyped.status == 415)
        // A prefix collision is not claimed, so a typo is a 404 from `/mcp` rather than a 405 that
        // reads as "the method is wrong".
        #expect(await Self.answer("/upstreams/auth-expiryx", &deps).status != 405)
        #expect(await Self.answer("/upstreams/auth-expiry/notifyx", &deps).status != 405)
    }
}
