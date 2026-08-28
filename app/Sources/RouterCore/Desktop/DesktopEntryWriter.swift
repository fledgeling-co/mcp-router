import Foundation

/// The half of R32 that touches a file, kept apart from the half that decides what to write.
///
/// **This is a declared harness-config writer.** `scripts/lint/no-harness-config-writes.sh` names
/// it in `HARNESS_WRITERS`, beside ``ClaudeStagingEntry``, and refuses any *other* file that both
/// writes and speaks the harness vocabulary. Splitting the write out of ``DesktopEntry`` is what
/// makes that declaration meaningful rather than a comment: the planning, the schema check and the
/// diff are exercised with no filesystem at all, and everything that can damage a file is in this
/// one small type.
///
/// It is reached only from a command a person types, and only with `--apply`. There is no caller
/// inside the daemon, the watcher or the control API, and there is no code path that reaches it
/// from a fleet runner: the item's rule is that the owner performs the change, and the mechanism
/// for that is that nothing else knows how to.
public enum DesktopEntryWriter {
    /// What an apply did, in the terms a caller has to print.
    public struct Applied: Sendable, Equatable {
        public let backup: String
        public let bytesBefore: Int
        public let bytesAfter: Int
        /// The mode carried over from the file that was there. Reported rather than assumed: the
        /// file this was measured against is `0600`, and a writer that silently widened it would
        /// hand every process on the machine a config that names the user's local endpoints.
        public let mode: UInt16
    }

    /// Back up, then replace, in that order.
    ///
    /// The order is ``ClaudeStagingEntry/apply(atPath:port:fileSystem:processIdentifier:now:)``'s and
    /// it is load-bearing for the same reason: a backup taken after a failed parse is a copy of
    /// something already suspect, and a backup not taken at all leaves an unrecoverable overwrite.
    /// Here the parse has already happened — the caller cannot produce `document` without it — so
    /// what this order protects against is the write failing halfway.
    ///
    /// The write itself is ``WatchBackup/writeAtomic(_:toPath:fileSystem:processIdentifier:mode:)``
    /// at `.preserveExisting`: a temporary in the same directory and a rename, so a Claude Desktop
    /// that reads the file during the run sees either the old bytes or the new ones and never a
    /// half-written document.
    public static func apply(
        document: String,
        toPath path: String,
        fileSystem: any FileSystem & FileModeWriting,
        processIdentifier: Int32,
        now: Date
    ) throws -> Applied {
        let before = try fileSystem.readFile(atPath: path)
        let mode = try fileSystem.fileMode(atPath: path)
        let backup = "\(path).bak-mcp-router-\(stamp(now))"
        try fileSystem.copyItem(atPath: path, toPath: backup)
        try WatchBackup.writeAtomic(
            document,
            toPath: path,
            fileSystem: fileSystem,
            processIdentifier: processIdentifier,
            mode: .preserveExisting
        )
        return Applied(
            backup: backup,
            bytesBefore: before.count,
            bytesAfter: Data(document.utf8).count,
            mode: mode
        )
    }

    /// `date +%Y%m%d-%H%M%S`, local time — the same stamp ``ClaudeStagingEntry`` leaves, so the two
    /// clients' backups sort together and read as one convention rather than two.
    static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
}
