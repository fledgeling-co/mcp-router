import Foundation
import Testing
@testable import MCPRouterKit

/// B3 — the Mac reads the router's pairing bodies, and refuses one that is not a pairing body.
///
/// The bodies under `Control/Fixtures/pairing-*.json` were captured from the running router by
/// `scripts/capture-control-fixtures.sh`, which drives the pairing routes over HTTP, not written by
/// hand. A body a Swift test invented would agree with the decoder by construction; a captured one
/// can only agree with it if the two really match.
@Suite("B3 — the router's pairing bodies decode to what the sheet shows")
struct PairingCodeWireTests {
    /// The instant `pairing-code.json` was issued at. Every clock in the pairing tests is pinned here,
    /// so the code the fixture carries is inside its window when the sheet reads it.
    static let captured = Date(timeIntervalSince1970: 1_792_375_158)

    @Test("the captured issue body decodes, with the window the router chose")
    func issueBodyDecodes() async throws {
        let issued = try await FixtureControlAPIClient(.populated).issuePairingCode()
        #expect(issued.issuedAt == Self.captured)
        #expect(issued.expiresAt == Self.captured.addingTimeInterval(MacPairing.lifetime))
        #expect(issued.code.canonical.count == PairingCode.length)
    }

    @Test("the captured state body names the code the issue body carried")
    func stateBodyNamesTheLiveCode() async throws {
        let client = FixtureControlAPIClient(.populated)
        let issued = try await client.issuePairingCode()
        let live = try #require(try await client.pairingState())
        #expect(live == issued)
    }

    @Test("the captured revoke body reports that a code was revoked")
    func revokeBodyDecodes() async throws {
        #expect(try await FixtureControlAPIClient(.populated).revokePairingCode() == true)
    }

    @Test("a state body with no live code decodes to nothing rather than to a code")
    func emptyStateDecodes() throws {
        let decoded = try JSONDecoder().decode(PairingStateWire.self, from: Data(#"{"code":null}"#.utf8))
        #expect(decoded.code == nil)
    }

    /// A code the Mac cannot type is not a code the router issued, whatever the transport said. The
    /// lower-case form is refused too: the router writes upper case, so a lenient reader would be
    /// accepting a body the router did not send.
    @Test("a body whose code is not a canonical pairing code is refused, not coerced", arguments: [
        "ABCD234",
        "ABCD23456",
        "ABCD234U",
        "abcd2345"
    ])
    func refusesAMalformedCode(code: String) {
        let body = Data(
            #"{"code":"\#(code)","issuedAt":"2026-10-19T10:00:00Z","expiresAt":"2026-10-19T10:05:00Z"}"#
                .utf8
        )
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PairingCodeWire.self, from: body)
        }
    }

    @Test("a body whose expiry is not an ISO-8601 instant is refused")
    func refusesAMalformedInstant() {
        let body = Data(#"{"code":"ABCD2345","issuedAt":"yesterday","expiresAt":"2026-10-19T10:05:00Z"}"#
            .utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PairingCodeWire.self, from: body)
        }
    }

    /// The live client reaches the three routes with the bearer token, and reads what comes back.
    /// The stub answers with the same shape the captured bodies have, which the fixture test above
    /// pins against the real route.
    @Test("the live client POSTs, GETs and DELETEs the pairing routes with the token")
    func liveClientReachesTheRoutes() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        let issuedAt = "2026-10-19T01:59:18Z"
        let expiresAt = "2026-10-19T02:04:18Z"
        let body = #"{"code":"ABCD2345","issuedAt":"\#(issuedAt)","expiresAt":"\#(expiresAt)"}"#
        stub.on("POST", "/pairing/codes", .json(201, body))
        stub.on("GET", "/pairing/state", .json(200, #"{"code":\#(body)}"#))
        stub.on("DELETE", "/pairing/codes", .json(200, #"{"revoked":true}"#))
        let subject = LiveControlAPIClient(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            store: InMemoryTokenStore("test-token"),
            tokenFile: RouterTokenFile(url: URL(fileURLWithPath: "/nonexistent/control.token")),
            log: ControlLog()
        )

        let issued = try await subject.issuePairingCode()
        #expect(issued.issuedAt == Self.captured)
        #expect(try await subject.pairingState() == issued)
        #expect(try await subject.revokePairingCode())

        let heads = stub.requests
        #expect(heads.contains { $0.contains("POST /pairing/codes") })
        #expect(heads.contains { $0.contains("GET /pairing/state") })
        #expect(heads.contains { $0.contains("DELETE /pairing/codes") })
        #expect(heads.allSatisfy { $0.contains("Authorization: Bearer test-token") })
    }
}
