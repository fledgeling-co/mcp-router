import Foundation

/// Put a run back, from the router's own disk, without fetching anything.
///
/// It reverses the apply step in the opposite order: the `settings.json` keys first, then each
/// entry's bytes out of the quarantine and back into Claude's tree, then the router's copy out of
/// the store. Nothing here reads the network, and nothing here deletes: the router's copy leaves
/// through ``ExtensionStoring/remove(_:name:)``, which moves it aside rather than destroying it, so
/// an undo of an undo is still possible.
///
/// **It refuses rather than clobbers.** An entry whose original path is occupied by anything other
/// than the link this run left there is skipped and reported, because the alternative is deleting
/// whatever somebody put back by hand.
public enum ExtensionIngestUndo {
    /// Hoisted out of ``Outcome`` rather than nested inside it: SwiftLint's `nesting` rule caps
    /// types at one level deep, and a third level here would buy nothing a prefix does not.
    public enum State: String, Sendable {
        case restored
        case skipped
    }

    public struct Outcome: Sendable {
        public let kind: ExtensionKind
        public let name: String
        public let state: State
        public let detail: String
    }

    public struct Report: Sendable {
        public let runId: String
        public let outcomes: [Outcome]
        public let settingsRestored: Int
        public let settingsFailure: String?
    }

    public static func undo(
        _ manifest: IngestManifest,
        store: DiskExtensionStore,
        fileSystem: any FileSystem & FileModeWriting,
        clock: any RouterClock
    ) -> Report {
        var restoredKeys = 0
        var settingsFailure: String?
        do {
            restoredKeys = try ClaudeSettingsEdit.restore(
                manifest.removedSettingsKeys,
                to: ClaudeSettingsEdit.Destination(
                    path: manifest.settingsPath,
                    backupDirectory: (store.ingestDirectory as NSString)
                        .appendingPathComponent("settings-backups"),
                    processIdentifier: ProcessInfo.processInfo.processIdentifier,
                    nowMilliseconds: clock.nowMilliseconds
                ),
                fileSystem: fileSystem
            )
        } catch {
            settingsFailure = "\(error)"
        }
        let outcomes = manifest.entries.reversed().map { restore($0, store: store) }
        return Report(
            runId: manifest.runId, outcomes: outcomes, settingsRestored: restoredKeys,
            settingsFailure: settingsFailure
        )
    }

    private static func restore(
        _ entry: IngestManifest.Entry, store: DiskExtensionStore
    ) -> Outcome {
        func skip(_ detail: String) -> Outcome {
            Outcome(kind: entry.kind, name: entry.name, state: .skipped, detail: detail)
        }
        guard let quarantine = entry.quarantinePath,
              FileManager.default.fileExists(atPath: quarantine)
        else {
            return skip("nothing in the quarantine at \(entry.quarantinePath ?? "—")")
        }
        if let occupied = occupant(of: entry) { return skip(occupied) }
        do {
            try FileManager.default.createDirectory(
                atPath: (entry.sourcePath as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(atPath: quarantine, toPath: entry.sourcePath)
        } catch {
            return skip("could not be moved back: \(error.localizedDescription)")
        }
        switch store.remove(entry.kind, name: entry.name) {
        case let .removed(path):
            return Outcome(
                kind: entry.kind, name: entry.name, state: .restored,
                detail: "back at \(entry.sourcePath); the router's copy is aside at \(path)"
            )
        case let .refused(refusal):
            return Outcome(
                kind: entry.kind, name: entry.name, state: .restored,
                detail: "back at \(entry.sourcePath); the router's copy stayed: \(refusal.message)"
            )
        }
    }

    /// What is sitting at the original path, when something is and it is not ours to remove.
    ///
    /// The `--link-back` link is ours, and only when it still points where this run pointed it. A
    /// link somebody re-aimed is not, and neither is a directory: both are reported and left.
    private static func occupant(of entry: IngestManifest.Entry) -> String? {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: entry.sourcePath, isDirectory: &isDirectory)
            || (try? manager.attributesOfItem(atPath: entry.sourcePath)) != nil
        else { return nil }
        guard entry.linked,
              let target = try? manager.destinationOfSymbolicLink(atPath: entry.sourcePath)
        else {
            return "\(entry.sourcePath) is occupied by something this run did not put there"
        }
        guard target == entry.storedPath else {
            return "\(entry.sourcePath) is a link to \(target), not to this run's copy"
        }
        do {
            try manager.removeItem(atPath: entry.sourcePath)
            return nil
        } catch {
            return "the link at \(entry.sourcePath) could not be removed: "
                + error.localizedDescription
        }
    }
}
