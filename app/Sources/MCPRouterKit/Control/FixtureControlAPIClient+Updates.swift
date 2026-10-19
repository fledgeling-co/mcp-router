import Foundation

/// The update check's fixture answers, for the Skills board's offers and their changelog.
///
/// Split out of `FixtureControlAPIClient.swift` for file length. Like the writes, the answer does not branch
/// on the
/// scenario beyond the failure and empty cases, because the populated answer is the one the board is drawn
/// from.
public extension FixtureControlAPIClient {
    func extensionUpdates() async throws(ControlAPIError) -> ExtensionUpdatesResponse {
        try guardFailure()
        if scenario == .loading { try await Self.forever() }
        if scenario == .empty { return ExtensionUpdatesResponse() }
        return ExtensionUpdatesResponse(entries: SkillFixtures.updateEntries)
    }
}
