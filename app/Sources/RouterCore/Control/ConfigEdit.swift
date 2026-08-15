import Foundation

/// Reading, changing and writing `servers.json`, plus reloading the live maps.
public enum ConfigEdit {
    /// The mode the reference commits `servers.json` at (`src/control.ts:95`), and the one B31
    /// names. The watcher writes the same file at `0644` (`watch.ts:282`, ``WatchAdoption``), which
    /// is the reference's own asymmetry and is preserved rather than reconciled.
    static let configMode: UInt16 = 0o600

    public enum Problem: Error, Sendable, Equatable, CustomStringConvertible {
        /// D1 — the refusal the reference does not make.
        case unrecognisedShape(path: String)
        case unparseable(path: String, reason: String)
        case writeFailed(path: String, reason: String)

        public var description: String {
            switch self {
            case let .unrecognisedShape(path):
                // Names the file, says what did and did not happen, gives the fix, blames nobody.
                "\(path) has no \"mcpServers\" object, so adding a server would overwrite the ones "
                    + "already there. Wrap them in \"mcpServers\": { … } and try again. Nothing was "
                    + "changed."
            case let .unparseable(path, reason):
                "\(path) is not valid JSON (\(reason)). Nothing was changed."
            case let .writeFailed(path, reason):
                "\(path) could not be written (\(reason)). Nothing was changed."
            }
        }
    }

    /// Read `servers.json`, apply a change, write it back atomically.
    ///
    /// **This refuses where the reference destroys (divergence D1).** The reference does
    /// `raw.mcpServers ??= {}`, so adding one server to a *flat* `servers.json` — the shape R1
    /// recorded as its trap — creates an empty `mcpServers`, writes it back, and silently discards
    /// every server the file declared. R1 was mandated to reject that shape on read; writing over it
    /// is strictly worse, because the data is gone rather than merely unreported.
    ///
    /// Everything else is the reference, byte for byte: unrelated top-level members are preserved in
    /// place, the mutator works on the ordered members in place and its return value is ignored, the
    /// output is two-space indented with **no trailing newline**, and the commit is a `0600`
    /// temporary file renamed over the destination (B31).
    ///
    /// **R2-W adds the lock (X2).** The whole read-modify-write happens under
    /// ``ConfigMutationLock``, because the config watcher is a second process writing this same file
    /// and a lock only one of them takes excludes nothing. The bound is deliberately short: this
    /// runs synchronously inside the daemon's async control handlers, so a long wait parks a
    /// cooperative-pool thread. Nothing about the output, the preserved members or the error cases
    /// changed with it.
    public static func edit(
        path: String,
        fileSystem: any FileSystem & FileModeWriting,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        lockTimeoutMs: Int = ConfigMutationLock.timeoutMilliseconds(
            default: ConfigMutationLock.daemonTimeoutMs
        ),
        _ mutate: (inout [JSONMember]) throws -> Void
    ) throws {
        try ConfigMutationLock.withExclusiveLock(forConfigAt: path, timeoutMs: lockTimeoutMs) {
            try editLocked(
                path: path, fileSystem: fileSystem,
                processIdentifier: processIdentifier, mutate
            )
        }
    }

    /// The body of ``edit(path:fileSystem:processIdentifier:lockTimeoutMs:_:)``, with the lock
    /// already held. Separate so the watcher — which holds the lock across a wider critical section
    /// than one edit — can reuse the mutation without re-entering the lock.
    static func editLocked(
        path: String,
        fileSystem: any FileSystem & FileModeWriting,
        processIdentifier: Int32,
        _ mutate: (inout [JSONMember]) throws -> Void
    ) throws {
        var root: [JSONMember] = []
        if fileSystem.fileExists(atPath: path) {
            let data = try fileSystem.readFile(atPath: path)
            let parsed: JSONValue
            do {
                parsed = try JSONParser.parse(data)
            } catch {
                throw Problem.unparseable(path: path, reason: "\(error)")
            }
            guard let members = parsed.asObjectMembers else {
                throw Problem.unrecognisedShape(path: path)
            }
            root = members
        }

        let key = JSString("mcpServers")
        let existing = root.first { $0.key == key }?.value
        var servers: [JSONMember]
        switch existing {
        case let .some(.object(members)):
            servers = members
        case .none, .some(.null):
            // Absent or null is the ordinary first-run case: `??=` creates the object. A file with
            // no `mcpServers` **and** other top-level members is the trap, and is refused above
            // only when it is not an object at all — so distinguish the two.
            guard root.isEmpty || existing != nil || !declaresServersAtTopLevel(root) else {
                throw Problem.unrecognisedShape(path: path)
            }
            servers = []
        default:
            // Present but not an object — a string, number, array or boolean. The reference's `??=`
            // leaves it alone and then indexes it, which produces nonsense rather than an error.
            throw Problem.unrecognisedShape(path: path)
        }

        try mutate(&servers)

        if let index = root.firstIndex(where: { $0.key == key }) {
            root[index] = JSONMember(key: key, value: .object(servers))
        } else {
            root.append(JSONMember(key: key, value: .object(servers)))
        }

        let bytes = Data(JSStringify.prettyTwoSpace(.object(root)).utf8)
        let temporary = "\(path).tmp-\(processIdentifier)"
        do {
            // `writeFileSync(tmp, …, { mode: 0o600 })` (`src/control.ts:95`), and B31 names the mode
            // as part of the byte contract. The mode travels with the rename, so writing the
            // temporary through the mode-less overload left `servers.json` at the umask default —
            // typically `0644` — on a file that holds every server's `env`, which is where API keys
            // live. `B10` keeps those values off the wire; this keeps them off other accounts.
            try fileSystem.writeFile(bytes, atPath: temporary, mode: Self.configMode)
            try fileSystem.moveItem(atPath: temporary, toPath: path)
        } catch {
            throw Problem.writeFailed(path: path, reason: "\(error)")
        }
    }

    /// The trap's signature: a top level whose members look like server declarations rather than
    /// like a config. A flat file is one whose members are objects carrying `command` or `url` —
    /// exactly what a user gets by copying the inside of `mcpServers` to the top level.
    ///
    /// Deliberately narrow. A config that merely lacks `mcpServers` and declares nothing else is a
    /// legitimate empty config and must still be writable, or a first run could never add a server.
    ///
    /// Internal rather than private so the config watcher's own writer applies the same test. It
    /// writes different bytes from this one (X2a), but "what does a flat file look like" must have
    /// exactly one answer across the three processes that write this file.
    static func declaresServersAtTopLevel(_ members: [JSONMember]) -> Bool {
        guard !members.isEmpty else { return false }
        return members.contains { member in
            guard let inner = member.value.asObjectMembers else { return false }
            return inner.contains { $0.key == JSString("command") || $0.key == JSString("url") }
        }
    }

    /// Re-read `servers.json` into the live maps so the pool sees the change.
    ///
    /// **Divergence D2**: an unrecognisable or unparseable config is an error here, where the
    /// reference loads zero upstreams silently. It runs immediately after a write, and a reload
    /// that yields nothing presents to every surface as "you have no servers".
    ///
    /// The order is the reference's and is observable: the complete next list is built **before**
    /// anything live is touched, so a parse failure mid-way leaves the running router exactly as it
    /// was rather than half-updated (B31, S7).
    public static func reload(
        path: String,
        fileSystem: any FileSystem
    ) throws -> [(name: JSString, upstream: UpstreamConfig)] {
        let data = try fileSystem.readFile(atPath: path)
        let parsed: JSONValue
        do {
            parsed = try JSONParser.parse(data)
        } catch {
            throw Problem.unparseable(path: path, reason: "\(error)")
        }
        guard let root = parsed.asObjectMembers else {
            throw Problem.unrecognisedShape(path: path)
        }
        let key = JSString("mcpServers")
        guard let servers = root.first(where: { $0.key == key })?.value else {
            throw Problem.unrecognisedShape(path: path)
        }
        guard let entries = servers.asObjectMembers else {
            throw Problem.unrecognisedShape(path: path)
        }

        var next: [(name: JSString, upstream: UpstreamConfig)] = []
        for entry in entries {
            // A rejected server is skipped silently here, exactly as the reference does — the
            // skipped-with-reason list belongs to `loadConfig`, not to a reload.
            if case let .upstream(upstream) = ServerParser.parse(
                name: entry.key.string, raw: entry.value
            ) {
                next.append((entry.key, upstream))
            }
        }
        return next
    }
}
