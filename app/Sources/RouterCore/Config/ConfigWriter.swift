import Foundation

/// Writes the server list.
///
/// Two deliberate departures from the reference, both recorded in the spec's divergence register:
///
/// - **The write is atomic.** The reference writes in place, and a truncated write leaves exactly
///   the unrecognisable shape this whole item exists to reject.
/// - **Top-level keys it did not set are preserved.** The reference's writer emits four keys, so a
///   read/modify/write cycle silently resets `startupTimeoutMs` — and anything else a user has
///   hand-added — to its default.
public enum ConfigWriter {
    public enum WriteProblem: Error, Sendable, Equatable, CustomStringConvertible {
        case backupFailed(path: String, reason: String)
        case writeFailed(path: String, reason: String)

        public var description: String {
            switch self {
            case let .backupFailed(path, reason):
                "Could not back up the existing server list to \(path) (\(reason)). "
                    + "Nothing was written — the current list is unchanged."
            case let .writeFailed(path, reason):
                "Could not write the server list to \(path) (\(reason))."
            }
        }
    }

    public static let backupsKept = 5

    /// Writes `servers.json`, preserving anything already in it that is not being replaced.
    public static func write(
        servers: [JSONMember],
        port: Int,
        host: String,
        idleMs: Int,
        toPath path: String,
        fileSystem: FileSystem = RealFileSystem(),
        now: Date = Date()
    ) throws {
        let directory = (path as NSString).deletingLastPathComponent
        do {
            try fileSystem.createDirectory(atPath: directory)
        } catch {
            throw WriteProblem.writeFailed(path: path, reason: error.localizedDescription)
        }

        var members: [JSONMember] = []
        if let existingMembers = existingTopLevel(path: path, fileSystem: fileSystem) {
            members = existingMembers
            try backUp(path: path, fileSystem: fileSystem, now: now)
        }

        // Losing a setting the user typed is worse than the tidiness of a fixed key set, so
        // anything already present and not being replaced survives.
        set(&members, "port", .number(Double(port)))
        set(&members, "host", .string(JSString(host)))
        set(&members, "idleMs", .number(Double(idleMs)))
        set(&members, "mcpServers", .object(servers))

        let text = JSStringify.prettyTwoSpace(.object(members))
        let temporary = "\(path).tmp-\(ProcessInfo.processInfo.processIdentifier)"
        do {
            try fileSystem.writeFile(Data(text.utf8), atPath: temporary)
            try fileSystem.moveItem(atPath: temporary, toPath: path)
        } catch {
            throw WriteProblem.writeFailed(path: path, reason: error.localizedDescription)
        }
    }

    /// The top-level members already in the file, when there is a readable object there.
    private static func existingTopLevel(path: String, fileSystem: FileSystem) -> [JSONMember]? {
        guard fileSystem.fileExists(atPath: path),
              let existing = try? fileSystem.readFile(atPath: path),
              let parsed = try? JSONParser.parse(existing),
              case let .object(members) = parsed
        else { return nil }
        return members
    }

    /// Copies the current file aside before it is replaced, keeping the most recent few.
    ///
    /// A failed backup **stops the write**. Losing the old list in order to save the new one is the
    /// wrong trade for a file people hand-edit.
    private static func backUp(path: String, fileSystem: FileSystem, now: Date) throws {
        let stamp = Self.stampFormatter.string(from: now)
        let backup = "\(path).bak-\(stamp)"
        do {
            try fileSystem.copyItem(atPath: path, toPath: backup)
        } catch {
            throw WriteProblem.backupFailed(path: backup, reason: error.localizedDescription)
        }

        let directory = (path as NSString).deletingLastPathComponent
        let base = (path as NSString).lastPathComponent
        guard let entries = try? fileSystem.contentsOfDirectory(atPath: directory) else { return }
        let backups = entries.filter { $0.hasPrefix("\(base).bak-") }.sorted()
        guard backups.count > backupsKept else { return }
        for stale in backups.prefix(backups.count - backupsKept) {
            try? fileSystem.removeItem(atPath: (directory as NSString).appendingPathComponent(stale))
        }
    }

    private static func set(_ members: inout [JSONMember], _ key: String, _ value: JSONValue) {
        let target = JSString(key)
        if let index = members.firstIndex(where: { $0.key == target }) {
            members[index] = JSONMember(key: target, value: value)
        } else {
            members.append(JSONMember(key: target, value: value))
        }
    }

    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
