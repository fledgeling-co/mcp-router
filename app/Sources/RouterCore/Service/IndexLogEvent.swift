import Foundation

/// What indexing logs that is neither R1's `LogEvent` nor the serving process's.
///
/// Its own type rather than a case on either, following the extension point `RouterLog.swift`
/// declares: items add their lines without editing one shared enum, and the closed set is what
/// makes it structurally impossible to log a token — the only associated values here are a server
/// name, a path and a failure reason.
///
/// Kept off `LogEvent` for a second reason. Every string on that enum is the reference's, to the
/// character, and `parity-log.sh` diffs them; this line has no counterpart there, because the
/// reference's `saveManifest` throws and takes the whole verb down instead of writing anything.
public enum IndexLogEvent: Sendable, Hashable, LoggableEvent {
    /// This run's manifest row for a server did not reach disk. DEF-049.
    ///
    /// It covers both arms: the row a successful index produced, and the failure row the catch arm
    /// writes for an upstream that would not start. The wording therefore says what was lost rather
    /// than what produced it — "indexed X but could not write" would be false of the second.
    case manifestNotWritten(server: String, path: String, reason: String)

    public var level: RouterLog.Level {
        switch self {
        case .manifestNotWritten: .error
        }
    }

    public var message: String {
        switch self {
        case let .manifestNotWritten(server, path, reason):
            "the manifest row for \"\(server)\" did not reach \(path) (\(reason)); "
                + "nothing this run read from it is cached — check that directory's permissions "
                + "and run `mcp-router index --force` again"
        }
    }
}
