import Foundation

/// The four endpoints a router may legitimately not have, and the one rule they share.
///
/// Every other read on this client treats a non-2xx as `server(status:message:hint:)`, whose
/// headline is *the router couldn't complete that*. For these four that sentence is wrong: a 404
/// means the router on the other end does not have the feature, which is version skew rather than
/// a failure, and `malformedResponse` already carries exactly that wording.
///
/// They are in a file of their own because they are one family rather than four endpoints, and
/// because splitting on that seam is what keeps the actor body inside this repository's length cap
/// — the alternative was raising the cap, which `SWIFT_PRACTICES.md` §7 rules out for tests and
/// this repository has never done for a lint either.
public extension LiveControlAPIClient {
    func skills() async throws(ControlAPIError) -> SkillsResponse {
        try await skillsRead("skills", as: SkillsResponse.self)
    }

    func marketplaces() async throws(ControlAPIError) -> MarketplacesResponse {
        try await skillsRead("marketplaces", as: MarketplacesResponse.self)
    }

    func harnesses() async throws(ControlAPIError) -> HarnessesResponse {
        try await skillsRead("harnesses", as: HarnessesResponse.self)
    }

    func insights() async throws(ControlAPIError) -> InsightsResponse {
        try await skillsRead("insights", as: InsightsResponse.self)
    }

    /// A read whose 404 means "this router predates the feature" rather than "not found".
    ///
    /// Every other path on this client treats a non-2xx as `server(status:message:hint:)`, whose
    /// headline is "The router couldn't complete that". For these two endpoints that is the wrong
    /// sentence: the TypeScript router is the installed default and one built before M4 has no
    /// skills route at all, so 404 is the *expected* answer from an older daemon and the honest
    /// reading of it is version skew. **M22's `/harnesses` and `/insights` take the same path for
    /// a stronger version of the same reason**: the reference answers both 404 by design and
    /// always will, so a router that does not serve them is the ordinary case rather than a fault.
    /// The name is still `skillsRead` because renaming it would touch two call sites this item is
    /// not here to change. `malformedResponse` already carries exactly that wording —
    /// "The router may be newer or older than this app" — and it is the state the board is designed
    /// around. Without this mapping the board would render a copy that its own spec never allows.
    private func skillsRead<T: Decodable>(
        _ path: String,
        as type: T.Type
    ) async throws(ControlAPIError) -> T {
        do {
            return try await send(.get, path, as: type)
        } catch {
            if case let .server(status, _, _) = error, status == 404 {
                throw ControlAPIError.malformedResponse(detail: "this router has no /\(path) endpoint")
            }
            throw error
        }
    }
}
