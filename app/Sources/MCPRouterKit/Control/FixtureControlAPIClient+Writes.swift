import Foundation

/// The fixture client's writes.
///
/// Split out of `FixtureControlAPIClient.swift` for file length, and the writes are the right cut:
/// every one of them is the same three lines — refuse if the scenario is a failure one, decode the
/// recorded response, stamp the caller's own name into it — while the reads each branch on the
/// scenario and are where the fixture actually models anything.
///
/// **None of these branch on scenario beyond `guardFailure()`, and that is correct rather than an
/// omission.** A write's answer is the write's answer; the empty scenario has no empty form of
/// "this server was added". The one read that likewise does not branch is `server(named:)`, which
/// has no meaningful empty form either and no caller.
public extension FixtureControlAPIClient {
    func add(_ server: NewServer, force _: Bool) async throws(ControlAPIError) -> AddedServer {
        try guardFailure()
        var added = try decode("added", as: AddedServer.self)
        added.added = server.name
        return added
    }

    func remove(_ name: String, keepHistory _: Bool) async throws(ControlAPIError) -> RemovedServer {
        try guardFailure()
        var removed = try decode("removed", as: RemovedServer.self)
        removed.removed = name
        return removed
    }

    func reindex(_ name: String) async throws(ControlAPIError) -> ReindexResult {
        try guardFailure()
        var result = try decode("reindex-failure", as: ReindexResult.self)
        result.name = name
        if scenario == .success { result.error = nil; result.tools = 14 }
        return result
    }

    func patch(server name: String, _ patch: ServerPatch) async throws(ControlAPIError) -> MCPServer {
        try guardFailure()
        var server = try decode("patch-response", as: MCPServer.self)
        server.name = name
        if let warm = patch.warm { server.warm = warm }
        if let projects = patch.projects { server.projects = projects }
        return server
    }

    func approvePendingChange(server name: String) async throws(ControlAPIError) -> ApprovalResult {
        try guardFailure()
        var approval = try decode("approve", as: ApprovalResult.self)
        approval.server = name
        return approval
    }

    func beginAuthorization(for name: String) async throws(ControlAPIError) -> AuthorizationStart {
        try guardFailure()
        var start = try decode("auth-start", as: AuthorizationStart.self)
        start.server = name
        return start
    }

    func signOut(_ name: String) async throws(ControlAPIError) -> SignedOut {
        try guardFailure()
        var out = try decode("signout", as: SignedOut.self)
        out.server = name
        return out
    }

    func resetUsage() async throws(ControlAPIError) -> UsageReset {
        try guardFailure()
        return try decode("usage-reset", as: UsageReset.self)
    }

    // The held-version writes answer the router's shapes and keep no state. The fixture board does not
    // re-derive its rows from a write, so a fixture answer is an echo of what was asked, and the error
    // scenario refuses every one of them, which is how the refusal path is exercised.

    func promote(
        _ name: String, kind: StoredExtensionKind, pluginVersion: String, files _: [ExtensionFileBody]
    ) async throws(ControlAPIError) -> PromotionAck {
        try guardFailure()
        return PromotionAck(
            promoted: name, kind: kind, pluginVersion: pluginVersion, replaced: "2.2.0",
            restore: "1700000000000"
        )
    }

    func undoPromotion(
        _ name: String, kind: StoredExtensionKind, restore _: String
    ) async throws(ControlAPIError) -> UndoAck {
        try guardFailure()
        return UndoAck(restored: name, kind: kind, version: "2.2.0", withdrawn: "2.3.0")
    }

    func keepHeldVersion(
        _ name: String, kind: StoredExtensionKind, pluginVersion: String
    ) async throws(ControlAPIError) -> KeepAck {
        try guardFailure()
        return KeepAck(kept: name, kind: kind, pluginVersion: pluginVersion)
    }
}
