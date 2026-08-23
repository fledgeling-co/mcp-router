import Foundation

/// The recordings for M22's two boards.
///
/// A file of their own, following `FixtureControlAPIClient+Writes.swift`: these read from
/// `HarnessFixtures` and `InsightsFixtures` rather than from the recorded JSON, because both
/// routes are Swift-only surface the TypeScript reference answers 404 — a file under
/// `Control/Fixtures` would be replayed against that reference by `parity-fixture.sh` and would
/// fail a gate that is working correctly.
public extension FixtureControlAPIClient {
    func harnesses() async throws(ControlAPIError) -> HarnessesResponse {
        try guardFailure()
        if scenario == .loading { try await Self.forever() }
        switch scenario {
        // Nothing on this Mac looks like an agent CLI. A real answer rather than a failure, and
        // the board's own empty state rather than an error.
        case .empty: return HarnessFixtures.response([])
        // The mock's error frame for this board is a config that would not parse, which is a
        // *partial* read: the other five harnesses were read normally and are still shown.
        case .partial: return HarnessFixtures.response(HarnessFixtures.partiallyUnreadable)
        default: return HarnessFixtures.response(HarnessFixtures.populated)
        }
    }

    func insights() async throws(ControlAPIError) -> InsightsResponse {
        try guardFailure()
        if scenario == .loading { try await Self.forever() }
        // `thin` rather than a zeroed `populated`: the difference is `logHorizon`, and that nil is
        // the whole of "not enough history yet". A response full of zeros would draw a flat chart
        // and imply a quiet day.
        return scenario == .empty ? InsightsFixtures.thin : InsightsFixtures.populated
    }
}
