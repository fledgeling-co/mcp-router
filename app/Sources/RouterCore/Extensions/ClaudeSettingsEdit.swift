import Foundation

/// Editing `~/.claude/settings.json` and touching **only** the two members R30 owns.
///
/// That file holds `env`, `permissions`, `hooks`, `model` and `statusLine` for every project on the
/// machine — 22 top-level members when this was written — and a rewrite that dropped one it did not
/// understand would be worse than the drift this item exists to fix. So this never builds a new
/// document. It parses the existing one into ``JSONMember``s, deletes named keys out of
/// `enabledPlugins` and `extraKnownMarketplaces`, and writes the same array back: **every other
/// member keeps its value and its position**, and the containers themselves keep theirs.
///
/// Four rules make that a property rather than an intention:
///
///  1. **A parse failure writes nothing.** `WatchBackup`'s rule — never write anything derived from
///     a parse that failed — applied to a file with more in it than `~/.claude.json` has.
///  2. **Nothing to remove writes nothing.** A no-op run leaves the file byte-identical, so
///     `mcp-router ingest` cannot reformat a file it had no business changing.
///  3. **The file is stamped before the read and again before the write**, and a change in between
///     aborts. Claude writes this file too; a lock cannot stop it, and a read-modify-write that
///     ignored the window would silently discard whatever it wrote in that second.
///  4. **A backup is taken first**, into the same rotation `~/.claude.json` already uses.
public enum ClaudeSettingsEdit {
    /// Where a write lands and under what rules — one value rather than four parameters that are
    /// only meaningful together.
    ///
    /// The seam ``ImportConfigWriter/Destination`` already established in this repository, for the
    /// same reason: a caller that read the path without the backup directory, or the clock without
    /// the process identifier the temporary file is named for, is describing half a destination.
    public struct Destination: Sendable {
        public let path: String
        public let backupDirectory: String
        public let processIdentifier: Int32
        public let nowMilliseconds: Double

        public init(
            path: String,
            backupDirectory: String,
            processIdentifier: Int32,
            nowMilliseconds: Double
        ) {
            self.path = path
            self.backupDirectory = backupDirectory
            self.processIdentifier = processIdentifier
            self.nowMilliseconds = nowMilliseconds
        }
    }

    /// One key, in one of the two containers.
    public struct KeyRemoval: Sendable, Hashable {
        public let container: String
        public let key: String

        public init(container: String, key: String) {
            self.container = container
            self.key = key
        }
    }

    /// A key that was removed, with everything an undo needs to put it back exactly.
    ///
    /// The value is carried as its compact JSON text rather than as a parsed value, because it has
    /// to survive a round trip through the run manifest on disk. `enabledPlugins` holds booleans and
    /// `extraKnownMarketplaces` holds objects, so a restore that assumed either shape would rebuild
    /// half the entries wrong.
    public struct RemovedKey: Sendable, Hashable {
        public let container: String
        public let key: String
        public let valueJSON: String
        /// Where it sat inside its container, so a restore puts it back rather than appending it.
        public let index: Int

        public init(container: String, key: String, valueJSON: String, index: Int) {
            self.container = container
            self.key = key
            self.valueJSON = valueJSON
            self.index = index
        }
    }

    public struct Result: Sendable {
        public let removed: [RemovedKey]
        /// Asked for and not there. Not an error: a plugin installed but never enabled has no
        /// `enabledPlugins` key, and 7 of the 127 installed on this machine were in that state.
        public let absent: [KeyRemoval]
        /// Top-level members before and after. Equal on every run this type is allowed to make, and
        /// the caller asserts it rather than trusting this sentence.
        public let topLevelBefore: Int
        public let topLevelAfter: Int
        public let backupPath: String?
        public let wrote: Bool
    }

    public enum Failure: Error, CustomStringConvertible {
        case unparsable(String)
        case notAnObject(String)
        case containerNotAnObject(String)
        case changedUnderfoot(String)
        case writeFailed(String)

        public var description: String {
            switch self {
            case let .unparsable(path): "\(path) is not valid JSON, so nothing was changed"
            case let .notAnObject(path): "\(path) is not a JSON object, so nothing was changed"
            case let .containerNotAnObject(name):
                "settings.json's \(name) is not an object, so nothing was changed"
            case let .changedUnderfoot(path):
                "\(path) changed while it was being edited, so nothing was written"
            case let .writeFailed(message): message
            }
        }
    }
}
