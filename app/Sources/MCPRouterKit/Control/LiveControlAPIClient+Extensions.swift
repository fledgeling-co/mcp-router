import Foundation

/// The held-version writes on the live client: promote, undo a promotion, and keep a held version.
///
/// Each decodes the router's reply into a thin ack, and none re-reads the board. A control that painted
/// itself from its own answer would be reporting its own success, which is what the analyst writes
/// are careful to avoid too. The board reloads `GET /skills` after a write.
public extension LiveControlAPIClient {
    func promote(
        _ name: String, kind: StoredExtensionKind, pluginVersion: String, files: [ExtensionFileBody]
    ) async throws(ControlAPIError) -> PromotionAck {
        try await send(
            .post,
            entryPath(kind, name, "promote"),
            body: jsonBody(PromoteBody(pluginVersion: pluginVersion, files: files)),
            as: PromotionAck.self
        )
    }

    func undoPromotion(
        _ name: String, kind: StoredExtensionKind, restore: String
    ) async throws(ControlAPIError) -> UndoAck {
        try await send(
            .post,
            entryPath(kind, name, "undo-promote"),
            body: jsonBody(UndoBody(restore: restore)),
            as: UndoAck.self
        )
    }

    func keepHeldVersion(
        _ name: String, kind: StoredExtensionKind, pluginVersion: String
    ) async throws(ControlAPIError) -> KeepAck {
        try await send(
            .post,
            entryPath(kind, name, "keep"),
            body: jsonBody(KeepBody(pluginVersion: pluginVersion)),
            as: KeepAck.self
        )
    }

    private func entryPath(_ kind: StoredExtensionKind, _ name: String, _ action: String) -> String {
        "extensions/\(kind.rawValue)/\(segment(name))/\(action)"
    }

    private func jsonBody(_ value: some Encodable) throws(ControlAPIError) -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw ControlAPIError.malformedResponse(detail: "could not encode the request: \(error)")
        }
    }
}

/// The request bodies, one per route. Private to this file: nothing else sends them.
private struct PromoteBody: Encodable {
    let pluginVersion: String
    let files: [ExtensionFileBody]
}

private struct UndoBody: Encodable {
    let restore: String
}

private struct KeepBody: Encodable {
    let pluginVersion: String
}
