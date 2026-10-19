import Foundation

/// The fixture client's pairing calls, decoded from bodies captured off the TypeScript route.
///
/// The recordings come from the running router, so a decode that passes here passes against the bytes
/// the router sends. Each body is one capture's answer: the code in it is the one that capture
/// minted, and its window is the one the router chose. The sheet's clock in the tests is pinned to
/// the instant that capture issued the code, so the window reads as live.
public extension FixtureControlAPIClient {
    func issuePairingCode() async throws(ControlAPIError) -> IssuedPairingCode {
        try guardFailure()
        return try decode("pairing-code", as: PairingCodeWire.self).issued
    }

    func pairingState() async throws(ControlAPIError) -> PairingState {
        try guardFailure()
        return try decode("pairing-state", as: PairingStateWire.self).state
    }

    func revokePairingCode() async throws(ControlAPIError) -> Bool {
        try guardFailure()
        return try decode("pairing-revoke", as: PairingRevokeWire.self).revoked
    }
}
