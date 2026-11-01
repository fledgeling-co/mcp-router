import Foundation

extension LiveControlAPIClient: InboxControlAPI {
    public func inbox() async throws(ControlAPIError) -> RouterInboxResponse {
        try await send(.get, "inbox", as: RouterInboxResponse.self)
    }

    public func inboxEndpoint() async throws(ControlAPIError) -> PairingEndpoint? {
        let state = try await send(.get, "pairing/state", as: InboxPairingEndpointWire.self)
        guard state.listener.enabled, let host = state.listener.host, let port = state.listener.port,
              let fingerprint = state.listener.fingerprint else { return nil }
        return PairingEndpoint(host: host, port: port, fingerprint: fingerprint)
    }

    public func decideInbox(id: String, action: String, reviewDigest: String?) async throws(ControlAPIError) {
        guard ["accept", "decline", "restore"].contains(action) else {
            throw .malformedResponse(detail: "unknown inbox decision")
        }
        let body: Data
        do {
            body = try JSONSerialization
                .data(withJSONObject: reviewDigest.map { ["reviewDigest": $0] } ?? [:])
        } catch { throw .malformedResponse(detail: "inbox decision could not be encoded") }
        let result = try await send(
            .post,
            "inbox/\(segment(id))/\(action)",
            body: body,
            as: InboxDecisionWire.self
        )
        let expected = action == "accept" ? "accepted" : action == "decline" ? "declined" : "waiting"
        guard result.id == id, result.state == expected else {
            throw .malformedResponse(detail: "the inbox decision acknowledgement did not match the request")
        }
    }
}

private struct InboxDecisionWire: Decodable { let id: String; let state: String }
private struct InboxPairingEndpointWire: Decodable {
    struct Listener: Decodable {
        let enabled: Bool; let host: String?; let port: Int?; let fingerprint: String?
    }

    let listener: Listener
}
