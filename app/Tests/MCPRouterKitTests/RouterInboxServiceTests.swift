import Foundation
import Testing
@testable import MCPRouterKit

@Suite("The router inbox client") struct RouterInboxServiceTests {
    private func client(_ stub: HTTPStub) -> LiveControlAPIClient {
        LiveControlAPIClient(
            baseURL: stub.baseURL,
            session: URLSession(configuration: .ephemeral),
            store: InMemoryTokenStore("inbox-test-token"),
            tokenFile: RouterTokenFile(url: URL(fileURLWithPath: "/nonexistent/control.token"))
        )
    }

    @Test func readsPartialAndBoundIdentity() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on(
            "GET",
            "/inbox",
            .json(
                200,
                #"""
                {"items":[{"id":"io.example/atlas","deviceName":"Phone",
                "queuedAt":"2026-10-20T09:00:00Z","state":"waiting",
                "resolved":null,"reviewDigest":"digest"}],"pairedDeviceNames":["Phone"]}
                """#
            )
        )
        stub.on(
            "GET",
            "/pairing/state",
            .json(
                200,
                #"""
                {"listener":{"enabled":true,"port":7333,"host":"test.local",
                "fingerprint":"SHA256:observed"}}
                """#
            )
        )
        let service = RouterInboxService(client: client(stub))
        #expect(service.availability() == .noEndpoint)
        let snapshot = try await service.snapshot()
        #expect(snapshot.items.count == 1)
        #expect(snapshot.items.first?.isPartial == true)
        #expect(snapshot.pairedDeviceName == "Phone")
        #expect(snapshot.items.first?.reviewDigest == "digest")
        #expect(service.availability().endpoint?.host == "test.local")
        #expect(stub.requests
            .allSatisfy { $0.lowercased().contains("authorization: bearer inbox-test-token") })
        let item = try #require(snapshot.items.first)
        await #expect(throws: ControlAPIError.self) { try await service.accept(item) }
        #expect(stub.requests.count == 2)
    }

    @Test func failureIsNeverAnEmptyInbox() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on("GET", "/inbox", .json(500, #"{"error":"unreadable"}"#))
        let service = RouterInboxService(client: client(stub))
        await #expect(throws: InboxServiceError.self) { _ = try await service.snapshot() }
        #expect(service.availability() == .noEndpoint)
    }

    @Test func declinedItemsRestoreThroughEscapedRoute() async throws {
        let stub = try HTTPStub()
        defer { stub.stop() }
        stub.on(
            "POST",
            "/inbox/io.example%2Fatlas/decline",
            .json(200, #"{"id":"io.example/atlas","state":"declined"}"#)
        )
        stub.on(
            "POST",
            "/inbox/io.example%2Fatlas/restore",
            .json(200, #"{"id":"io.example/atlas","state":"waiting"}"#)
        )
        let api = client(stub)
        try await api.decideInbox(id: "io.example/atlas", action: "decline", reviewDigest: nil)
        try await api.decideInbox(id: "io.example/atlas", action: "restore", reviewDigest: nil)
        #expect(stub.requests.count == 2)
        #expect(stub.requests.allSatisfy { $0.contains("/inbox/io.example%2Fatlas/") })
    }
}
