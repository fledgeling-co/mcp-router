import Foundation

/// Copy, verify, then remove — and never in any other order.
///
/// The order is the whole safety argument, so it is worth saying what each step buys:
///
///  * **copy** puts the bytes in the router's store through ``DiskExtensionStore/adopt(_:name:from:)``,
///    which stages and renames, so a failure leaves no half-entry under a name.
///  * **verify** re-measures the source and compares it to the stamp the scan took, then
///    compares the store's copy against the source, then reads the entry back through the store's
///    own reader and requires it to have no problem. The first of those three is what makes the
///    settle window a guarantee rather than a window: a tree edited *during* the copy is caught
///    here, not merely one edited before it.
///  * **remove** moves Claude's directory into `<store>/.removed/claude/…`. It is never deleted.
///
/// A failure at any step leaves Claude's copy untouched and takes the router's copy back out, so
/// the two states this can end in are "both copies, plan not applied" and "one copy, in the router".
/// There is no state in which neither exists.
public struct ExtensionIngest: Sendable {
    public struct Options: Sendable {
        /// Leave a symlink at Claude's path pointing at the router's copy, and keep the
        /// `settings.json` registration.
        ///
        /// Off by default, because it is the mode whose success cannot be proven here: whether
        /// Claude follows a symlink into another directory for a skill or a plugin is a fact about
        /// Claude, and establishing it means running against the live tree. With it off, the router
        /// holds the only copy and Claude's registration is withdrawn, which is a state this suite
        /// can measure end to end.
        public let linkBack: Bool

        public init(linkBack: Bool = false) {
            self.linkBack = linkBack
        }
    }

    public struct Run: Sendable {
        public let runId: String
        public let outcomes: [IngestOutcome]
        public let settings: ClaudeSettingsEdit.Result?
        /// Why the settings edit did not happen, when it did not. The entries are still ingested and
        /// still in the manifest — a settings file this router would not touch is a reason to stop
        /// editing it, not a reason to abandon bytes already moved.
        public let settingsFailure: String?
        public let manifestPath: String?
        public let manifest: IngestManifest
    }

    let store: DiskExtensionStore
    let tree: ClaudeTree
    let clock: any RouterClock
    let fileSystem: any FileSystem & FileModeWriting

    public init(
        store: DiskExtensionStore,
        tree: ClaudeTree,
        clock: any RouterClock = SystemClock(),
        fileSystem: any FileSystem & FileModeWriting = RealFileSystem()
    ) {
        self.store = store
        self.tree = tree
        self.clock = clock
        self.fileSystem = fileSystem
    }

    public func apply(_ candidates: [IngestCandidate], options: Options = Options()) -> Run {
        let runId = "ingest-\(Int(clock.nowMilliseconds))"
        let startedAt = clock.nowMilliseconds
        var outcomes: [IngestOutcome] = []
        var entries: [IngestManifest.Entry] = []
        for candidate in candidates {
            let outcome = ingest(candidate, options: options)
            outcomes.append(outcome)
            guard outcome.state != .refused, let stored = outcome.storedPath else { continue }
            entries.append(IngestManifest.Entry(
                kind: candidate.kind, name: candidate.name, sourcePath: candidate.sourcePath,
                storedPath: stored, quarantinePath: outcome.quarantinePath,
                linked: outcome.state == .linked, version: candidate.version,
                digest: candidate.stamp.digest, files: candidate.stamp.files,
                bytes: candidate.stamp.bytes
            ))
        }
        // Written BEFORE the settings edit as well as after it. A crash between the two leaves a
        // manifest that already names every quarantined directory, which is what an undo needs; a
        // manifest written only at the end would leave the bytes moved and unrecorded.
        let partial = manifest(runId, startedAt, entries, [])
        let path = writeManifest(partial)
        let (result, failure) = editSettings(entries, outcomes: outcomes, options: options)
        let complete = manifest(runId, startedAt, entries, result?.removed ?? [])
        return Run(
            runId: runId, outcomes: outcomes, settings: result, settingsFailure: failure,
            manifestPath: writeManifest(complete) ?? path, manifest: complete
        )
    }

    // MARK: - One entry

    private func ingest(_ candidate: IngestCandidate, options: Options) -> IngestOutcome {
        func refuse(_ detail: String) -> IngestOutcome {
            IngestOutcome(candidate: candidate, state: .refused, detail: detail)
        }
        switch store.adopt(candidate.kind, name: candidate.name, from: candidate.sourcePath) {
        case let .refused(refusal):
            return refuse("copy refused: \(refusal.message)")
        case .added:
            break
        }
        let stored = store.entryPath(candidate.kind, candidate.name)
        if let problem = verify(candidate, storedAt: stored) {
            try? FileManager.default.removeItem(atPath: stored)
            return refuse(problem)
        }
        let quarantine = quarantinePath(candidate)
        do {
            try FileManager.default.createDirectory(
                atPath: (quarantine as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(atPath: candidate.sourcePath, toPath: quarantine)
        } catch {
            try? FileManager.default.removeItem(atPath: stored)
            return refuse("Claude's copy could not be moved aside: \(error.localizedDescription)")
        }
        guard options.linkBack else {
            return IngestOutcome(
                candidate: candidate, state: .ingested, storedPath: stored,
                quarantinePath: quarantine, detail: "the router holds the only copy"
            )
        }
        do {
            try FileManager.default.createSymbolicLink(
                atPath: candidate.sourcePath, withDestinationPath: stored
            )
        } catch {
            // The bytes are safe in two places and the link is the only thing that failed, so put
            // Claude's copy back rather than leaving a path that resolves to nothing.
            try? FileManager.default.moveItem(atPath: quarantine, toPath: candidate.sourcePath)
            try? FileManager.default.removeItem(atPath: stored)
            return refuse("the link back could not be created: \(error.localizedDescription)")
        }
        return IngestOutcome(
            candidate: candidate, state: .linked, storedPath: stored,
            quarantinePath: quarantine,
            detail: "Claude's path is now a link to the router's copy"
        )
    }

    /// `nil` when all three checks hold. The sentence, when one does not.
    private func verify(_ candidate: IngestCandidate, storedAt stored: String) -> String? {
        guard let after = ExtensionStamp.measure(candidate.sourcePath) else {
            return "\(candidate.sourcePath) could not be re-measured after the copy"
        }
        guard after == candidate.stamp else {
            return "\(candidate.sourcePath) changed while it was being copied, so nothing was moved"
        }
        guard let copied = ExtensionStamp.measure(stored) else {
            return "the router's copy at \(stored) could not be measured"
        }
        guard copied.digest == candidate.stamp.digest else {
            return "the router's copy does not match: \(copied.files) files / \(copied.bytes) bytes "
                + "against \(candidate.stamp.files) / \(candidate.stamp.bytes)"
        }
        guard let record = store.read(candidate.kind, name: candidate.name) else {
            return "the router's copy could not be read back through the store"
        }
        if let problem = record.problem {
            return "the router's copy does not read as a \(candidate.kind.singular): \(problem)"
        }
        return nil
    }

    private func quarantinePath(_ candidate: IngestCandidate) -> String {
        let kindDirectory = store.quarantineDirectory(candidate.kind)
        let entry = (kindDirectory as NSString).appendingPathComponent(candidate.name)
        return (entry as NSString).appendingPathComponent(String(Int(clock.nowMilliseconds)))
    }
}
