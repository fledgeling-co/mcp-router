import Foundation
import Testing
@testable import MCPRouterKit

@Suite("Confirmed phone control API")
struct PairedDeviceWireTests {
    static func body(_ phones: String? = "[]") -> String {
        let extra = phones.map { ",\"confirmedPhones\":\($0)" } ?? ""
        return """
        {"code":null,"awaitingAck":[],
        "listener":{"enabled":false,"port":null,"advertising":false}\(extra)}
        """
    }

    static let row = #"{"phoneId":"phone-1","phoneName":"Test phone","pairedAt":"2026-11-01T10:00:00Z"}"#

    @Test("live client reads device metadata, authenticates and deletes the named phone")
    func liveBoundary() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on("GET", "/pairing/state", .json(200, Self.body("[\(Self.row)]")))
        stub.on("DELETE", "/pairing/phones/phone-1", .json(200, #"{"revoked":"phone-1"}"#))
        let client = LiveControlAPIClient(
            baseURL: stub.baseURL,
            session: .init(configuration: .ephemeral),
            store: InMemoryTokenStore("synthetic-device-test-token"),
            tokenFile: RouterTokenFile(url: URL(fileURLWithPath: "/nonexistent/device-fixture/control.token"))
        )
        let state = try await client.pairingState()
        #expect(state.confirmedPhones?.first?.phoneName == "Test phone")
        #expect(state.confirmedPhones?.first?.phoneId == "phone-1")
        #expect(state.listener.enabled == false)
        #expect(try await client.revokePairedPhone(id: "phone-1") == "phone-1")
        #expect(stub.requests.count == 2)
        #expect(stub.requests
            .allSatisfy { $0.lowercased().contains("authorization: bearer synthetic-device-test-token") })
    }

    @Test("legacy absence differs from an observed empty list, and duplicate identities are refused")
    func listContract() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(PairingStateWire.self, from: Data(Self.body(nil).utf8)).state
            .confirmedPhones == nil)
        #expect(try decoder.decode(PairingStateWire.self, from: Data(Self.body().utf8)).state
            .confirmedPhones == [])
        #expect(throws: DecodingError.self) {
            try decoder.decode(PairingStateWire.self, from: Data(Self.body("[\(Self.row),\(Self.row)]").utf8))
        }
        #expect(throws: DecodingError.self) {
            try decoder.decode(
                PairingStateWire.self,
                from: Data(Self
                    .body(
                        "[\(Self.row.replacingOccurrences(of: "2026-11-01T10:00:00Z", with: "invalid"))]"
                    )
                    .utf8)
            )
        }
    }

    @Test("a different revocation acknowledgement is refused and 404 is preserved")
    func refusalContract() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        let client = LiveControlAPIClient(
            baseURL: stub.baseURL,
            session: .init(configuration: .ephemeral),
            store: InMemoryTokenStore("synthetic-device-test-token"),
            tokenFile: RouterTokenFile(url: URL(fileURLWithPath: "/nonexistent/device-fixture/control.token"))
        )
        stub.on("DELETE", "/pairing/phones/phone-1", .json(200, #"{"revoked":"other-phone"}"#))
        await #expect(throws: ControlAPIError
            .malformedResponse(detail: "the router revoked a different phone"))
        {
            try await client.revokePairedPhone(id: "phone-1")
        }
        stub.on(
            "DELETE",
            "/pairing/phones/phone-1",
            .json(404, #"{"error":"no confirmed phone has that id"}"#)
        )
        await #expect(throws: ControlAPIError.server(
            status: 404,
            message: "no confirmed phone has that id"
        )) {
            try await client.revokePairedPhone(id: "phone-1")
        }
    }
}
