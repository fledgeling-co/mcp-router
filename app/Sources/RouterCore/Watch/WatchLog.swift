import Foundation

/// `watch.log` — the only account of a process that runs unattended, rewrites the user's own
/// config, and is invisible when it works.
///
/// Every string is a case here rather than a literal at its call site, so the set is asserted as a
/// set. They are carried **verbatim** from the reference unless marked new: `spec-R2W.md`'s copy
/// table is normative, and a rewording would make R4 report a difference that is only a rewording.
///
/// **A logging failure is never the reason a run fails** (`watch.ts:73-80`). The append is
/// best-effort and its error is dropped — which is the one place in this repo where swallowing an
/// error is right, because the alternative is a watcher that stops adopting servers when a disk
/// fills.
public enum WatchLogEvent: Sendable, Equatable {
    case configDidNotParse(reason: String)
    case skipped(name: String, reason: String)
    case noRouterConfig(path: String)
    case indexFailed(entry: String)
    case adopted(entry: String)
    case reReadDidNotParse(names: [String], reason: String)
    case changedWhileIndexing(name: String)
    case removedFromStaging(names: [String])
    case stillPending(names: [String])
    case restarted(label: String)
    case restartFailed(label: String, reason: String)
    /// New — the reference neither owes a restart nor retries one.
    case retryingOwedRestart
    /// New — the reference writes over a flat config and discards what it declared (W-D7).
    case flatRouterConfig(path: String)

    public var message: String {
        switch self {
        case let .configDidNotParse(reason):
            "~/.claude.json did not parse (\(reason)); abandoned, nothing written"
        case let .skipped(name, reason):
            "skipped \"\(name)\": \(reason)"
        case let .noRouterConfig(path):
            "no router config at \(path); adoption skipped"
        case let .indexFailed(entry):
            "failed to index \"\(entry)\"; left in ~/.claude.json, will retry"
        case let .adopted(entry):
            "adopted \(entry) from ~/.claude.json"
        case let .reReadDidNotParse(names, reason):
            "indexed \(names.joined(separator: ", ")) but ~/.claude.json no longer parses "
                + "(\(reason)); left it untouched, will retry"
        case let .changedWhileIndexing(name):
            "\"\(name)\" changed in ~/.claude.json while it was being indexed; "
                + "left it there for the next fire"
        case let .removedFromStaging(names):
            "removed \(names.count) adopted stdio entr\(names.count == 1 ? "y" : "ies") "
                + "from ~/.claude.json: \(names.joined(separator: ", "))"
        case let .stillPending(names):
            "still pending (not adopted): \(names.joined(separator: ", "))"
        case let .restarted(label):
            "restarted \(label) to pick up the new upstream"
        case let .restartFailed(label, reason):
            "could not restart \(label) (\(reason)); run it manually"
        case .retryingOwedRestart:
            "retrying a restart owed from an earlier fire"
        case let .flatRouterConfig(path):
            "\(path) has no \"mcpServers\" object, so adopting into it would overwrite the servers "
                + "already there. Nothing was changed."
        }
    }
}

/// Appends `<ISO8601> <message>` lines to `watch.log`.
public struct WatchLog: Sendable {
    let path: String
    let fileSystem: any FileSystem
    let clock: any RouterClock

    public init(
        path: String,
        fileSystem: any FileSystem = RealFileSystem(),
        clock: any RouterClock = SystemClock()
    ) {
        self.path = path
        self.fileSystem = fileSystem
        self.clock = clock
    }

    public func record(_ event: WatchLogEvent) {
        try? fileSystem.createDirectory(atPath: (path as NSString).deletingLastPathComponent)
        let line = "\(JSDate.iso8601(milliseconds: clock.nowMilliseconds)) \(event.message)\n"
        // `catch { /* logging must never be the reason this fails */ }`.
        try? fileSystem.appendFile(Data(line.utf8), atPath: path)
    }
}
