#if os(macOS)
    import Foundation
    import MCPRouterKit

    /// The instant the captured pairing code was issued at, read from the recording the sheet tests
    /// decode.
    ///
    /// The sheet tests pin their clock here, so the code the recording carries is inside its window
    /// when they read it. This was a typed constant, and a re-record moved the recording out from
    /// under it: every pairing suite went red on a correct capture.
    enum RecordedPairingClock {
        static let issuedAt: Date = {
            guard
                let data = try? FixtureControlAPIClient.fixtureData("pairing-code"),
                let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let text = body["issuedAt"] as? String,
                let date = ISO8601DateFormatter().date(from: text)
            else { preconditionFailure("pairing-code.json carries no issuedAt") }
            return date
        }()
    }
#endif
