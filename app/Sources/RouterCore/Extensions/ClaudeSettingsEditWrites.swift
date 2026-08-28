import Foundation

/// The two operations on `settings.json`, split from their types so the file that decides what to
/// write is the short one.
public extension ClaudeSettingsEdit {
    /// Delete the named keys out of their containers. Everything else is left exactly where it was.
    static func remove(
        _ removals: [KeyRemoval],
        to destination: Destination,
        fileSystem: any FileSystem & FileModeWriting
    ) throws -> Result {
        let path = destination.path
        guard fileSystem.fileExists(atPath: path) else {
            // A Claude tree with no settings file has nothing registered in it, so there is nothing
            // to unregister. Creating one here would put a file into a home the user does not have.
            return Result(
                removed: [], absent: removals, topLevelBefore: 0, topLevelAfter: 0,
                backupPath: nil, wrote: false
            )
        }
        let before = try? fileSystem.attributes(atPath: path)
        var root = try parse(path, fileSystem: fileSystem)
        let topLevelBefore = root.count
        var removed: [RemovedKey] = []
        var absent: [KeyRemoval] = []
        try apply(removals, to: &root, removed: &removed, absent: &absent)
        guard !removed.isEmpty else {
            return Result(
                removed: [], absent: absent, topLevelBefore: topLevelBefore,
                topLevelAfter: topLevelBefore, backupPath: nil, wrote: false
            )
        }
        let backup = WatchBackup.backUp(
            path: path, into: destination.backupDirectory, fileSystem: fileSystem,
            nowMilliseconds: destination.nowMilliseconds
        )
        try write(root, to: destination, expecting: before, fileSystem: fileSystem)
        return Result(
            removed: removed, absent: absent, topLevelBefore: topLevelBefore,
            topLevelAfter: root.count, backupPath: backup, wrote: true
        )
    }

    /// Put removed keys back, at the index they came from.
    ///
    /// **In reverse.** `restorations` arrives in the order the keys were removed, and each index was
    /// recorded against the array as it stood at that moment — so every later removal's index was
    /// taken from a list already shortened by the earlier ones. Undoing forwards therefore restores
    /// the values and scrambles their order. Worked through on the fixture: `enabledPlugins`
    /// `[cr@fledgeling, cr@claude-code, swift-lsp]` loses index 1 then index 0, and re-inserting at
    /// 1 then 0 yields `[cr@fledgeling, swift-lsp, cr@claude-code]` — every key present, one of
    /// them moved. Re-inserting at 0 then 1 yields the original. Position is not cosmetic here:
    /// this file is one a person reads and diffs, and an undo that reorders it is an undo that
    /// leaves a diff behind.
    ///
    /// A key whose container has since gone is re-created as a container holding just that key,
    /// because the alternative — dropping it — would be an undo reporting success while leaving the
    /// extension unregistered.
    @discardableResult
    static func restore(
        _ restorations: [RemovedKey],
        to destination: Destination,
        fileSystem: any FileSystem & FileModeWriting
    ) throws -> Int {
        let path = destination.path
        guard !restorations.isEmpty, fileSystem.fileExists(atPath: path) else { return 0 }
        let before = try? fileSystem.attributes(atPath: path)
        var root = try parse(path, fileSystem: fileSystem)
        var restored = 0
        for entry in restorations.reversed() {
            guard let value = try? JSONParser.parse(entry.valueJSON) else { continue }
            let name = JSString(entry.container)
            var members = root.first { $0.key == name }?.value.asObjectMembers ?? []
            guard !members.contains(where: { $0.key == JSString(entry.key) }) else { continue }
            let at = min(max(entry.index, 0), members.count)
            members.insert(JSONMember(key: JSString(entry.key), value: value), at: at)
            set(&root, name, .object(members))
            restored += 1
        }
        guard restored > 0 else { return 0 }
        WatchBackup.backUp(
            path: path, into: destination.backupDirectory, fileSystem: fileSystem,
            nowMilliseconds: destination.nowMilliseconds
        )
        try write(root, to: destination, expecting: before, fileSystem: fileSystem)
        return restored
    }

    // MARK: - The three steps neither operation may skip

    private static func parse(
        _ path: String, fileSystem: any FileSystem
    ) throws -> [JSONMember] {
        guard let data = try? fileSystem.readFile(atPath: path),
              let text = String(data: data, encoding: .utf8),
              let parsed = try? JSONParser.parse(text)
        else { throw Failure.unparsable(path) }
        guard let members = parsed.asObjectMembers else { throw Failure.notAnObject(path) }
        return members
    }

    private static func apply(
        _ removals: [KeyRemoval],
        to root: inout [JSONMember],
        removed: inout [RemovedKey],
        absent: inout [KeyRemoval]
    ) throws {
        for container in orderedContainers(of: removals) {
            let name = JSString(container)
            guard let existing = root.first(where: { $0.key == name })?.value else {
                absent.append(contentsOf: removals.filter { $0.container == container })
                continue
            }
            guard var members = existing.asObjectMembers else {
                throw Failure.containerNotAnObject(container)
            }
            for removal in removals where removal.container == container {
                let key = JSString(removal.key)
                guard let index = members.firstIndex(where: { $0.key == key }) else {
                    absent.append(removal)
                    continue
                }
                removed.append(RemovedKey(
                    container: container, key: removal.key,
                    valueJSON: JSStringify.compact(members[index].value), index: index
                ))
                members.remove(at: index)
            }
            set(&root, name, .object(members))
        }
    }

    /// Stamp, write, and refuse if the file moved under us.
    ///
    /// The stamp is compared immediately before the rename rather than after it, because after is
    /// too late: the write would already have discarded whatever landed in the window.
    private static func write(
        _ root: [JSONMember],
        to destination: Destination,
        expecting stamp: FileStamp?,
        fileSystem: any FileSystem & FileModeWriting
    ) throws {
        let path = destination.path
        if let stamp, let now = try? fileSystem.attributes(atPath: path), now != stamp {
            throw Failure.changedUnderfoot(path)
        }
        do {
            // Two-space indent and a trailing newline, which is what Claude's own writer produces —
            // measured on the real file, 2026-08-28. Matching it keeps the diff of an ingest run to
            // the lines it actually changed.
            try WatchBackup.writeAtomic(
                JSStringify.prettyTwoSpace(.object(root)) + "\n",
                toPath: path,
                fileSystem: fileSystem,
                processIdentifier: destination.processIdentifier,
                mode: .preserveExisting
            )
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.writeFailed("\(path) could not be written: \(error.localizedDescription)")
        }
    }

    /// The containers named by the removals, in first-seen order, without a dictionary — the wire
    /// lint covers this directory and member order is what this whole type is about.
    private static func orderedContainers(of removals: [KeyRemoval]) -> [String] {
        var seen: [String] = []
        for removal in removals where !seen.contains(removal.container) {
            seen.append(removal.container)
        }
        return seen
    }

    private static func set(_ members: inout [JSONMember], _ key: JSString, _ value: JSONValue) {
        guard let index = members.firstIndex(where: { $0.key == key }) else {
            members.append(JSONMember(key: key, value: value))
            return
        }
        members[index] = JSONMember(key: key, value: value)
    }
}
