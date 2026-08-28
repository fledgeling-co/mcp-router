import Foundation

/// Taking a whole directory into the store, byte for byte — R30's half of ``DiskExtensionStore``.
///
/// ``ExtensionStoring/add(_:name:files:)`` cannot be used for this and the reason is in its
/// signature: an ``ExtensionFile`` carries `text: String`, so every file it can express is UTF-8.
/// A plugin tree holds images, compiled assets and symlinks, and routing them through a `String`
/// would either fail or silently transcode. R28 built `add` for a caller that has bytes it authored;
/// this is for a caller that has a directory somebody else authored, and the difference is not one
/// an encoder can paper over.
///
/// What it keeps from `add` is the part that matters: **every refusal happens before a byte is
/// written**, the copy lands in `<root>/.staging` and is renamed into place in one operation, and
/// the record is read back off disk rather than reported from the request.
public extension DiskExtensionStore {
    /// Copy `source` in under `name`, atomically.
    ///
    /// The destination is refused if it exists — two adds racing on one name must not have the
    /// loser overwrite the winner — and a failure anywhere leaves its wreckage in `.staging`, where
    /// no listing reads.
    func adopt(
        _ kind: ExtensionKind, name: String, from source: String
    ) -> ExtensionWriteOutcome {
        guard ExtensionNaming.isWellFormedName(name) else {
            return .refused(ExtensionRefusal(
                status: 400, reason: "invalidName",
                message: "\"\(name)\" is not a usable name for a \(kind.singular)"
            ))
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return .refused(ExtensionRefusal(
                status: 400, reason: "noSource", message: "\(source) is not a directory"
            ))
        }
        let destination = entryPath(kind, name)
        guard !FileManager.default.fileExists(atPath: destination) else {
            return .refused(ExtensionRefusal(
                status: 409, reason: "nameTaken",
                message: "a \(kind.singular) named \"\(name)\" already exists"
            ))
        }
        let staging = adoptStagingPath(kind, name)
        do {
            try FileManager.default.createDirectory(
                atPath: (staging as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(atPath: source, toPath: staging)
            try FileManager.default.createDirectory(
                atPath: directory(for: kind), withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(atPath: staging, toPath: destination)
        } catch {
            try? FileManager.default.removeItem(atPath: staging)
            return .refused(ExtensionRefusal(
                status: 500, reason: "writeFailed",
                message: "\(name) could not be copied in: \(error.localizedDescription)"
            ))
        }
        guard let record = read(kind, name: name) else {
            return .refused(ExtensionRefusal(
                status: 500, reason: "writeFailed",
                message: "\(name) was copied in and could not be read back"
            ))
        }
        return .added(record)
    }

    /// Where the entry a removal moved aside would be put back.
    ///
    /// Exposed so an undo can reach it without re-deriving a path the store owns, and named rather
    /// than inlined because getting it wrong writes into the one directory this item promises is
    /// recoverable.
    func quarantineDirectory(_ kind: ExtensionKind) -> String {
        let removed = (root as NSString).appendingPathComponent(".removed")
        // `.removed/claude/<kind>`, one level below where ``remove(_:name:)`` puts a store entry.
        // The two are kept apart because they are put back in opposite directions: a store removal
        // goes back into the store, and this one goes back into Claude's own tree.
        let claude = (removed as NSString).appendingPathComponent("claude")
        return (claude as NSString).appendingPathComponent(kind.rawValue)
    }

    /// `<root>/.ingest` — where a run's manifest is written. A sibling of the three kind
    /// directories and dot-prefixed, so ``list(_:)`` never reads it and `ExtensionNaming` refuses
    /// any entry that could be called one.
    var ingestDirectory: String {
        (root as NSString).appendingPathComponent(".ingest")
    }

    private func adoptStagingPath(_ kind: ExtensionKind, _ name: String) -> String {
        let staging = (root as NSString).appendingPathComponent(".staging")
        return (staging as NSString)
            .appendingPathComponent("adopt-\(kind.rawValue)-\(name)-\(Int(clockMilliseconds))")
    }
}
