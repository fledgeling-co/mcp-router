import Foundation
import Testing
@testable import MCPRouterKit

@Suite("M6 — the inbox envelope, and what a phone may not say")
struct InboxEnvelopeTests {
    static func json(
        t: String = InboxEnvelope.discriminator,
        v: Int? = 1,
        id: String? = "q-1",
        entry: String? = "smithery:deepwiki",
        name: String? = "DeepWiki",
        queued: String? = "2026-08-15T09:41:00Z",
        device: String? = "Luke's iPhone"
    ) -> String {
        var object: [String: Any] = ["t": t]
        if let v { object["v"] = v }
        if let id { object["id"] = id }
        if let entry { object["entry"] = entry }
        if let name { object["name"] = name }
        if let queued { object["queued"] = queued }
        if let device { object["device"] = device }
        let data = try? JSONSerialization.data(withJSONObject: object)
        return data.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
    }

    @Test("a well-formed envelope decodes to its five facts")
    func decodesTheHappyPath() throws {
        let envelope = try InboxEnvelope.decode(Self.json())
        #expect(envelope.version == 1)
        #expect(envelope.id == "q-1")
        #expect(envelope.entryID == "smithery:deepwiki")
        #expect(envelope.displayName == "DeepWiki")
        #expect(envelope.deviceName == "Luke's iPhone")
        #expect(envelope.queuedAt == ISO8601Instant.parse("2026-08-15T09:41:00Z"))
    }

    /// The tolerant instant parser matters here for the same reason it did on the pairing payload:
    /// a JavaScript `toISOString()` writes fractional seconds, and the strict option rejects them.
    @Test("a fractional-second instant is accepted")
    func fractionalSecondsParse() throws {
        let envelope = try InboxEnvelope.decode(Self.json(queued: "2026-08-15T09:41:00.000Z"))
        #expect(envelope.queuedAt == ISO8601Instant.parse("2026-08-15T09:41:00Z"))
    }

    @Test("something that is not ours is refused as not ours")
    func foreignPayload() {
        #expect(throws: InboxEnvelopeError.notAQueueItem) {
            try InboxEnvelope.decode(Self.json(t: "mcp-router-pair"))
        }
        #expect(throws: InboxEnvelopeError.notAQueueItem) {
            try InboxEnvelope.decode("not json at all")
        }
    }

    @Test("an unknown version is a named outcome, never a silent read")
    func unknownVersion() {
        #expect(throws: InboxEnvelopeError.unsupportedVersion(found: 7)) {
            try InboxEnvelope.decode(Self.json(v: 7))
        }
        #expect(throws: InboxEnvelopeError.malformedPayload(detail: "no version")) {
            try InboxEnvelope.decode(Self.json(v: nil))
        }
    }

    /// **The failure mode `SWIFT_PRACTICES.md` §2 forbids, asserted field by field.**
    ///
    /// The TypeScript router shipped a reader that found a missing key and loaded zero servers with
    /// no error — a silent empty result that looks exactly like "you have nothing". The same shape
    /// here would be an item that resolves to nothing and renders as a permanently unactionable row
    /// nobody could explain. Every field is required, and the one that fails is named.
    @Test("a missing or empty field fails loudly, and says which field")
    func missingFieldsAreNamed() {
        #expect(throws: InboxEnvelopeError.malformedPayload(detail: "missing entry")) {
            try InboxEnvelope.decode(Self.json(entry: nil))
        }
        #expect(throws: InboxEnvelopeError.malformedPayload(detail: "missing id")) {
            try InboxEnvelope.decode(Self.json(id: nil))
        }
        #expect(throws: InboxEnvelopeError.malformedPayload(detail: "empty entry")) {
            try InboxEnvelope.decode(Self.json(entry: ""))
        }
        #expect(throws: InboxEnvelopeError.malformedPayload(detail: "empty id")) {
            try InboxEnvelope.decode(Self.json(id: ""))
        }
        #expect(throws: InboxEnvelopeError.malformedPayload(detail: "empty name")) {
            try InboxEnvelope.decode(Self.json(name: ""))
        }
        #expect(throws: InboxEnvelopeError.malformedPayload(detail: "empty device")) {
            try InboxEnvelope.decode(Self.json(device: ""))
        }
        #expect(
            throws: InboxEnvelopeError.malformedPayload(detail: "queued is not an ISO-8601 instant")
        ) {
            try InboxEnvelope.decode(Self.json(queued: "yesterday"))
        }
    }

    /// **A11, at the type level: there is no field in which a phone can describe a capability.**
    ///
    /// The security property this whole surface rests on is that the Mac reads what a thing does
    /// rather than believing what the sender said about it. An envelope carrying extra keys decodes
    /// fine — a stricter decoder would break on a future version's additions — and contributes
    /// nothing, because the type has nowhere to put them.
    @Test("extra keys a sender invents are carried nowhere")
    func extraKeysContributeNothing() throws {
        var object: [String: Any] = [
            "t": InboxEnvelope.discriminator, "v": 1, "id": "q-1", "entry": "e",
            "name": "N", "queued": "2026-08-15T09:41:00Z", "device": "D"
        ]
        object["capability"] = "read-only"
        object["command"] = "rm -rf /"
        object["trusted"] = true
        let data = try JSONSerialization.data(withJSONObject: object)
        let text = try #require(String(bytes: data, encoding: .utf8))
        let envelope = try InboxEnvelope.decode(text)

        // The decoded value has five facts and no opinion. Reflected over, so a field added later
        // without a decision fails here rather than reaching a surface.
        let mirrored = Set(Mirror(reflecting: envelope).children.compactMap(\.label))
        #expect(mirrored == ["version", "id", "entryID", "displayName", "queuedAt", "deviceName"])
    }
}

@Suite("M6 — items, acceptability, and the fixture's coverage")
struct InboxItemTests {
    static let envelope = InboxEnvelope(
        version: 1,
        id: "q-1",
        entryID: "authored:local-notes",
        displayName: "What the phone called it",
        queuedAt: Date(timeIntervalSince1970: 1_755_000_000),
        deviceName: "Luke's iPhone"
    )

    /// **`resolved == nil` IS the Partial state**, and this is what makes "cannot be accepted"
    /// structural rather than a rule a view has to remember.
    @Test("an unresolved item cannot obtain permission to install")
    func unresolvedIsNotAcceptable() {
        let item = InboxItem(envelope: Self.envelope, resolved: nil)
        #expect(item.isPartial)
        #expect(AcceptableInboxItem(item) == nil)
    }

    @Test("a resolved item can, and carries the entry the Mac read")
    func resolvedIsAcceptable() throws {
        let found = try FixtureInboxService.resolve(entryID: "authored:local-notes")
        let entry = try #require(found)
        let item = InboxItem(envelope: Self.envelope, resolved: entry)
        let acceptable = try #require(AcceptableInboxItem(item))
        #expect(!item.isPartial)
        #expect(acceptable.entry.id == "authored:local-notes")
    }

    /// The name shown is the Mac's reading where it has one, and the phone's only where it does not.
    /// A resolved item showing the phone's name would let a sender relabel something.
    @Test("a resolved item shows what the Mac read, never what the phone said")
    func titlePrefersTheResolvedEntry() throws {
        let found = try FixtureInboxService.resolve(entryID: "authored:local-notes")
        let entry = try #require(found)
        #expect(InboxItem(envelope: Self.envelope, resolved: entry).title == entry.displayName)
        #expect(InboxItem(envelope: Self.envelope, resolved: entry).title != Self.envelope.displayName)
        // And falls back only when there is nothing else to say which thing it is.
        #expect(
            InboxItem(envelope: Self.envelope, resolved: nil).title == Self.envelope.displayName
        )
    }

    /// Every scenario produces a distinct **observable**, so a state added later cannot ship with no
    /// way to see it — the same coverage guard `PairingOutcomeCoverageTests` applies on the phone.
    ///
    /// **The earlier assertion was arithmetic.** It appended one string per iteration and then
    /// checked `seen.count == allCases.count - 1`, which is true for any loop over that collection
    /// whatever the snapshots contain — the property the test is named for was never asserted. And
    /// the strings it built were prefixed with the scenario's own `rawValue`, so even a set-based
    /// check would have been distinct by construction.
    ///
    /// The fingerprint below carries **only what a user could observe** — the rows, the device, the
    /// availability, the code's lifetime — and never the scenario name. That immediately found a
    /// real gap: `.paired` and `.expiring` were byte-identical, so the near-expiry state existed in
    /// the enum and nowhere else. `pairingLifetime()` is what now separates them.
    @Test("every fixture scenario is reachable and observably distinct")
    func scenarioCoverage() async throws {
        var seen: [String] = []
        for scenario in FixtureInboxService.Scenario.allCases where scenario != .loading {
            let service = FixtureInboxService(scenario)
            if scenario == .failed {
                await #expect(throws: InboxServiceError.self) { try await service.snapshot() }
                seen.append("threw")
                continue
            }
            let snapshot = try await service.snapshot()
            let ids = snapshot.items.map(\.id).joined(separator: ",")
            let device = snapshot.pairedDeviceName ?? "-"
            let reach = "\(service.availability())|\(service.pairingLifetime())"
            seen.append("\(ids)|\(device)|\(reach)")
        }
        // `.loading` is excluded deliberately: it never returns, which is the state. Sleeping on it
        // here would hang the suite rather than assert anything.
        #expect(
            Set(seen).count == seen.count,
            "two scenarios are observably identical, so one of them is a state nobody can reach: \(seen)"
        )
        #expect(seen.count == FixtureInboxService.Scenario.allCases.count - 1)
    }

    /// The split the Partial state depends on: an entry that is genuinely absent resolves to `nil`,
    /// and only a missing or malformed registry *file* throws.
    ///
    /// Collapsing the two is what `SWIFT_PRACTICES.md` §2 forbids, and the collapse was live here —
    /// `try?` returning `nil` meant a renamed fixture would have made every row say "This entry
    /// could not be read", with the acceptance script's Partial assertions passing on it.
    @Test("an absent entry is nil, and the registry files themselves are readable")
    func absentEntryIsNotAnUnreadableRegistry() throws {
        let absent = try FixtureInboxService.resolve(entryID: "smithery:withdrawn-entry")
        let present = try FixtureInboxService.resolve(entryID: FixtureInboxService.authoredStdioID)
        #expect(absent == nil)
        #expect(present != nil)
    }

    /// The other half, and the one the tests above cannot reach: a registry file that is **not
    /// there** is a named failure rather than an empty read.
    ///
    /// Both bundled resources exist, so nothing reachable through `resolve` takes this branch — a
    /// mutation returning `[]` in place of the throw survived the whole suite until this test
    /// existed. An empty read here would resolve every item to `nil` and render the entire queue as
    /// Partial, which reads as "the registry does not have these" when the truth is "this app could
    /// not open its own registry" (`SWIFT_PRACTICES.md` §2).
    @Test("a registry file that is not there fails loudly, never emptily")
    func missingRegistryFileIsNamed() {
        #expect(throws: InboxServiceError.self) {
            try FixtureInboxService.entries(in: "no-such-registry-fixture")
        }
    }

    /// The default scenario is what ships, not the richest one.
    @Test("the none scenario has no endpoint, no device and nothing queued")
    func noneIsWhatShips() async throws {
        let service = FixtureInboxService(.none)
        #expect(service.availability() == .noEndpoint)
        let snapshot = try await service.snapshot()
        #expect(snapshot.items.isEmpty)
        #expect(snapshot.pairedDeviceName == nil)
    }

    /// The Release implementation is a real one, not a fixture configured empty.
    @Test("the no-transport service is honest in both directions")
    func noTransportService() async throws {
        let service = NoTransportInboxService()
        #expect(service.availability() == .noEndpoint)
        let snapshot = try await service.snapshot()
        #expect(snapshot.items.isEmpty)
        #expect(snapshot.pairedDeviceName == nil)
    }

    /// The partial scenario contains exactly one item the Mac could not resolve, which is what the
    /// acceptance run drives to reach the Partial cell.
    @Test("the partial scenario yields one unresolved item and one resolved")
    func partialScenarioShape() async throws {
        let snapshot = try await FixtureInboxService(.partial).snapshot()
        #expect(snapshot.items.count == 2)
        #expect(snapshot.items.filter(\.isPartial).count == 1)
        #expect(snapshot.items.filter { !$0.isPartial }.count == 1)
    }
}
