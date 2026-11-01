import Foundation

/// The three pairing calls, against the router's `/pairing/*` routes.
///
/// Loopback like every other call on this client, and token-gated on every method, GET included:
/// `/pairing/state` names the code a phone would type, so a read of it is as privileged as a write.
public extension LiveControlAPIClient {
    func issuePairingCode() async throws(ControlAPIError) -> IssuedPairingCode {
        try await send(
            .post,
            "pairing/codes",
            body: Data("{}".utf8),
            as: PairingCodeWire.self
        ).issued
    }

    func pairingState() async throws(ControlAPIError) -> PairingState {
        try await send(.get, "pairing/state", as: PairingStateWire.self).state
    }

    func revokePairingCode() async throws(ControlAPIError) -> Bool {
        try await send(.delete, "pairing/codes", as: PairingRevokeWire.self).revoked
    }

    func revokePairedPhone(id: String) async throws(ControlAPIError) -> String {
        let result = try await send(.delete, "pairing/phones/\(segment(id))", as: PairingPhoneRevokeWire.self)
        guard result.revoked == id else {
            throw .malformedResponse(detail: "the router revoked a different phone")
        }
        return result.revoked
    }
}
