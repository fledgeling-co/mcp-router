import Foundation

/// W4 — back up before writing, write temp-plus-rename, preserve the mode, keep ten.
///
/// `~/.claude.json` is ~268 KB and holds live session state for every project on the machine. The
/// two rules that follow from that are the reference's and are not negotiable here: never truncate
/// in place, and never write anything derived from a parse that failed.
///
/// The mode is read from the destination and re-applied, rather than assumed. `~/.claude.json` is
/// `0600` on some machines and `0644` on others; writing it back at a fixed mode would either widen
/// a file the user narrowed or narrow one their tooling expects to read.
public enum WatchBackup {
    /// How many copies of each file are kept. The reference's `KEEP_BACKUPS`.
    public static let keep = 10

    /// Copy `path` aside into the backup directory, then prune. Never throws: a failed backup of a
    /// file we are about to rewrite is worth logging, and the reference treats pruning as
    /// housekeeping that must not fail a run.
    @discardableResult
    public static func backUp(
        path: String,
        into directory: String,
        fileSystem: any FileSystem,
        nowMilliseconds: Double
    ) -> String? {
        guard fileSystem.fileExists(atPath: path) else { return nil }
        try? fileSystem.createDirectory(atPath: directory)
        let base = (path as NSString).lastPathComponent
        let destination = (directory as NSString)
            .appendingPathComponent("\(base).\(stamp(nowMilliseconds))")
        guard (try? fileSystem.copyItem(atPath: path, toPath: destination)) != nil else {
            return nil
        }
        prune(prefix: base, in: directory, fileSystem: fileSystem)
        return destination
    }

    /// `readdir().filter(startsWith).sort()`, then drop all but the newest ten. The stamp sorts
    /// lexicographically because it is fixed-width and most-significant-first.
    static func prune(prefix: String, in directory: String, fileSystem: any FileSystem) {
        guard let entries = try? fileSystem.contentsOfDirectory(atPath: directory) else { return }
        let mine = entries.filter { $0.hasPrefix("\(prefix).") }.sorted()
        guard mine.count > keep else { return }
        for stale in mine.prefix(mine.count - keep) {
            try? fileSystem.removeItem(
                atPath: (directory as NSString).appendingPathComponent(stale)
            )
        }
    }

    /// Which mode a write lands at. One value rather than a mode plus a flag, because the two are
    /// only ever meaningful together and a caller that read one without the other would write
    /// `~/.claude.json` at a fixed mode or `servers.json` at whatever it happened to have.
    public enum ModeRule: Sendable, Equatable {
        /// `servers.json` — `writeAtomic(…, 0o644)` at `watch.ts:282`.
        case fixed(UInt16)
        /// `~/.claude.json` — `statSync(CLAUDE_JSON).mode & 0o777` at `watch.ts:328`.
        ///
        /// There is deliberately **no fallback**. That `statSync` runs immediately before the write
        /// and throws when the path has gone, which is the whole of what stops the reference
        /// rebuilding a staging file deleted during the run. A default mode here would turn that
        /// throw into a successful write, recreating ~268 KB of session state the user had just
        /// discarded — and the window is real, because the file is re-read seconds earlier.
        case preserveExisting

        func resolve(path: String, fileSystem: any FileModeWriting) throws -> UInt16 {
            switch self {
            case let .fixed(mode): mode
            case .preserveExisting: try fileSystem.fileMode(atPath: path)
            }
        }
    }

    /// Write `contents` to `path` atomically.
    ///
    /// The temporary lands in the same directory so the rename stays within one filesystem — a
    /// rename across devices is not atomic and is not even a rename.
    public static func writeAtomic(
        _ contents: String,
        toPath path: String,
        fileSystem: any FileSystem & FileModeWriting,
        processIdentifier: Int32,
        mode rule: ModeRule
    ) throws {
        let mode = try rule.resolve(path: path, fileSystem: fileSystem)
        let temporary = "\(path).mcpr-tmp-\(processIdentifier)"
        try fileSystem.writeFile(Data(contents.utf8), atPath: temporary, mode: mode)
        try fileSystem.moveItem(atPath: temporary, toPath: path)
    }

    /// `new Date().toISOString().replace(/[:.]/g, '-')`.
    static func stamp(_ milliseconds: Double) -> String {
        JSDate.iso8601(milliseconds: milliseconds)
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }
}
