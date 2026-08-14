import Foundation

/// The six checks MCP Router can genuinely perform against a declared server.
///
/// Every one is a pure function of a field the control API already serves — nothing here calls a
/// tool, sends a fixture or grades a reply, because no runner in this product can. That is the whole
/// honesty position of this surface, and it is enforced by the signatures: a function with only an
/// `MCPServer` to read cannot invent an observation.
///
/// **`unknown` is a first-class answer and three of these return it.** The defect this file exists to
/// avoid is reporting a confirmation for a question nobody asked — a check that says "yes" because
/// its input was never gathered is the same failure as a fabricated number, and it is the more
/// dangerous of the two because it looks like evidence.
public enum ServerChecks {
    /// The six, in the order the inspector renders them.
    public static func all(_ server: MCPServer) -> [CheckResult] {
        [
            indexes(server),
            declaresTools(server),
            authorized(server),
            surfaceApproved(server),
            operative(server),
            callsSucceed(server)
        ]
    }

    /// The router can start it and read its tool surface.
    public static func indexes(_ server: MCPServer) -> CheckResult {
        if let error = server.indexError, !error.isEmpty {
            return CheckResult(.indexes, .failed, reason: CheckCopy.indexFailed(error))
        }
        guard server.indexedAt != nil else {
            return CheckResult(.indexes, .unknown, reason: CheckCopy.neverIndexed)
        }
        return CheckResult(.indexes, .passed)
    }

    /// It offers at least one tool.
    ///
    /// **Not observed whenever the index is failing**, whatever `tools` holds. A server that indexed
    /// cleanly last week and now fails still carries last week's count, and reporting a confirmation
    /// from it would be asserting a present fact from a stale reading. The spec gate caught this; the
    /// first draft looked only at `indexedAt`.
    public static func declaresTools(_ server: MCPServer) -> CheckResult {
        if let error = server.indexError, !error.isEmpty {
            return CheckResult(.declaresTools, .unknown, reason: CheckCopy.toolsUnknownUntilIndexed)
        }
        guard server.indexedAt != nil else {
            return CheckResult(.declaresTools, .unknown, reason: CheckCopy.toolsUnknownUntilIndexed)
        }
        guard server.tools > 0 else {
            return CheckResult(.declaresTools, .failed, reason: CheckCopy.noToolsDeclared)
        }
        return CheckResult(.declaresTools, .passed)
    }

    /// Its credentials are current.
    ///
    /// `.notApplicable` rather than a pass when the transport carries no credentials: "there are none
    /// to be current" and "the ones it has are current" are different statements, and only one of
    /// them is true of a stdio server.
    public static func authorized(_ server: MCPServer) -> CheckResult {
        guard server.auth.supported else {
            return CheckResult(.authorized, .notApplicable, reason: CheckCopy.credentialsNotApplicable)
        }
        guard server.auth.authorized else {
            return CheckResult(.authorized, .failed, reason: CheckCopy.credentialsMissing)
        }
        return CheckResult(.authorized, .passed)
    }

    /// No tool description is waiting for review.
    public static func surfaceApproved(_ server: MCPServer) -> CheckResult {
        guard let pending = server.pendingChange else {
            return CheckResult(.surfaceApproved, .passed)
        }
        return CheckResult(
            .surfaceApproved,
            .failed,
            reason: CheckCopy.surfaceHeld(count: pending.count, seenAt: pending.seenAt)
        )
    }

    /// It carries no placard.
    public static func operative(_ server: MCPServer) -> CheckResult {
        guard let placard = server.placard else {
            return CheckResult(.operative, .passed)
        }
        return CheckResult(.operative, .failed, reason: CheckCopy.placarded(placard.reason))
    }

    /// Its calls come back without error.
    ///
    /// **The load-bearing one.** Zero calls with zero errors is arithmetically a clean record and is
    /// *not* a confirmation — nobody has ever exercised this server, so whether its calls succeed is
    /// unobserved. Reporting success for something nobody has done is the same defect as a fabricated
    /// number.
    ///
    /// Reads `usage.calls`, never `callsServed`: the former is the recorded window that
    /// `POST /usage/reset` clears and that every sentence on these panes is scoped to, the latter is
    /// this process's lifetime tally. A server whose history was reset must read as never exercised,
    /// because over the window being described it is.
    public static func callsSucceed(_ server: MCPServer) -> CheckResult {
        guard server.usage.calls > 0 else {
            return CheckResult(.callsSucceed, .unknown, reason: CheckCopy.neverExercised)
        }
        guard server.usage.errors > 0 else {
            return CheckResult(.callsSucceed, .passed)
        }
        return CheckResult(
            .callsSucceed,
            .failed,
            reason: CheckCopy.callsFailed(errors: server.usage.errors, calls: server.usage.calls)
        )
    }

    /// The field and value each check was computed from, for the inspector.
    ///
    /// The footer promises a check is "something MCP Router performed and can show you the input to".
    /// That promise is only verifiable by the reader if the input is on screen, and without it a
    /// derived row is indistinguishable from a grade — which is the single strongest objection this
    /// surface faces. So the input is rendered, and this is where it comes from.
    public static func input(_ check: CheckID, _ server: MCPServer) -> String {
        switch check {
        case .indexes:
            "indexedAt = \(server.indexedAt ?? "nil") · indexError = \(server.indexError ?? "nil")"
        case .declaresTools:
            "tools = \(server.tools) · indexError = \(server.indexError ?? "nil")"
        case .authorized:
            "auth.supported = \(server.auth.supported) · auth.authorized = \(server.auth.authorized)"
        case .surfaceApproved:
            "pendingChange = \(server.pendingChange.map { "\($0.count) held" } ?? "nil")"
        case .operative:
            "placard = \(server.placard?.reason ?? "nil")"
        case .callsSucceed:
            "usage.calls = \(server.usage.calls) · usage.errors = \(server.usage.errors)"
        case .reachable, .versioned, .originUnchanged, .updateWantsNoMore, .described:
            // A skill check has no server to read. Unreachable through `all(_:)`, and stated rather
            // than crashed on: an exhaustive switch is what makes the impossibility visible.
            "not a server check"
        }
    }
}
