import Foundation
import Testing
@testable import MCPRouterKit

/// Every recorded response decodes, keeps every field it was given, and covers the variants — not
/// one happy path per endpoint.
///
/// The reason this suite is large rather than one representative test: a decode breaks per *shape*,
/// and the shapes that break are the conditional ones. A router that answers a healthy `GET
/// /servers` correctly can still answer the refused add, the held change or the in-flight
/// authorization in a form the client drops on the floor, and only a fixture per variant sees it.
@Suite("Recorded fixtures")
struct ControlFixtureTests {
    /// One recording, and the type it is supposed to decode as.
    ///
    /// The type is captured as a single closure that decodes *and* re-encodes, so the decode test
    /// and the round-trip test cannot drift apart into disagreeing about which type a fixture is.
    struct FixtureCase: Sendable {
        let name: String
        let roundTrip: @Sendable (Data) throws -> Data
    }

    private static func expect(_ name: String, _ type: (some Codable).Type) -> FixtureCase {
        FixtureCase(name: name) { data in
            try JSONEncoder().encode(JSONDecoder().decode(type, from: data))
        }
    }

    /// Every fixture in the bundle, with the type it is supposed to decode as.
    ///
    /// Kept as one table so that adding a recording without a decode test is impossible: the
    /// completeness test below fails when the directory holds a file this list does not mention.
    static let expected: [FixtureCase] = [
        expect("servers", ServersResponse.self),
        expect("servers-pending-auth", ServersResponse.self),
        expect("server-stdio", MCPServer.self),
        expect("server-http", MCPServer.self),
        expect("server-tools", MCPServer.self),
        expect("server-pending-change", MCPServer.self),
        expect("patch-response", MCPServer.self),
        expect("usage", UsageResponse.self),
        expect("usage-summary", UsageSummary.self),
        expect("usage-reset", UsageReset.self),
        expect("changes-none", HeldChanges.self),
        expect("changes-pending", HeldChanges.self),
        expect("registry-search", RegistrySearchResponse.self),
        expect("added", AddedServer.self),
        expect("removed", RemovedServer.self),
        expect("reindex-held", ReindexResult.self),
        expect("reindex-failure", ReindexResult.self),
        expect("approve", ApprovalResult.self),
        expect("auth-start", AuthorizationStart.self),
        expect("signout", SignedOut.self),
        expect("add-refused", RouterErrorBody.self),
        expect("approve-conflict", RouterErrorBody.self),
        expect("unauthorized", RouterErrorBody.self)
    ]

    // MARK: - A14 / A17: every recording still decodes

    @Test("every recorded response decodes as the type the client expects")
    func everyFixtureDecodes() throws {
        for entry in Self.expected {
            let data = try FixtureControlAPIClient.fixtureData(entry.name)
            #expect(throws: Never.self, "\(entry.name).json no longer decodes") {
                _ = try entry.roundTrip(data)
            }
        }
    }

    /// A recording nobody decodes is a recording that proves nothing. This fails when one is added
    /// to the directory without being added to the table above.
    @Test("no recording exists that nothing decodes")
    func everyFixtureIsClaimed() throws {
        let directory = try #require(
            Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures")
                ?? Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: nil)
        )
        let onDisk = Set(directory.map { $0.deletingPathExtension().lastPathComponent })
        let claimed = Set(Self.expected.map(\.name))
        #expect(
            onDisk == claimed,
            """
            unclaimed recordings: \(onDisk.subtracting(claimed).sorted()); \
            missing files: \(claimed.subtracting(onDisk).sorted())
            """
        )
    }

    // MARK: - A24: fidelity, in both directions

    /// Every key the router sent has a field, and every field the model encodes was sent.
    ///
    /// One round-trip on one fixture proves nothing about the others, so this runs over all of
    /// them. Both directions are checked because they catch opposite mistakes: a wire key with no
    /// field is data silently dropped, and a field with no wire key is a value invented here.
    @Test("every fixture round-trips without losing or inventing a field")
    func fixturesRoundTripWithKeyParity() throws {
        for entry in Self.expected {
            let data = try FixtureControlAPIClient.fixtureData(entry.name)
            let reEncoded = try entry.roundTrip(data)

            let original = try JSONSerialization.jsonObject(with: data)
            let returned = try JSONSerialization.jsonObject(with: reEncoded)

            let sent = Self.keyPaths(original)
            let kept = Self.keyPaths(returned)

            #expect(
                sent.subtracting(kept).isEmpty,
                "\(entry.name): the router sent keys the model drops: \(sent.subtracting(kept).sorted())"
            )
            #expect(
                kept.subtracting(sent).isEmpty,
                """
                \(entry.name): the model encodes keys the router never sent: \
                \(kept.subtracting(sent).sorted())
                """
            )
        }
    }

    /// Every key path in a decoded JSON value, so two shapes can be compared regardless of order.
    /// Array elements collapse onto one path — an array of ten servers is one shape, not ten.
    static func keyPaths(_ value: Any, prefix: String = "") -> Set<String> {
        if let object = value as? [String: Any] {
            var out: Set<String> = []
            for (key, child) in object {
                let path = prefix.isEmpty ? key : "\(prefix).\(key)"
                out.insert(path)
                out.formUnion(keyPaths(child, prefix: path))
            }
            return out
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<String>()) { $0.formUnion(keyPaths($1, prefix: "\(prefix)[]")) }
        }
        return []
    }

    // MARK: - A15: the variants, not one happy path

    @Test("the two transports are recorded as the different shapes they are")
    func stdioAndHTTPAreBothRecorded() throws {
        let stdio = try FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)
        let http = try FixtureControlAPIClient.decodeFixture("server-http", as: MCPServer.self)

        #expect(stdio.transport == .stdio)
        #expect(stdio.command != nil, "a stdio server is recorded with its command")
        #expect(stdio.url == nil)

        #expect(http.transport == .http)
        #expect(http.url != nil, "an http server is recorded with its url")
        #expect(http.command == nil)
    }

    @Test("a refused add keeps the router's advice about how to proceed")
    func refusedAddCarriesItsHint() throws {
        let body = try FixtureControlAPIClient.decodeFixture("add-refused", as: RouterErrorBody.self)
        #expect(body.error.contains("ENOENT"))
        let hint = try #require(
            body.hint,
            "the hint is the whole difference between a dead end and a next step"
        )
        #expect(hint.contains("force=1"))
    }

    @Test("a re-index failure is structured, not just a status")
    func reindexFailureIsStructured() throws {
        let failure = try FixtureControlAPIClient.decodeFixture("reindex-failure", as: ReindexResult.self)
        #expect(failure.error != nil, "the failure has to name itself, to be shown against its row")
        #expect(failure.tools == 0)

        let ok = try FixtureControlAPIClient.decodeFixture("reindex-held", as: ReindexResult.self)
        #expect(ok.error == nil)
    }

    @Test("a held change is recorded present as well as absent")
    func heldChangesBothWays() throws {
        let none = try FixtureControlAPIClient.decodeFixture("changes-none", as: HeldChanges.self)
        #expect(!none.pending)
        #expect(none.changes.isEmpty)

        let pending = try FixtureControlAPIClient.decodeFixture("changes-pending", as: HeldChanges.self)
        #expect(pending.pending)
        #expect(pending.seenAt != nil)

        let kinds = Set(pending.changes.map(\.kind))
        #expect(
            kinds == [.added, .removed, .changed],
            "the recording should exercise every kind of change, saw \(kinds.map(\.rawValue).sorted())"
        )
    }

    /// The reason the quarantine surface exists at all: a description that reads differently to a
    /// model than to a person. A recording with no invisible codepoint in it leaves that field —
    /// and every surface that renders it — untested.
    @Test("an invisible codepoint in a rewritten description is named, not silently kept")
    func invisibleCodepointsSurvive() throws {
        let pending = try FixtureControlAPIClient.decodeFixture("changes-pending", as: HeldChanges.self)
        let changed = try #require(pending.changes.first { $0.kind == .changed })
        let invisible = try #require(changed.invisible, "the rewritten description hides a codepoint")
        #expect(invisible.contains("U+200B"))
        #expect(changed.before?.description != changed.after?.description)
    }

    // MARK: - A22: the in-flight authorization

    @Test("an authorization already in flight is recorded, and modelled rather than dropped")
    func pendingAuthorizationIsModelled() throws {
        let quiet = try FixtureControlAPIClient.decodeFixture("servers", as: ServersResponse.self)
        #expect(quiet.pendingAuth == nil, "the ordinary case carries none")

        let busy = try FixtureControlAPIClient.decodeFixture("servers-pending-auth", as: ServersResponse.self)
        let flow = try #require(busy.pendingAuth, "the recording was captured mid-flow and must keep it")
        #expect(flow.server == "fixture-oauth")
        #expect(flow.url.contains("code_challenge"), "the URL the app opens, as the router recorded it")
    }

    @Test("the approval response is a count, not a server")
    func approvalIsItsOwnShape() throws {
        let approval = try FixtureControlAPIClient.decodeFixture("approve", as: ApprovalResult.self)
        #expect(approval.server == "fixture-tools")
        #expect(approval.approved > 0, "the router reports how many tools it promoted")
    }

    @Test("a call record survives the wire with everything the router logged about it")
    func callRecordsAreRecorded() throws {
        let usage = try FixtureControlAPIClient.decodeFixture("usage", as: UsageResponse.self)
        let record = try #require(usage.records.first, "an empty call log agrees with any model ever written")
        #expect(!record.server.isEmpty)
        #expect(!record.tool.isEmpty)
        #expect(record.ms >= 0)
        #expect(record.pid != nil)
    }

    // MARK: - A23: closed sets stay closed

    @Test("an unrecognised change kind fails decoding instead of defaulting")
    func unknownChangeKindThrows() {
        let json = Data(#"{"server":"x","pending":true,"changes":[{"kind":"rewritten","name":"t"}]}"#.utf8)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(HeldChanges.self, from: json)
        }
    }

    @Test("an unrecognised registry source fails decoding instead of defaulting")
    func unknownRegistrySourceThrows() {
        let json = Data(
            """
            {"results":[{"id":"a","name":"a","displayName":"A","description":"d","source":"hearsay"}],
             "sources":{"official":0,"smithery":0,"merged":0},"warnings":[]}
            """.utf8
        )
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(RegistrySearchResponse.self, from: json)
        }
    }
}
