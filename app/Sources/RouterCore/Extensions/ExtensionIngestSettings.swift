import Foundation

/// The settings half of a run, and the manifest it writes — split from the copy/verify/remove loop
/// so that loop stays readable as the four steps it is.
extension ExtensionIngest {
    /// Withdraw Claude's registration for everything that was actually removed.
    ///
    /// **Only entries that left Claude's tree are unregistered.** A `--link-back` entry keeps its
    /// key, because Claude can still resolve it through the link, and an entry that was refused
    /// never moved. Dropping a key for an extension still sitting in `~/.claude` would be the
    /// mirror image of the drift this item exists to fix.
    func editSettings(
        _ entries: [IngestManifest.Entry],
        outcomes: [IngestOutcome],
        options: Options
    ) -> (ClaudeSettingsEdit.Result?, String?) {
        var removals: [ClaudeSettingsEdit.KeyRemoval] = []
        for entry in entries where !entry.linked {
            guard let container = ClaudeTree.settingsContainer(for: entry.kind) else { continue }
            guard let key = outcomes.first(where: {
                $0.candidate.kind == entry.kind && $0.candidate.name == entry.name
            })?.candidate.settingsKey else { continue }
            removals.append(ClaudeSettingsEdit.KeyRemoval(container: container, key: key))
        }
        guard !removals.isEmpty else { return (nil, nil) }
        do {
            let result = try ClaudeSettingsEdit.remove(
                removals, to: settingsDestination, fileSystem: fileSystem
            )
            // The preservation claim, asserted rather than described. Every removal this type makes
            // is inside a container, so the number of top-level members cannot change; if it did,
            // something rewrote more of the file than it was asked to.
            guard result.topLevelBefore == result.topLevelAfter else {
                let drift = "settings.json went from \(result.topLevelBefore) top-level keys "
                    + "to \(result.topLevelAfter) — the edit is not the one this router makes"
                return (result, drift)
            }
            return (result, nil)
        } catch {
            return (nil, "\(error)")
        }
    }

    func manifest(
        _ runId: String,
        _ startedAt: Double,
        _ entries: [IngestManifest.Entry],
        _ removed: [ClaudeSettingsEdit.RemovedKey]
    ) -> IngestManifest {
        IngestManifest(
            runId: runId, startedAtMilliseconds: startedAt, claudeRoot: tree.root,
            storeRoot: store.root, settingsPath: tree.settingsPath, entries: entries,
            removedSettingsKeys: removed
        )
    }

    /// `nil` when it could not be written, which the caller reports rather than swallows: a run
    /// whose manifest did not land is a run whose removal is not reversible from the router, and
    /// that is the one promise this item cannot quietly drop.
    @discardableResult
    func writeManifest(_ manifest: IngestManifest) -> String? {
        let path = (store.ingestDirectory as NSString)
            .appendingPathComponent("\(manifest.runId).json")
        do {
            try FileManager.default.createDirectory(
                atPath: store.ingestDirectory, withIntermediateDirectories: true
            )
            try Data(IngestManifestJSON.text(manifest).utf8)
                .write(to: URL(fileURLWithPath: path))
            return path
        } catch {
            return nil
        }
    }

    var settingsBackupDirectory: String {
        (store.ingestDirectory as NSString).appendingPathComponent("settings-backups")
    }

    var settingsDestination: ClaudeSettingsEdit.Destination {
        ClaudeSettingsEdit.Destination(
            path: tree.settingsPath,
            backupDirectory: settingsBackupDirectory,
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            nowMilliseconds: clock.nowMilliseconds
        )
    }
}
