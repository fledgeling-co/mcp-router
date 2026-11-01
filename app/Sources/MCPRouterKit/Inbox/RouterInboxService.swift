import Foundation
import os

public struct RouterInboxRow: Codable, Sendable {
    public let id: String
    public let deviceName: String
    public let queuedAt: String
    public let state: String
    public let resolved: RegistryEntry?
    public let reviewDigest: String
}

public struct RouterInboxResponse: Codable, Sendable {
    public let items: [RouterInboxRow]
    public let pairedDeviceNames: [String]?
}

public protocol InboxControlAPI: Sendable {
    func inbox() async throws(ControlAPIError) -> RouterInboxResponse
    func inboxEndpoint() async throws(ControlAPIError) -> PairingEndpoint?
    func decideInbox(id: String, action: String, reviewDigest: String?) async throws(ControlAPIError)
}

public protocol InboxDeciding: InboxService {
    func accept(_ item: InboxItem) async throws(ControlAPIError)
    func decline(_ item: InboxItem) async throws(ControlAPIError)
    func restore(_ item: InboxItem) async throws(ControlAPIError)
}

/// Reads the token-gated router snapshot. A failed read never becomes an empty inbox.
public final class RouterInboxService: InboxDeciding, Sendable {
    private let client: any ControlAPIClient
    private let endpoint = OSAllocatedUnfairLock<PairingEndpoint?>(initialState: nil)

    public init(client: any ControlAPIClient) {
        self.client = client
    }

    private func api() throws(ControlAPIError) -> any InboxControlAPI {
        guard let api = client as? any InboxControlAPI else {
            throw .server(status: 503, message: "This client cannot read the router inbox")
        }
        return api
    }

    public func snapshot() async throws(InboxServiceError) -> InboxSnapshot {
        do throws(ControlAPIError) {
            let api = try api()
            let result = try await api.inbox()
            let address = try await api.inboxEndpoint()
            endpoint.withLock { $0 = address }
            guard result.items
                .allSatisfy({
                    ["waiting", "accepted", "declined"].contains($0.state) && !$0.id.isEmpty && !$0
                        .reviewDigest
                        .isEmpty })
            else {
                throw ControlAPIError.malformedResponse(detail: "invalid inbox row")
            }
            var waiting: [InboxItem] = []
            for row in result.items where row.state == "waiting" {
                guard let queuedAt = ISO8601Instant.parse(row.queuedAt) else {
                    throw ControlAPIError.malformedResponse(detail: "inbox queuedAt is not an instant")
                }
                waiting.append(InboxItem(
                    envelope: InboxEnvelope(
                        version: 1,
                        id: row.id,
                        entryID: row.id,
                        displayName: row.resolved?.displayName ?? row
                            .id,
                        queuedAt: queuedAt,
                        deviceName: row.deviceName
                    ),
                    resolved: row.resolved,
                    reviewDigest: row.reviewDigest
                ))
            }
            return InboxSnapshot(items: waiting, pairedDeviceName: result.pairedDeviceNames?.first)
        } catch {
            endpoint.withLock { $0 = nil }
            throw .registryUnreadable(error)
        }
    }

    public func availability() -> PairingAvailability {
        endpoint.withLock { $0.map(PairingAvailability.available) ?? .noEndpoint }
    }

    public func accept(_ item: InboxItem) async throws(ControlAPIError) {
        guard item.resolved != nil, let digest = item.reviewDigest else {
            throw .server(status: 422, message: "This item has no resolved review")
        }
        try await api().decideInbox(id: item.id, action: "accept", reviewDigest: digest)
    }

    public func decline(_ item: InboxItem) async throws(ControlAPIError) {
        try await api().decideInbox(id: item.id, action: "decline", reviewDigest: nil)
    }

    public func restore(_ item: InboxItem) async throws(ControlAPIError) {
        try await api().decideInbox(id: item.id, action: "restore", reviewDigest: nil)
    }
}
