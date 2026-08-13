import Foundation

/// The only shape the app may send to the control API's PATCH.
///
/// **`command`, `args` and `env` are absent by construction, and that is the whole point.** A
/// control API that can rewrite a command line is a control API that can run anything on the
/// machine, so the guarantee is structural rather than a validation rule someone could later
/// relax: there is no field here to set, so no code path — present or future — can populate one.
///
/// `ControlContractTests` asserts this against the *encoded JSON* rather than the Swift type,
/// because a computed property or a `CodingKeys` mapping could put one of those keys on the wire
/// without ever appearing as a stored property.
public struct ServerPatch: Codable, Hashable, Sendable {
    /// Keep the server warm rather than reaping it when idle.
    public var warm: Bool?
    /// Restrict the server to these project directories.
    public var projects: [String]?
    /// Accept the tool-description change currently held for review.
    public var acceptPendingChange: Bool?

    public init(warm: Bool? = nil, projects: [String]? = nil, acceptPendingChange: Bool? = nil) {
        self.warm = warm
        self.projects = projects
        self.acceptPendingChange = acceptPendingChange
    }

    /// The fields the control API will never accept, named so the test can assert on them and so
    /// the next person to extend this type sees the rule before adding a case.
    public static let forbiddenWireKeys: Set<String> = ["command", "args", "env"]
}
