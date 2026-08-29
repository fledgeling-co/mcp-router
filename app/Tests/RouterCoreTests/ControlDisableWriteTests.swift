import Foundation
import Testing
@testable import RouterCore

/// M29's strike, read back through a channel the handler does not own.
///
/// `PATCH /servers/:name {"disabled": …}` is the one write the whole *Disable a server* feature
/// performs. Everything M29 built stands on it: the sheet's destructive button sends it, the row's
/// `Enable` action reverses it, and the band, the dot, the sweeps and the tool union all read the
/// state it is supposed to leave behind.
///
/// **The suite did not measure it.** Deleting the `disabled` arm from
/// ``ControlHandler/applyPatchFields(to:supplied:)`` outright — the whole
/// `if let disabled = supplied("disabled")` block — left all **688 RouterCore tests in 106 suites
/// passing**, measured on this branch. No test here sent a PATCH body containing `disabled` to the
/// handler at all; the three router-side suites that mention the field (``DisabledSweepTests``,
/// ``ControlReindexDisabledTests``, ``ConfigParityTests``) each start from a fixture that is
/// *already* switched off, so they exercise every reader of the switch and no writer of it.
///
/// **What did cover it, and what that cover cannot say.** `scripts/acceptance/control-differential.sh`
/// drives `PATCH {"disabled":true}`, `{"disabled":false}` and `{"disabled":"yes"}` through
/// `compare_mutating`, which diffs the status, the response body *and* `servers.json` against the
/// running reference. That is real cover and this file does not replace it. But it is an
/// **equivalence**: it says the two implementations agree, not that either is right — two ports
/// that both stopped writing the member produce identical configs and the lane stays green. It
/// needs a built binary and a live node reference, so it is not in `make all`; and it compares
/// bytes, so it cannot ask the question the user actually has, which is whether a session is still
/// served the server's tools. Oracle line 6 of `planning/specs/spec-M29.md` is the clause, and
/// until this file it had no witness inside the suite.
///
/// This file is a fourth member of ``WireGuaranteeTests``' family and is separate from it for that
/// suite's own stated reason: a fixture pins a point, and the recorded corpus simply never PATCHes
/// this key. It is kept out of that file because that file is already at the length limit.
///
/// **The read-back is deliberately not the response body.** `patch` answers with `Describe.row` of
/// its own reloaded upstream, so asserting on the response asks the handler whether it thinks it
/// wrote — the same channel that struck. Every assertion below reads the **user's `servers.json`
/// off the filesystem** and re-parses it through ``ServerParser``, then asks ``ToolUnion/isServed(_:cwd:)``,
/// which is the predicate that decides what a session is actually served.
@Suite("M29 — the switch reaches the config, not only the response")
struct ControlDisableWriteTests {
    /// Two servers, neither switched off. `on` is the control in every test here: a handler that
    /// wrote `disabled` to the whole file, or to the wrong entry, passes each `off` assertion.
    private static let bothLive = #"""
    {"mcpServers":{
      "off":{"command":"/bin/echo","args":["a"]},
      "on":{"command":"/bin/echo","args":["b"]}
    }}
    """#

    private static let offAlreadyDisabled = #"""
    {"mcpServers":{
      "off":{"command":"/bin/echo","args":["a"],"disabled":true},
      "on":{"command":"/bin/echo","args":["b"]}
    }}
    """#

    // MARK: - Harness

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

    private static func temporaryConfig(_ json: String) throws -> (path: String, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("disable-write-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("servers.json").path
        try Data(json.utf8).write(to: URL(fileURLWithPath: path))
        return (path, directory)
    }

    /// The strike: one PATCH through the real handler against a real `servers.json`.
    ///
    /// Returns the status and the file **as re-read from disk**, never the handler's own view of
    /// what it wrote.
    /// What one PATCH left behind, across every channel this file reads.
    ///
    /// A named type rather than a tuple because the repo caps a tuple at two members, and the
    /// point of this file is that the write has to be read four different ways.
    struct Outcome {
        let status: Int
        /// The handler's own account of the write.
        let body: String
        /// The user's `servers.json`, re-read from the filesystem.
        let onDisk: String
        /// The handler's reloaded live map — `nil` when it no longer knows the server.
        let reloaded: Bool?
    }

    private static func patch(
        _ body: String, on name: String, startingFrom config: String
    ) async throws -> Outcome {
        let temporary = try Self.temporaryConfig(config)
        defer { try? FileManager.default.removeItem(at: temporary.directory) }
        var deps = try PortIdentityTests.deps(upstreams: Self.upstreams(from: config))
        deps.configPath = temporary.path
        let response = await ControlHandler(token: "t").handle(
            ControlAPIRequest(
                method: "PATCH",
                encodedPath: "/servers/\(name)",
                headers: [
                    (name: "x-mcpr-token", value: "t"),
                    (name: "content-type", value: "application/json")
                ],
                body: Data(body.utf8)
            ), &deps
        )
        let onDisk = try String(contentsOfFile: temporary.path, encoding: .utf8)
        // Oracle 6's middle clause: the handler reloads its own live map from the file it just
        // wrote. Reported separately from the two independent channels rather than instead of them.
        return Outcome(
            status: response.status,
            body: Self.bodyText(response),
            onDisk: onDisk,
            reloaded: deps.upstreams.first { $0.name.string == name }?.upstream.disabled
        )
    }

    private static func bodyText(_ response: ControlAPIResponse) -> String {
        guard case let .bytes(bytes) = response.body else { return "<stream>" }
        return String(bytes: bytes, encoding: .utf8) ?? "<not utf-8>"
    }

    /// Whether a session in `cwd` would be served this server, decided from the config text alone.
    ///
    /// Re-parsed rather than read from `deps.upstreams`: the handler reloads that map itself, so
    /// reading it would ask the handler to confirm its own write. This asks the file.
    private static func isServed(_ name: String, in configText: String) throws -> Bool {
        let parsed = try Self.upstreams(from: configText)
        let upstream = try #require(
            parsed.first { $0.name.string == name }?.upstream,
            "\(name) is not in the config at all, so the serving question is not being asked"
        )
        return ToolUnion.isServed(upstream, cwd: nil)
    }

    // MARK: - The write

    /// The arm the mutation deleted. Both halves of the read-back move, and the sibling does not.
    @Test("disabling a server writes the switch to the config and stops it being served")
    func theSwitchReachesTheConfigAndTheServingPredicate() async throws {
        // The fixture is not already in the state being asserted, which is what makes the
        // assertions below a measurement rather than a restatement of the seed.
        #expect(try Self.isServed("off", in: Self.bothLive), "the fixture is already switched off")

        let result = try await Self.patch(#"{"disabled":true}"#, on: "off", startingFrom: Self.bothLive)

        #expect(result.status == 200, "the switch was refused rather than applied")
        #expect(
            try !Self.isServed("off", in: result.onDisk),
            "the server is still served after being disabled: \(result.onDisk)"
        )
        #expect(
            result.onDisk.contains(#""disabled": true"#),
            "the switch never reached the user's config: \(result.onDisk)"
        )

        // Oracle 6's other two clauses — *reloads*, and *the response body reports
        // `disabled: true`*. Both read the handler's own account of the write, so they are stated
        // after the two independent channels above rather than in place of them.
        #expect(result.reloaded == true, "the handler did not reload its own map from the file")
        #expect(
            result.body.contains(#""disabled": true"#) || result.body.contains(#""disabled":true"#),
            "the response body does not report the switch: \(result.body)"
        )

        // The control. Every assertion above is also passed by a handler that disabled the whole
        // file, so the untouched sibling is what makes them about *this server*.
        #expect(
            try Self.isServed("on", in: result.onDisk),
            "disabling one server stopped another being served: \(result.onDisk)"
        )
    }

    /// The reverse, and the half a naive `set("disabled", value)` gets wrong.
    ///
    /// `applyPatchFields` writes the switch **shaped like `warm`**: a falsy value removes the member
    /// rather than writing `false`, so turning a server back on leaves the config as it found it.
    /// A port that assigned the value as given — the way `idleMs` is assigned two lines above —
    /// would leave `"disabled": false` behind and still be served, so `isServed` alone cannot see
    /// it. The reference is diffed against this byte for byte.
    @Test("enabling a server removes the member rather than writing false")
    func enablingRemovesTheMemberRatherThanWritingFalse() async throws {
        #expect(
            try !Self.isServed("off", in: Self.offAlreadyDisabled),
            "the fixture is not switched off, so there is nothing to switch back on"
        )

        let result = try await Self.patch(
            #"{"disabled":false}"#, on: "off", startingFrom: Self.offAlreadyDisabled
        )

        #expect(result.status == 200)
        #expect(
            try Self.isServed("off", in: result.onDisk),
            "the server is still withheld after being switched back on: \(result.onDisk)"
        )
        #expect(
            !result.onDisk.contains("disabled"),
            "enabling left a disabled member in the config: \(result.onDisk)"
        )
    }

    /// The key-presence gate, which is a different mechanism from the two arms above.
    ///
    /// `applyPatchFields` reaches the switch only when the body carries the key. Without that gate
    /// every PATCH would read a missing `disabled` as falsy and write the member away — so the row's
    /// *Keep warm* toggle would silently switch a disabled server back on, and the only evidence
    /// would be tools reappearing in a session nobody touched.
    @Test("a PATCH that does not name the switch leaves it exactly as it was")
    func anUnrelatedPatchDoesNotTouchTheSwitch() async throws {
        let result = try await Self.patch(
            #"{"warm":true}"#, on: "off", startingFrom: Self.offAlreadyDisabled
        )

        #expect(result.status == 200)
        #expect(
            try !Self.isServed("off", in: result.onDisk),
            "a warm-only PATCH switched a disabled server back on: \(result.onDisk)"
        )
        #expect(
            result.onDisk.contains(#""disabled": true"#),
            "a warm-only PATCH removed the switch from the config: \(result.onDisk)"
        )
        // The sibling field did land, so this measures "the switch was left alone" rather than
        // "the PATCH did nothing at all".
        #expect(
            result.onDisk.contains(#""warm": true"#),
            "the allowed sibling was not applied, so the request may simply have failed"
        )
    }
}
