import Foundation
import Testing
@testable import RouterCore

/// Three guarantees the clause table names and the corpus did not constrain.
///
/// Every test here was written because `scripts/parity/mutation-gate.sh` broke the behaviour and
/// the whole suite stayed green — mutations R10, R12 and R13. That is the distinction the gate
/// exists to draw: each of these clauses had a passing *fixture*, and a fixture pins a point rather
/// than a contract. The recorded responses simply never contain a null `cwd`, never carry an empty
/// `Bearer`, and never PATCH a `command`, so nothing recorded could have caught a port that got
/// them wrong.
///
/// B40 is the one that matters most. "`command`, `args` and `env` are not writable through PATCH"
/// is one of this product's standing constraints, and until this file existed, a port that
/// **rejected** such a PATCH with a 400 passed every test in the suite while diverging from the
/// reference, which returns 200 and applies the allowed sibling fields.
@Suite("Wire guarantees the fixtures cannot reach")
struct WireGuaranteeTests {
    // MARK: - Shared construction

    private static func upstreams(
        from json: String
    ) throws -> [(name: JSString, upstream: UpstreamConfig)] {
        let parsed = try JSONParser.parse(json)
        let entries = parsed.member("mcpServers")?.asObjectMembers ?? []
        var out: [(name: JSString, upstream: UpstreamConfig)] = []
        for entry in entries {
            guard case let .upstream(upstream) = ServerParser.parse(
                name: entry.key.string, raw: entry.value
            ) else { continue }
            out.append((entry.key, upstream))
        }
        return out
    }

    /// A `servers.json` in its own directory. Returns the path and the directory to remove, rather
    /// than taking a closure, so the caller can stay `async` — the handler is.
    private static func temporaryConfig(_ json: String) throws -> (path: String, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wire-guarantee-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("servers.json").path
        try Data(json.utf8).write(to: URL(fileURLWithPath: path))
        return (path, directory)
    }

    private static func bodyText(_ response: ControlAPIResponse) -> String {
        guard case let .bytes(bytes) = response.body else { return "<stream>" }
        return String(bytes: bytes, encoding: .utf8) ?? "<not utf-8>"
    }

    // MARK: - B2 / S3 — null is a value, undefined is an absence

    /// Mutation R10: `if let raw = …member("cwd"), raw != .null` — omitting a null `cwd` as though
    /// it were undefined. The suite stayed green, because `server-stdio.json` has **no** `cwd` at
    /// all and so exercises only the absent half of B2's tri-state.
    ///
    /// `JSON.stringify` omits a member whose value is `undefined` and emits `"k":null` for one whose
    /// value is `null`. A Swift `Optional` collapses the two, which is why B2 is a clause and why
    /// the raw config is consulted rather than the parsed `String?`.
    @Test("an explicit null cwd is emitted as null, not omitted")
    func nullCwdIsEmitted() async throws {
        let json = #"{"mcpServers":{"s1":{"command":"/bin/echo","cwd":null}}}"#
        var deps = try PortIdentityTests.deps(upstreams: Self.upstreams(from: json))
        let response = await ControlHandler(token: "t").handle(
            ControlAPIRequest(method: "GET", encodedPath: "/servers/s1"), &deps
        )
        #expect(response.status == 200)
        let text = Self.bodyText(response)
        #expect(
            text.contains(#""cwd":null"#),
            "an explicit null cwd was not emitted as null — got \(text)"
        )
    }

    /// The other two thirds of B2's tri-state, so this file cannot be satisfied by an implementation
    /// that simply emits `"cwd":null` unconditionally.
    @Test(
        "cwd's tri-state, one case each",
        arguments: [
            (#"{"command":"/bin/echo"}"#, false, false),
            (#"{"command":"/bin/echo","cwd":null}"#, true, false),
            (#"{"command":"/bin/echo","cwd":"/tmp"}"#, false, true)
        ]
    )
    func cwdTriState(_ entry: String, _ expectNull: Bool, _ expectValue: Bool) async throws {
        let json = #"{"mcpServers":{"s1":"# + entry + "}}"
        var deps = try PortIdentityTests.deps(upstreams: Self.upstreams(from: json))
        let response = await ControlHandler(token: "t").handle(
            ControlAPIRequest(method: "GET", encodedPath: "/servers/s1"), &deps
        )
        let text = Self.bodyText(response)
        #expect(text.contains(#""cwd":null"#) == expectNull, "null case wrong: \(text)")
        #expect(text.contains(#""cwd":"/tmp""#) == expectValue, "value case wrong: \(text)")
        // Absent means the key does not appear at all — not that it appears holding something falsy.
        if !expectNull, !expectValue {
            #expect(!text.contains(#""cwd""#), "an absent cwd emitted a key: \(text)")
        }
    }

    // MARK: - B17 — an exact `Bearer ` prefix shadows x-mcpr-token

    /// Mutation R13: `hasPrefix("Bearer "), header.count > 7` — letting an empty bearer fall through
    /// to `x-mcpr-token`. The suite stayed green because no recorded request carries both headers.
    ///
    /// The reference reads the bearer **if and only if** the prefix is present, and compares that
    /// value. It never tries the second header as a fallback, so a caller presenting a wrong or
    /// empty `Authorization` cannot rescue itself with a correct `x-mcpr-token`.
    @Test(
        "a present Bearer shadows x-mcpr-token even when empty or wrong",
        arguments: [
            ("Bearer ", "the bearer is empty"),
            ("Bearer wrong", "the bearer is wrong"),
            ("Bearer T", "the bearer differs only in case")
        ]
    )
    func bearerShadows(_ authorization: String, _ why: String) async throws {
        var deps = try PortIdentityTests.deps(
            upstreams: Self.upstreams(from: #"{"mcpServers":{"s1":{"command":"/bin/echo"}}}"#)
        )
        let response = await ControlHandler(token: "t").handle(
            ControlAPIRequest(
                method: "DELETE",
                encodedPath: "/servers/s1",
                headers: [
                    (name: "authorization", value: authorization),
                    // Correct, and it must not save the request.
                    (name: "x-mcpr-token", value: "t")
                ]
            ), &deps
        )
        #expect(response.status == 401, "\(why), and x-mcpr-token rescued it")
        #expect(response.handled, "a 401 is a handled reply, never a fall-through (B20, S8)")
    }

    /// The boundary that keeps the clause honest: `x-mcpr-token` **is** consulted when the prefix is
    /// absent, so the test above is asserting shadowing rather than a blanket refusal. `Bearer` with
    /// no trailing space is not the prefix.
    @Test(
        "x-mcpr-token is consulted when the exact prefix is absent",
        arguments: ["", "Bearer", "bearer t", "Token t"]
    )
    func tokenHeaderUsedWithoutPrefix(_ authorization: String) async throws {
        var deps = try PortIdentityTests.deps(
            upstreams: Self.upstreams(from: #"{"mcpServers":{"s1":{"command":"/bin/echo"}}}"#)
        )
        var headers = [(name: "x-mcpr-token", value: "t")]
        if !authorization.isEmpty {
            headers.append((name: "authorization", value: authorization))
        }
        let response = await ControlHandler(token: "t").handle(
            ControlAPIRequest(
                method: "DELETE", encodedPath: "/servers/ghost", headers: headers
            ), &deps
        )
        // 404, not 401: the token passed, and the route lookup is what refused (B22).
        #expect(response.status == 404, "x-mcpr-token was ignored for authorization=\(authorization)")
    }

    // MARK: - B40 — command, args and env are IGNORED, not rejected

    /// Mutation R12: refuse a PATCH carrying `command`, `args` or `env` with a 400. The suite stayed
    /// green, so this product's headline control-API guarantee had no behavioural evidence at all.
    ///
    /// B40 is stated as an **equivalence**, and it is asserted here as one: the response bytes, the
    /// status, and the config file on disk must all be identical to the same request with those
    /// three members deleted. Asserting merely that the command line is unchanged would be passed by
    /// a handler that rejected the request outright and wrote nothing — which is exactly the wrong
    /// implementation, since the reference returns 200 and applies the allowed siblings.
    @Test("a PATCH carrying command, args and env equals the same PATCH without them")
    func commandLineMembersAreIgnoredNotRejected() async throws {
        let start = #"{"mcpServers":{"s1":{"command":"/bin/echo","args":["a"],"env":{"K":"v"}}}}"#

        func run(_ body: String) async throws -> (response: ControlAPIResponse, onDisk: String) {
            let temporary = try Self.temporaryConfig(start)
            defer { try? FileManager.default.removeItem(at: temporary.directory) }
            var deps = try PortIdentityTests.deps(upstreams: Self.upstreams(from: start))
            deps.configPath = temporary.path
            let response = await ControlHandler(token: "t").handle(
                ControlAPIRequest(
                    method: "PATCH",
                    encodedPath: "/servers/s1",
                    headers: [
                        (name: "x-mcpr-token", value: "t"),
                        (name: "content-type", value: "application/json")
                    ],
                    body: Data(body.utf8)
                ), &deps
            )
            let onDisk = (try? String(contentsOfFile: temporary.path, encoding: .utf8))
                ?? "<unreadable>"
            return (response, onDisk)
        }

        let carrying = try await run(
            #"{"command":"/bin/rm","args":["-rf","/"],"env":{"K":"stolen"},"warm":true}"#
        )
        let without = try await run(#"{"warm":true}"#)

        #expect(carrying.response.status == 200, "the PATCH was rejected rather than ignored")
        #expect(
            carrying.response.status == without.response.status,
            "statuses differ: \(carrying.response.status) vs \(without.response.status)"
        )
        #expect(
            Self.bodyText(carrying.response) == Self.bodyText(without.response),
            """
            response bodies differ:
              carrying: \(Self.bodyText(carrying.response))
              without:  \(Self.bodyText(without.response))
            """
        )
        #expect(
            carrying.onDisk == without.onDisk,
            "the config on disk differs: \(carrying.onDisk) vs \(without.onDisk)"
        )
        // Stated separately from the equivalence, because the equivalence alone would hold if BOTH
        // requests had rewritten the command line the same wrong way.
        #expect(
            carrying.onDisk.contains(#""command": "/bin/echo""#),
            "the command line moved: \(carrying.onDisk)"
        )
        #expect(!carrying.onDisk.contains("/bin/rm"), "a PATCH wrote a command: \(carrying.onDisk)")
        #expect(!carrying.onDisk.contains("stolen"), "a PATCH wrote an env value: \(carrying.onDisk)")
        #expect(carrying.onDisk.contains(#""warm": true"#), "the allowed sibling was not applied")
    }
}
