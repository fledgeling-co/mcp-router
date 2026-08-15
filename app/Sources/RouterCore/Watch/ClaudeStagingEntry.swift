import Foundation

/// The router's own entry in `~/.claude.json` — `docs/install.sh:162-188`, in Swift.
///
/// This is the step that actually points Claude Code at the router. The reference performs it
/// inline in the installer through a `node -e` script, so it is a verb of no binary; **R4-C removes
/// Node from the installer entirely** (`spec-R4.md`: `swift build`, drop the Node 20 check, delete
/// `package.json`), which is why the capability has to exist here. `install-claude-json`.
///
/// **There is deliberately no ``ConfigMutationLock`` here (`D-p2-a`).** R2-W's sidecar flock is
/// used where it excludes something — ``ImportConfigWriter`` takes it on `servers.json`, which has
/// three writers. On this file it would exclude nothing: Claude Code rewrites `~/.claude.json`
/// constantly and will never take an advisory lock of ours, the Swift watcher's own staging rewrite
/// is unlocked by V1's deliberate decision (`D-v1f`, R4's call), and nothing under `MCPRouterUI` or
/// `MCPRouterKit` writes the file at all — verified, not assumed. What it *would* do is leave a
/// permanent `~/.claude.json.lock` in the user's home next to ~268 KB of live session state. The
/// temp-plus-rename below is what actually protects a concurrent writer.
public enum ClaudeStagingEntry {
    /// The entry the installer adds.
    public static let entryName = "mcp-router"
    /// Earlier installs called it this. Dropped on upgrade, but only when it points at the same
    /// endpoint — two entries on one url would double every tool in the list.
    public static let legacyEntryName = "router"

    public static func url(port: Int) -> String {
        "http://127.0.0.1:\(port)/mcp"
    }

    public enum Outcome: Sendable, Equatable {
        /// `install.sh` guards with `[[ -f "$CLAUDE_JSON" ]]` and skips the node call, so an absent
        /// staging file is a success that writes nothing rather than an error.
        case noStagingFile
        /// `addedEntry` is false when the root was not an object: the property write is a no-op in
        /// JavaScript, the file is still re-stringified and copied, and nothing gained an entry.
        /// Carried out of here so no caller has to guess, and so nothing can print that the router
        /// entry was added to a document that has no properties.
        case rewritten(backup: String, addedEntry: Bool)
    }

    public enum Problem: Error, Sendable, Equatable, CustomStringConvertible {
        case unparseable(path: String, reason: String)
        case nullDocument(path: String)

        public var description: String {
            switch self {
            case let .unparseable(path, reason):
                "\(path) is not valid JSON (\(reason)). Nothing was changed."
            case let .nullDocument(path):
                // `d.mcpServers = …` on `null` throws `Cannot set properties of null` in node, and
                // install.sh inherits the failure. Reproduced rather than "handled".
                "\(path) contains only `null`, so there is nothing to add the router entry to."
            }
        }
    }

    /// The rewritten document. Pure, total, and **never optional**.
    ///
    /// Node does `JSON.parse` → mutate → `JSON.stringify(d, null, 2)` on whatever the root is, every
    /// time the file exists. An optional return would let a no-op re-run keep the file's original
    /// whitespace and skip the backup, where the reference always re-stringifies and always copies.
    ///
    /// The falsy/truthy distinction is JavaScript's, not a simplification of it:
    /// `d.mcpServers = d.mcpServers || {}` replaces `undefined`, `null`, `0`, `false` and `""`, but
    /// **not `[]`** — an empty array is truthy, survives the `||`, and then loses the named property
    /// in `JSON.stringify`. A rule of "any non-object becomes an object" would diverge on exactly
    /// that input.
    public static func rewritten(_ root: JSONValue, port: Int) -> JSONValue {
        // A non-object root has no properties to set: the assignment is a silent no-op in
        // JavaScript and stringify emits the value unchanged.
        guard var members = root.asObjectMembers else { return root }

        let key = JSString("mcpServers")
        let existing = members.first { $0.key == key }?.value
        // `|| {}` — only a falsy value is replaced.
        let servers: JSONValue = (existing?.isTruthy ?? false) ? (existing ?? .object([])) : .object([])

        guard case var .object(entries) = servers else {
            // Truthy but not an object: `[]`, a string, a number. Node leaves it exactly as it is.
            set(&members, key, servers)
            return .object(members)
        }

        let newEntry = JSONValue.object([
            JSONMember(key: JSString("type"), value: .string(JSString("http"))),
            JSONMember(key: JSString("url"), value: .string(JSString(url(port: port))))
        ])
        set(&entries, JSString(entryName), newEntry)

        // Conditional, and the false branch matters: a `router` entry pointing somewhere else is
        // someone's own server that happens to share the name.
        if let legacy = entries.first(where: { $0.key == JSString(legacyEntryName) })?.value,
           case let .object(legacyMembers) = legacy,
           case let .string(legacyURL)? = legacyMembers
           .first(where: { $0.key == JSString("url") })?.value,
           legacyURL.string == url(port: port)
        {
            entries.removeAll { $0.key == JSString(legacyEntryName) }
        }

        set(&members, key, .object(entries))
        return .object(members)
    }

    /// The whole installer step: back up, rewrite, write at the file's own mode.
    ///
    /// The backup reproduces `install.sh:162`'s `cp` rather than leaving it to the caller. Folding
    /// it in is what stops this being an undocumented verb that destructively rewrites live session
    /// state with no recovery, and it lets R4-C replace two lines with one; the net on-disk result
    /// is unchanged.
    ///
    /// **Order: copy, then parse — the reference's order, and the opposite of this function's first
    /// version.** `install.sh` runs `cp` at :162 and only reaches `JSON.parse` at :169, so an
    /// unparseable staging file leaves a `.bak-mcp-router-*` behind and the original untouched.
    /// Parsing first felt safer and was a silent divergence: a byte-for-byte copy is not "content
    /// derived from a parse that failed", which is the rule `WatchBackup` states, so there was
    /// nothing to protect and a recovery copy to lose.
    public static func apply(
        atPath path: String,
        port: Int,
        fileSystem: any FileSystem & FileModeWriting,
        processIdentifier: Int32,
        now: Date
    ) throws -> Outcome {
        guard isRegularFile(atPath: path) else { return .noStagingFile }

        let backup = "\(path).bak-mcp-router-\(stamp(now))"
        try fileSystem.copyItem(atPath: path, toPath: backup)

        let data = try fileSystem.readFile(atPath: path)
        let parsed: JSONValue
        do {
            parsed = try JSONParser.parse(data)
        } catch {
            throw Problem.unparseable(path: path, reason: "\(error)")
        }
        if case .null = parsed { throw Problem.nullDocument(path: path) }

        let document = rewritten(parsed, port: port)
        try WatchBackup.writeAtomic(
            JSStringify.prettyTwoSpace(document),
            toPath: path,
            fileSystem: fileSystem,
            processIdentifier: processIdentifier,
            mode: .preserveExisting
        )
        return .rewritten(backup: backup, addedEntry: declaresRouterEntry(document))
    }

    /// `[[ -f "$CLAUDE_JSON" ]]` exactly: a **regular** file, following symlinks.
    ///
    /// Not `FileManager.fileExists`, which is true for a directory where `[[ -f ]]` is false.
    /// A directory at the staging path would otherwise make `readFile` throw "is a directory" and
    /// exit non-zero, where `install.sh` skips the whole step and carries on — and after R4-C, with
    /// the installer under `set -e`, that difference aborts an install the reference completes.
    ///
    /// It does not go through the injected `FileSystem`: that protocol is R1's and shared, it has no
    /// file-type query, and widening a merged protocol for one caller manufactures a conflict for
    /// every runner working in parallel. `stat(2)` is what the shell test compiles to anyway.
    static func isRegularFile(atPath path: String) -> Bool {
        var status = stat()
        guard stat(path, &status) == 0 else { return false }
        return (status.st_mode & S_IFMT) == S_IFREG
    }

    /// Whether the written document actually carries the router entry as an object.
    ///
    /// A non-object root is a no-op for the property write (`rewritten`), so "added the router
    /// entry" would be a false sentence about a file that gained nothing.
    static func declaresRouterEntry(_ document: JSONValue) -> Bool {
        guard case let .object(members) = document,
              case let .object(entries)? = members
              .first(where: { $0.key == JSString("mcpServers") })?.value
        else { return false }
        return entries.contains { $0.key == JSString(entryName) }
    }

    /// `date +%Y%m%d-%H%M%S` — **local** time, which is what the shell produces.
    ///
    /// Not ``WatchBackup/stamp(_:)``: that is `JSDate.iso8601`, which is UTC and a different shape
    /// entirely. Second resolution means two runs inside one second collide; the reference has the
    /// same property and it is not P2's to improve.
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    private static func set(_ members: inout [JSONMember], _ key: JSString, _ value: JSONValue) {
        let member = JSONMember(key: key, value: value)
        if let index = members.firstIndex(where: { $0.key == key }) {
            members[index] = member
        } else {
            members.append(member)
        }
    }
}
