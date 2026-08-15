import Foundation

/// `mcp-router import`'s `servers.json` writer — the **third** writer of that file, and the
/// differences between the three are load-bearing rather than incidental.
///
/// | writer | stringify | mode | lock |
/// |---|---|---|---|
/// | ``ConfigEdit`` (daemon) | `prettyTwoSpace`, no trailing newline | temp at `.fixed(0o600)` + rename, so
/// **always** 0600 | yes |
/// | ``WatchAdoption`` (watcher) | `prettyTwoSpace` **+ `"\n"`** | `.fixed(0o644)` | yes |
/// | this one | `prettyTwoSpace`, no trailing newline | **0600 only when the file does not exist** | yes |
///
/// It implements `spec-R1.md`'s declared divergence **D3** on the path D3 was written about: the
/// reference's writer lives in `src/index.ts`, writes four keys, non-atomically, and drops every
/// other top-level key. Swift's is atomic and preserves them, because a truncated write produces
/// exactly the unrecognisable shape D1 exists to reject, and because dropping `startupTimeoutMs`
/// on a rewrite silently resets a setting the user configured.
public enum ImportConfigWriter {
    /// Where the write lands, and under what rules.
    ///
    /// One value rather than three parameters that are only meaningful together, which is the seam
    /// ``WatchAdoption/Destination`` already established in this repo for the same reason: a caller
    /// that read the path without the lock timeout, or the timeout without the process identifier
    /// the temporary file is named for, is describing half a destination.
    public struct Destination: Sendable {
        public let path: String
        public let processIdentifier: Int32
        public let lockTimeoutMs: Int

        public init(path: String, processIdentifier: Int32, lockTimeoutMs: Int) {
            self.path = path
            self.processIdentifier = processIdentifier
            self.lockTimeoutMs = lockTimeoutMs
        }
    }

    /// Write the adopted set, preserving whatever else the destination declared.
    ///
    /// **The lock spans the read as well as the write.** `WatchAdoption` documents why (X3): the
    /// object the delta is applied to has to be the one currently on disk. Reading outside and
    /// writing inside would let a control-API PATCH landing in the window be clobbered, and the
    /// "preserved" keys would have been preserved from a stale snapshot.
    public static func write(
        adopted: [JSONMember],
        port: Int,
        to destination: Destination,
        fileSystem: any FileSystem & FileModeWriting
    ) throws {
        let path = destination.path
        try ConfigMutationLock.withExclusiveLock(
            forConfigAt: path, timeoutMs: destination.lockTimeoutMs
        ) {
            // Resolved before the write and inside the lock, so it describes the file the rename is
            // about to replace.
            let existed = fileSystem.fileExists(atPath: path)
            let root = merged(
                into: existingMembers(at: path, fileSystem: fileSystem),
                adopted: adopted,
                port: port
            )

            // The one line where two obvious alternatives are both wrong, in opposite directions.
            //
            // The reference passes `{ mode: 0o600 }` to an IN-PLACE `writeFileSync`
            // (`src/index.ts:141`), and node applies that mode only when the file is CREATED.
            // Measured 2026-08-15: in-place over an existing 0644 file leaves 0644; a temp written
            // at 0600 and renamed over the same file yields 0600.
            //
            // So `.fixed(0o600)` unconditionally is wrong — `writeAtomic` always writes a new
            // inode, so it would narrow every existing 0644 config, and that file holds every
            // server's `env`. And `fileSystem.writeFile(path, mode:)` is wrong the same way:
            // `FileModeWriting` fchmods unconditionally and deliberately. Neither may be used bare.
            let mode: WatchBackup.ModeRule = existed ? .preserveExisting : .fixed(configCreateMode)

            // No trailing newline. `JSON.stringify` emits none; `WatchAdoption` appends one under
            // the WATCHER's rules (`watch.ts:282`), and copying that here would change bytes
            // `cli-import` compares.
            try WatchBackup.writeAtomic(
                JSStringify.prettyTwoSpace(.object(root)),
                toPath: path,
                fileSystem: fileSystem,
                processIdentifier: destination.processIdentifier,
                mode: mode
            )
        }
    }

    /// `writeFileSync(DEFAULT_CONFIG_PATH, …, { mode: 0o600 })` — applied on create only.
    static let configCreateMode: UInt16 = 0o600

    /// What the destination already declared, or nothing.
    ///
    /// A parse failure is **not** an error here, and that is deliberate: the reference overwrites
    /// unconditionally, so throwing would wedge an import the user cannot escape — the one command
    /// whose whole job is to rebuild this file.
    static func existingMembers(
        at path: String, fileSystem: any FileSystem
    ) -> [JSONMember] {
        guard fileSystem.fileExists(atPath: path),
              let data = try? fileSystem.readFile(atPath: path),
              let parsed = try? JSONParser.parse(data),
              let members = parsed.asObjectMembers
        else { return [] }
        return members
    }

    /// Set the four keys the reference writes; leave every other member where it was.
    ///
    /// Position, not just presence: a rewrite that moved `startupTimeoutMs` to the end would still
    /// "preserve" it while changing the bytes of a file the user reads.
    static func merged(
        into existing: [JSONMember], adopted: [JSONMember], port: Int
    ) -> [JSONMember] {
        var root = existing
        // Written in the reference's own order, so a file that had none of them comes out
        // byte-identical to the four-key document `JSON.stringify` produces.
        set(&root, "port", .number(Double(port)))
        set(&root, "host", .string(JSString(RouterHome.defaultHost)))
        set(&root, "idleMs", .number(Double(RouterHome.defaultIdleMs)))
        set(&root, "mcpServers", .object(adopted))
        return root
    }

    private static func set(_ members: inout [JSONMember], _ key: String, _ value: JSONValue) {
        let name = JSString(key)
        let member = JSONMember(key: name, value: value)
        if let index = members.firstIndex(where: { $0.key == name }) {
            members[index] = member
        } else {
            members.append(member)
        }
    }
}
