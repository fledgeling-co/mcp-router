import Foundation
import Testing
@testable import MCPRouterKit

@Suite("Control API contract")
struct ControlContractTests {
    /// The guardrail this whole item exists to protect: the control API must never be able to
    /// rewrite a command line.
    ///
    /// Asserted against the **encoded JSON**, not the Swift type. Reflection would only see stored
    /// properties, so a computed property or a `CodingKeys` mapping could put `command` on the wire
    /// while a `Mirror`-based test stayed green — the encoder is the thing that decides what
    /// actually gets sent, so the encoder is what gets asserted.
    @Test("an encoded ServerPatch can never carry command, args or env")
    func patchCannotRewriteACommandLine() throws {
        let patch = ServerPatch(
            projects: ["/tmp/a", "/tmp/b"],
            warm: true,
            idleMs: 30000,
            placard: Placard(reason: "under review")
        )
        let data = try JSONEncoder().encode(patch)
        let object = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
            "encoded patch was not a JSON object"
        )

        for forbidden in ServerPatch.forbiddenWireKeys {
            #expect(
                object[forbidden] == nil,
                """
                ServerPatch encoded a forbidden key '\(forbidden)' — the control API \
                must not be able to rewrite a command line
                """
            )
        }
        #expect(Set(object.keys).isSubset(of: ServerPatch.permittedWireKeys))
    }

    /// The shape is checked against the router's own handler rather than against itself: the
    /// TypeScript `PATCH /servers/:name` reads `projects`, `warm`, `idleMs` and `placard`, and
    /// silently ignores anything else. A field here that the router does not read produces a call
    /// that returns 200 and changes nothing, which is worse than a failure.
    @Test("a fully-populated patch encodes exactly the keys the router reads")
    func patchKeysAreExactlyThePermittedOnes() throws {
        let data = try JSONEncoder().encode(
            ServerPatch(projects: [], warm: false, idleMs: 0, placard: Placard(reason: "x"))
        )
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ServerPatch.permittedWireKeys)
    }

    /// The stored-property check that the encoded-JSON check cannot make.
    ///
    /// Adding `public var command: String?` and leaving it nil is invisible to every assertion
    /// above — the synthesised encoder omits nil optionals, so the key set is unchanged and the
    /// suite stays green until the day a caller assigns it. Reflection sees the property whether
    /// or not it currently has a value, which is exactly the gap the encoder cannot cover.
    @Test("no stored property is named after a forbidden wire key")
    func noForbiddenStoredProperty() {
        let labels = Mirror(reflecting: ServerPatch()).children.compactMap(\.label)
        for label in labels {
            #expect(
                !ServerPatch.forbiddenWireKeys.contains(label),
                "ServerPatch has a stored property '\(label)' — nil today, on the wire tomorrow"
            )
        }
        #expect(
            Set(labels) == ServerPatch.permittedWireKeys,
            "stored properties and permitted wire keys have diverged: \(labels.sorted())"
        )
    }

    /// `encodedBody()` is the path the app uses, so it is the path that gets tested. The assertions
    /// above encode with a locally-constructed encoder, which proves nothing about a caller that
    /// brings its own — this one exercises the real seam.
    @Test("encodedBody produces only permitted keys")
    func encodedBodyIsAllowlisted() throws {
        let data = try ServerPatch(projects: ["/tmp/a"], warm: true).encodedBody()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys).isSubset(of: ServerPatch.permittedWireKeys))
        #expect(object["projects"] != nil)
        #expect(object["warm"] != nil)
    }

    /// The allowlist has to be able to *fail*, or it is decoration.
    ///
    /// There is no way to make `ServerPatch` itself emit a forbidden key without editing it, which
    /// is the point of the design — so the check is exercised on an equivalent encode-and-inspect
    /// of a shape that does carry one, proving the comparison rejects what it claims to reject
    /// rather than merely never being handed anything bad.
    @Test("the wire-key check rejects a body carrying a forbidden key")
    func allowlistRejectsForbiddenKeys() throws {
        struct Rogue: Encodable { var command: String }
        let data = try JSONEncoder().encode(Rogue(command: "/bin/sh"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let keys = Set(object.keys)

        #expect(!keys.isDisjoint(with: ServerPatch.forbiddenWireKeys))
        #expect(!keys.subtracting(ServerPatch.permittedWireKeys).isEmpty)
    }

    /// A shape the decoder does not recognise must fail loudly. The TypeScript router shipped a
    /// bug where a flat `servers.json` loaded zero servers with no error at all, and the Swift
    /// side must not reintroduce a silent-empty path.
    @Test("an unrecognised transport fails decoding instead of defaulting")
    func unknownTransportFailsLoudly() {
        let json = Data(
            #"{"name":"x","transport":"carrier-pigeon","state":"idle"}"#.utf8
        )
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(MCPServer.self, from: json)
        }
    }

    @Test("an unrecognised state fails decoding instead of defaulting")
    func unknownStateFailsLoudly() {
        let json = Data(#"{"name":"x","transport":"stdio","state":"vibing"}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(MCPServer.self, from: json)
        }
    }

    @Test("the offline case is distinguishable from every other failure")
    func routerNotRunningIsItsOwnCase() {
        #expect(ControlAPIError.routerNotRunning != ControlAPIError.transport(detail: "refused"))
        #expect(ControlAPIError.routerNotRunning.userFacingDescription.contains("isn't running"))
    }

    @Test("every error states what to do, and none of them blames the user")
    func errorCopyIsActionable() {
        let all: [ControlAPIError] = [
            .routerNotRunning, .unauthorized,
            .malformedResponse(detail: "x"), .server(status: 500, message: "y"),
            .transport(detail: "z")
        ]
        for error in all {
            let copy = error.userFacingDescription
            #expect(!copy.isEmpty)
            #expect(!copy.contains("!"), "error copy should not emote: \(copy)")
        }
    }

    @Test("a server nobody called is never-used, which cleanup reads")
    func neverUsedTracksCallCount() throws {
        let json = Data(
            """
            {"name":"x","transport":"stdio","state":"idle","inFlight":0,"callsServed":0,
             "idleSec":0,"tools":0,"toolNames":[],"projects":[],"warm":false,
             "auth":{"supported":false,"authorized":true},
             "usage":{"calls":0,"errors":0,"projects":{}}}
            """.utf8
        )
        let server = try JSONDecoder().decode(MCPServer.self, from: json)
        #expect(server.neverUsed)
        #expect(!server.needsAttention)
        #expect(server.isStdio)
    }
}

@Suite("Formatting")
struct RelativeTimeTests {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    private func ago(_ seconds: TimeInterval) -> String {
        shortAgo(now.addingTimeInterval(-seconds), from: now)
    }

    @Test("the boundaries between units are exact")
    func boundaries() {
        #expect(ago(0) == "now")
        #expect(ago(4) == "now")
        #expect(ago(5) == "5s")
        #expect(ago(59) == "59s")
        #expect(ago(60) == "1m")
        #expect(ago(3599) == "59m")
        #expect(ago(3600) == "1h")
        #expect(ago(86399) == "23h")
        #expect(ago(86400) == "1d")
        #expect(ago(86400 * 29) == "29d")
        #expect(ago(86400 * 30) == "1mo")
    }

    @Test("a future timestamp reads as now rather than a negative age")
    func futureClampsToNow() {
        #expect(shortAgo(now.addingTimeInterval(120), from: now) == "now")
    }

    @Test("a project label prefers the name and falls back to the directory")
    func projectLabelling() {
        #expect(projectLabel(cwd: "/Users/x/Dev/thing", project: "Thing") == "Thing")
        #expect(projectLabel(cwd: "/Users/x/Dev/thing", project: nil) == "thing")
        #expect(projectLabel(cwd: "/Users/x/Dev/thing", project: "") == "thing")
        #expect(projectLabel(cwd: nil, project: nil) == "—")
        #expect(projectLabel(cwd: "", project: nil) == "—")
    }

    @Test("timestamps parse with and without fractional seconds, and junk returns nil")
    func timestampParsing() {
        #expect("2026-08-13T12:00:00Z".asControlAPIDate != nil)
        #expect("2026-08-13T12:00:00.123Z".asControlAPIDate != nil)
        #expect("not a date".asControlAPIDate == nil)
    }
}
