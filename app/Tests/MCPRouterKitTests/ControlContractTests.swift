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
            placard: .set(Placard(reason: "under review"))
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
    /// TypeScript `PATCH /servers/:name` reads `projects`, `warm`, `idleMs`, `placard` and `disabled`, and
    /// silently ignores anything else. A field here that the router does not read produces a call
    /// that returns 200 and changes nothing, which is worse than a failure.
    @Test("a fully-populated patch encodes exactly the keys the router reads")
    func patchKeysAreExactlyThePermittedOnes() throws {
        let data = try JSONEncoder().encode(
            ServerPatch(
                projects: [], warm: false, idleMs: 0, placard: .set(Placard(reason: "x")),
                disabled: false
            )
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
    ///
    /// Every representative shape goes through it, not one. A single-input test is defeated by a
    /// bypass conditioned on a value it never supplies — `if warm == false { return … }` sails past
    /// a test that only ever passes `warm: true` — so the empty patch, each field alone, and the
    /// fully-populated patch are all pushed through the same door.
    ///
    /// What this does **not** prove: that no future edit can bypass the check. Nothing expressible
    /// here prevents someone adding an early `return` above the validation. What it does is remove
    /// the cheap version of that mistake, where a bypass hides in an input nobody tests.
    /// The router branches on `'placard' in b`, so the wire has three states and the type must
    /// too: absent leaves the mark, `null` removes it, an object sets it. The out-of-family critic
    /// found that `Placard?` could only ever express two of them — a nil optional is omitted by
    /// the encoder, so "clear the mark" produced the same bytes as "leave it alone" and the
    /// capability this type documents did nothing at all.
    @Test("a placard can be set, cleared, or left alone, and the three are different on the wire")
    func placardHasThreeWireStates() throws {
        func keys(_ patch: ServerPatch) throws -> [String: Any] {
            try #require(
                try JSONSerialization.jsonObject(with: patch.encodedBody()) as? [String: Any]
            )
        }

        let untouched = try keys(ServerPatch(warm: true))
        #expect(untouched["placard"] == nil, "an absent placard must not reach the wire at all")

        let cleared = try keys(ServerPatch(placard: .clear))
        #expect(cleared.keys.contains("placard"), "clearing has to send the key")
        #expect(cleared["placard"] is NSNull, "clearing has to send an explicit null, not an object")

        let set = try keys(ServerPatch(placard: .set(Placard(reason: "under review"))))
        let object = try #require(set["placard"] as? [String: Any])
        #expect(object["reason"] as? String == "under review")
    }

    @Test("a patch round-trips through Codable with its placard state intact")
    func placardSurvivesARoundTrip() throws {
        for patch in [
            ServerPatch(warm: true),
            ServerPatch(placard: .clear),
            ServerPatch(placard: .set(Placard(reason: "under review", substitute: "other")))
        ] {
            let data = try JSONEncoder().encode(patch)
            let back = try JSONDecoder().decode(ServerPatch.self, from: data)
            #expect(back == patch, "a patch changed meaning on the way through: \(patch)")
        }
    }

    @Test("encodedBody emits only permitted keys, for every shape a patch can take")
    func encodedBodyIsAllowlisted() throws {
        let shapes: [ServerPatch] = [
            ServerPatch(),
            ServerPatch(projects: ["/tmp/a"]),
            ServerPatch(warm: true),
            ServerPatch(warm: false),
            ServerPatch(idleMs: 0),
            ServerPatch(placard: .set(Placard(reason: "under review"))),
            ServerPatch(placard: .clear),
            ServerPatch(projects: [], warm: false, idleMs: 30000, placard: .set(Placard(reason: "x")))
        ]

        for patch in shapes {
            let data = try patch.encodedBody()
            let object = try #require(
                try JSONSerialization.jsonObject(with: data) as? [String: Any],
                "encodedBody did not produce a JSON object for \(patch)"
            )
            let keys = Set(object.keys)
            #expect(
                keys.isDisjoint(with: ServerPatch.forbiddenWireKeys),
                "encodedBody put a forbidden key on the wire for \(patch): \(keys.sorted())"
            )
            #expect(
                keys.isSubset(of: ServerPatch.permittedWireKeys),
                "encodedBody emitted an unpermitted key for \(patch): \(keys.sorted())"
            )
        }
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

    /// The widened protocol adds exactly one type that carries a command line, and this is what
    /// keeps that from being a way around the guarantee above.
    ///
    /// `NewServer` and `ServerPatch` are deliberately unrelated types rather than one being a
    /// superset of the other. Declaring a server is an explicit act with its own surface; editing
    /// one is not allowed to quietly become that act by gaining a field. Because they share no
    /// shape, no future edit can widen a patch into an installer — there is nothing to widen.
    @Test("adding a server is the only shape that carries a command, and it is not a patch")
    func newServerIsTheSoleCommandCarrier() throws {
        // It genuinely carries one — otherwise adding a server could not work at all.
        let new = NewServer(name: "x", command: "/bin/echo", args: ["hi"], env: ["K": "v"])
        let object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(new)) as? [String: Any]
        )
        #expect(object["command"] != nil)
        #expect(object["args"] != nil)
        #expect(object["env"] != nil)

        let patchLabels = Set(Mirror(reflecting: ServerPatch()).children.compactMap(\.label))
        let newLabels = Set(Mirror(reflecting: new).children.compactMap(\.label))
        #expect(
            !newLabels.isDisjoint(with: ServerPatch.forbiddenWireKeys),
            "this test is pointless if NewServer stopped carrying a command line"
        )
        #expect(
            patchLabels.isDisjoint(with: ServerPatch.forbiddenWireKeys),
            "a command-carrying field appeared on the patch type"
        )
        // The two shapes do overlap, and legitimately: `projects` and `warm` are settable when a
        // server is declared and editable afterwards, so the router reads them on both routes. What
        // must never overlap is a field a patch is not allowed to send — anything shared has to be
        // something the patch allowlist already permits.
        let shared = patchLabels.intersection(newLabels)
        #expect(
            shared.isSubset(of: ServerPatch.permittedWireKeys),
            """
            the two request shapes share a field the patch allowlist does not permit: \
            \(shared.subtracting(ServerPatch.permittedWireKeys).sorted())
            """
        )
    }

    /// The wider surface, checked for the hole the widening could have opened: the client now has
    /// fourteen operations, and none of them may offer a second route to a command line.
    @Test("the patch path stays allowlisted now that the protocol is wider")
    func patchStaysAllowlistedAcrossTheWiderSurface() throws {
        let encoded = try ServerPatch(projects: ["/tmp/a"], warm: true).encodedBody()
        let keys = try Set(
            (JSONSerialization.jsonObject(with: encoded) as? [String: Any] ?? [:]).keys
        )
        #expect(keys.isSubset(of: ServerPatch.permittedWireKeys))
        #expect(keys.isDisjoint(with: ServerPatch.forbiddenWireKeys))
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
             "idleSec":0,"tools":0,"toolNames":[],"projects":[],"warm":false,"disabled":false,
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
