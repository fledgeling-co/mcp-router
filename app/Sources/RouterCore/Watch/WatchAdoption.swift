import Foundation

/// The adoption merge — W10's answer, and the only part of the run that holds the lock.
///
/// The shape is chosen so the critical section is microseconds long:
///
/// ```
/// index the stale servers        seconds, NO lock       (X3)
/// ┌─ withExclusiveLock ────────────────────────────┐
/// │  re-read servers.json fresh                     │
/// │  merge only our own delta                       │
/// │  persist restartPending, then write             │
/// └─────────────────────────────────────────────────┘
/// ```
///
/// Re-reading **inside** the lock is what makes a concurrent control-API PATCH survive: the object
/// the delta is applied to is the one currently on disk, not the one read before indexing began.
///
/// **This does not go through ``ConfigEdit/edit(path:fileSystem:processIdentifier:lockTimeoutMs:_:)``
/// (X2a).** The two share the lock, not the writer, for three measured reasons: `edit` writes
/// unconditionally where the reference writes only when the config actually changed, which would
/// issue restarts the reference never issues; `edit` emits no trailing newline at mode `0600` where
/// this writes `+ "\n"` at `0644` (`watch.ts:282`); and nesting the two would have this call block
/// on its own lock.
///
/// The byte claim is proven by `modesAreHonoured` and `JSStringify`'s own parity suite, **not** by
/// `cli-watch`. An earlier version of this comment said the lane diffed these bytes; it cannot.
/// X12b arranges every lane scenario so `configChanged` stays false on both sides — otherwise the
/// reference reaches its hardcoded `kickstart` and restarts the developer's live router — so no
/// lane scenario ever writes `servers.json`. A comment naming a check that structurally cannot run
/// is worse than no comment, because the next reader stops looking for the real one.
public enum WatchAdoption {
    public enum Problem: Error, Sendable, Equatable, CustomStringConvertible {
        case unparseableRouterConfig(path: String, reason: String)
        case flatRouterConfig(path: String)

        public var description: String {
            switch self {
            case let .unparseableRouterConfig(path, reason):
                "\(path) is not valid JSON (\(reason)). Nothing was changed."
            case let .flatRouterConfig(path):
                WatchLogEvent.flatRouterConfig(path: path).message
            }
        }
    }

    /// The mode `writeAtomic(DEFAULT_CONFIG_PATH, …, 0o644)` sets. Fixed, not preserved — unlike
    /// `~/.claude.json`, which the reference reads the mode off first.
    static let routerConfigMode: UInt16 = 0o644

    /// Where the merge writes, and under what rules. One value rather than six parameters that are
    /// only meaningful together — the lock, the backup directory and the mode all describe the same
    /// destination.
    public struct Destination: Sendable {
        public let path: String
        public let backupDirectory: String
        public let processIdentifier: Int32
        public let lockTimeoutMs: Int

        public init(
            path: String, backupDirectory: String, processIdentifier: Int32, lockTimeoutMs: Int
        ) {
            self.path = path
            self.backupDirectory = backupDirectory
            self.processIdentifier = processIdentifier
            self.lockTimeoutMs = lockTimeoutMs
        }
    }

    /// Merge `adopted` into `servers.json` under the lock. Returns whether the file changed.
    ///
    /// `beforePersistingWrite` runs **inside the lock and before the rename**. That is where the
    /// owed restart is recorded, and the order is the fix for a crash window the reviewer found: a
    /// process killed between the rename and a later state save would leave the config changed,
    /// nothing owed, and the running router never told — D7's end state through a different door.
    public static func merge(
        adopted: [(name: String, raw: JSONValue)],
        into destination: Destination,
        fileSystem: any FileSystem & FileModeWriting,
        nowMilliseconds: Double,
        beforePersistingWrite: () throws -> Void
    ) throws -> Bool {
        let path = destination.path
        return try ConfigMutationLock.withExclusiveLock(
            forConfigAt: path, timeoutMs: destination.lockTimeoutMs
        ) {
            var root = try readRoot(at: path, fileSystem: fileSystem)
            var servers = try serversObject(in: root, at: path)
            guard applyDelta(adopted, to: &servers) else { return false }

            let key = JSString("mcpServers")
            if let index = root.firstIndex(where: { $0.key == key }) {
                root[index] = JSONMember(key: key, value: .object(servers))
            } else {
                root.append(JSONMember(key: key, value: .object(servers)))
            }

            try beforePersistingWrite()
            WatchBackup.backUp(
                path: path, into: destination.backupDirectory,
                fileSystem: fileSystem, nowMilliseconds: nowMilliseconds
            )
            try WatchBackup.writeAtomic(
                "\(JSStringify.prettyTwoSpace(.object(root)))\n",
                toPath: path,
                fileSystem: fileSystem,
                processIdentifier: destination.processIdentifier,
                mode: .fixed(routerConfigMode)
            )
            return true
        }
    }

    private static func readRoot(
        at path: String, fileSystem: any FileSystem
    ) throws -> [JSONMember] {
        let data = try fileSystem.readFile(atPath: path)
        let parsed: JSONValue
        do {
            parsed = try JSONParser.parse(data)
        } catch {
            throw Problem.unparseableRouterConfig(path: path, reason: "\(error)")
        }
        guard let root = parsed.asObjectMembers else {
            throw Problem.unparseableRouterConfig(path: path, reason: "not an object")
        }
        return root
    }

    /// The `mcpServers` object to merge into, or a refusal.
    ///
    /// The reference does `routerCfg.mcpServers ?? {}` here and writes the result back, which on a
    /// flat config discards every server the file declared — R1's D1 reached through the watcher.
    /// Refusing is W-D7.
    private static func serversObject(
        in root: [JSONMember], at path: String
    ) throws -> [JSONMember] {
        switch root.first(where: { $0.key == JSString("mcpServers") })?.value {
        case let .some(.object(members)):
            return members
        case .none, .some(.null):
            guard !ConfigEdit.declaresServersAtTopLevel(root) else {
                throw Problem.flatRouterConfig(path: path)
            }
            return []
        default:
            throw Problem.flatRouterConfig(path: path)
        }
    }

    /// Apply only our own delta. Returns whether anything actually changed.
    private static func applyDelta(
        _ adopted: [(name: String, raw: JSONValue)], to servers: inout [JSONMember]
    ) -> Bool {
        var changed = false
        for entry in adopted {
            let name = JSString(entry.name)
            let existing = servers.first { $0.key == name }?.value
            // `JSON.stringify(stable(a)) !== JSON.stringify(stable(b))` — key order is not a change,
            // so a client that rewrote the entry with its keys in another order does not cost a
            // config write and a router restart.
            let same = existing.map {
                JSStringify.compact(StableHash.stable($0))
                    == JSStringify.compact(StableHash.stable(entry.raw))
            } ?? false
            guard !same else { continue }
            let member = JSONMember(key: name, value: entry.raw)
            if let index = servers.firstIndex(where: { $0.key == name }) {
                servers[index] = member
            } else {
                servers.append(member)
            }
            changed = true
        }
        return changed
    }
}
