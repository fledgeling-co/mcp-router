import Foundation

/// The second half of a watcher run: deleting what was adopted from `~/.claude.json`, and deciding
/// whether the state hash may be sealed.
///
/// Split from ``WatchRunner`` on the seam the reference itself has — adopt into `servers.json`, then
/// unstage from `~/.claude.json`. The two halves fail differently and that is the point: by the time
/// this runs the config has already been written and the restart already issued, so an early return
/// here costs a retry rather than the router never learning about the server (W-D1).
extension WatchRunner {
    // MARK: - Staging

    func deleteFromStaging(
        _ adopted: [(name: String, raw: JSONValue)], state: inout WatchState, pending: [String]
    ) throws {
        // Re-read immediately before writing: this file is rewritten constantly, and the copy
        // parsed at the top of this run may be a minute stale by now (W5).
        let parsed: JSONValue
        do {
            parsed = try JSONParser.parse(fileSystem.readFile(atPath: paths.claudeJSON))
        } catch {
            log.record(.reReadDidNotParse(names: adopted.map(\.name), reason: "\(error)"))
            // Unlike the reference, the restart has already been issued by now, so this early
            // return costs a retry rather than the router never learning about the server (W-D1).
            state.mcpServersHash = nil
            try save(state)
            return
        }
        guard let root = parsed.asObjectMembers else {
            state.mcpServersHash = nil
            try save(state)
            return
        }

        let staged = WatchStaging.stagedServers(of: parsed)
        let outcome = WatchStaging.removable(
            adopted: adopted.map(\.name),
            indexedAs: Dictionary(uniqueKeysWithValues: adopted.map { ($0.name, $0.raw) }),
            staged: staged,
            log: log
        )
        var stillPending = pending + outcome.stillPending

        if !outcome.remove.isEmpty {
            let kept = staged.filter { !outcome.remove.contains($0.key.string) }
            WatchBackup.backUp(
                path: paths.claudeJSON, into: paths.backupDirectory,
                fileSystem: fileSystem, nowMilliseconds: clock.nowMilliseconds
            )
            try WatchBackup.writeAtomic(
                JSStringify.prettyTwoSpace(
                    .object(WatchStaging.replacingStagedServers(in: root, with: kept))
                ),
                toPath: paths.claudeJSON,
                fileSystem: fileSystem,
                processIdentifier: processIdentifier,
                // The reference reads `statSync(CLAUDE_JSON).mode & 0o777` and writes it back: this
                // file is 0600 on some machines and 0644 on others (W4).
                mode: .preserveExisting(orDefault: 0o600)
            )
            let removed = staged.map(\.key.string).filter { outcome.remove.contains($0) }
            log.record(.removedFromStaging(names: removed))
        }

        // Hash what is now on disk, not what was read at the top: our own write is about to fire
        // this watcher again, and that fire must take the fast path (W7).
        let after: String
        if let data = try? fileSystem.readFile(atPath: paths.claudeJSON),
           let reread = try? JSONParser.parse(data)
        {
            after = StableHash.hash(of: .object(WatchStaging.stagedServers(of: reread)))
        } else {
            stillPending.append(contentsOf: adopted.map(\.name))
            after = ""
        }
        try sealOrWithhold(state: &state, hash: after, pending: stillPending, announcing: true)
    }

    /// W8 — anything still pending withholds the state hash so the next fire retries.
    ///
    /// `announcing` is the reference's asymmetry, not a convenience: it logs `still pending` only on
    /// the path where something *was* adopted (`watch.ts:346`). Its other pending branch
    /// (`:352-355`) saves silently, and logging there too would put a line in `watch.log` that the
    /// reference never writes.
    func sealOrWithhold(
        state: inout WatchState, hash: String, pending: [String], announcing: Bool
    ) throws {
        if pending.isEmpty {
            state.mcpServersHash = hash
        } else {
            if announcing { log.record(.stillPending(names: pending)) }
            state.mcpServersHash = nil
        }
        try save(state)
    }
}
