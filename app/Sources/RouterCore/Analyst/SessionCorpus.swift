import Foundation

/// One line of one harness's session log, reduced to the text the analyst reads.
public struct SessionEntry: Sendable, Hashable {
    public let harness: MCPClient
    public let text: String

    public init(harness: MCPClient, text: String) {
        self.harness = harness
        self.text = text
    }
}

/// What one store gave up, including the ones that gave up nothing.
///
/// **Every store this router knows about appears here, read or not.** A store omitted because it
/// was absent, unreadable or of a format this reader does not handle is indistinguishable on the
/// wire from a store that held nothing, and the difference decides whether `linesRead` is a
/// coverage figure or a fraction of one nobody can see the denominator of.
public struct SessionStoreReport: Sendable, Hashable {
    public let harness: MCPClient
    public let path: String
    public let read: Bool
    public let lines: Int
    /// Lines opened and not used, by any cause — blank, unparsable, or carrying no prompt member.
    public let discarded: Int
    /// Why this store contributed nothing, or `nil` when it was read.
    public let reason: String?

    public init(
        harness: MCPClient,
        path: String,
        read: Bool,
        lines: Int,
        discarded: Int,
        reason: String? = nil
    ) {
        self.harness = harness
        self.path = path
        self.read = read
        self.lines = lines
        self.discarded = discarded
        self.reason = reason
    }
}

/// Everything the analyst read, and the accounting for what it did not.
public struct SessionCorpus: Sendable, Hashable {
    public let entries: [SessionEntry]
    public let reports: [SessionStoreReport]

    public init(entries: [SessionEntry], reports: [SessionStoreReport]) {
        self.entries = entries
        self.reports = reports
    }

    /// Lines the reader **parsed**, not lines it opened. The two differ by ``discardedLines`` and
    /// the design's readout is the first, so the second is carried beside it rather than folded in.
    public var linesRead: Int { reports.reduce(0) { $0 + $1.lines } }
    public var discardedLines: Int { reports.reduce(0) { $0 + $1.discarded } }
    public var unreadStores: [SessionStoreReport] { reports.filter { !$0.read } }
}

/// Where each harness keeps its sessions, and in what shape.
public struct SessionStore: Sendable, Hashable {
    public enum Shape: Sendable, Hashable {
        /// One JSON object per line, in one file.
        case jsonLinesFile
        /// A directory of `.jsonl` files.
        case jsonLinesDirectory
        /// Enumerated and never opened. See ``SessionStores/table(homeDirectory:)``.
        case unsupported(String)
    }

    public let harness: MCPClient
    public let path: String
    public let shape: Shape
}

public enum SessionStores {
    /// The table, from `PRD.md` §6.2.
    ///
    /// **Cursor is in the table and is not read.** Its store is SQLite where every other one is
    /// JSONL, so it is a second reader with a second failure surface rather than another path for
    /// the one below; `spec-F7.md` §2 records the deferral. It stays in the table so the wire
    /// reports it unread *with its reason*, which is the only form of that fact a surface can draw.
    public static func table(homeDirectory: String) -> [SessionStore] {
        [
            SessionStore(
                harness: .claudeCode, path: "\(homeDirectory)/.claude/history.jsonl",
                shape: .jsonLinesFile
            ),
            SessionStore(
                harness: .codexCLI, path: "\(homeDirectory)/.codex/history.jsonl",
                shape: .jsonLinesFile
            ),
            SessionStore(
                harness: .grokCLI, path: "\(homeDirectory)/.grok/sessions",
                shape: .jsonLinesDirectory
            ),
            SessionStore(
                harness: .geminiCLI, path: "\(homeDirectory)/.gemini/history",
                shape: .jsonLinesDirectory
            ),
            SessionStore(
                harness: .cursor, path: "\(homeDirectory)/.cursor/chats",
                shape: .unsupported("this store is SQLite; the analyst reads JSON Lines only")
            )
        ]
    }
}

/// The reader. Every byte it opens goes through ``FileSystem``, which is what lets the interesting
/// states — an unreadable store, a store of half-truncated lines, a machine with no harnesses on it
/// at all — be asked for rather than waited for.
public struct SessionCorpusReader: Sendable {
    /// The per-store line cap. A history file is unbounded and a prompt is not summarised by its
    /// oldest line, so the reader takes the **most recent** `lineCap` lines of each store.
    public static let lineCap = 4000

    let fileSystem: any FileSystem
    let stores: [SessionStore]

    public init(fileSystem: any FileSystem, homeDirectory: String) {
        self.fileSystem = fileSystem
        stores = SessionStores.table(homeDirectory: homeDirectory)
    }

    public func read() -> SessionCorpus {
        var entries: [SessionEntry] = []
        var reports: [SessionStoreReport] = []
        for store in stores {
            let outcome = readStore(store)
            entries.append(contentsOf: outcome.entries)
            reports.append(outcome.report)
        }
        return SessionCorpus(entries: entries, reports: reports)
    }

    private func readStore(
        _ store: SessionStore
    ) -> (entries: [SessionEntry], report: SessionStoreReport) {
        switch store.shape {
        case let .unsupported(reason):
            return ([], unread(store, reason))
        case .jsonLinesFile:
            guard fileSystem.fileExists(atPath: store.path) else {
                return ([], unread(store, "no file at this path"))
            }
            return harvest(store, files: [store.path])
        case .jsonLinesDirectory:
            guard let names = try? fileSystem.contentsOfDirectory(atPath: store.path) else {
                return ([], unread(store, "this directory could not be listed"))
            }
            let files = names.filter { $0.hasSuffix(".jsonl") }.sorted()
                .map { "\(store.path)/\($0)" }
            guard !files.isEmpty else {
                return ([], unread(store, "no .jsonl file in this directory"))
            }
            return harvest(store, files: files)
        }
    }

    private func unread(_ store: SessionStore, _ reason: String) -> SessionStoreReport {
        SessionStoreReport(
            harness: store.harness, path: store.path, read: false, lines: 0, discarded: 0,
            reason: reason
        )
    }

    private func harvest(
        _ store: SessionStore, files: [String]
    ) -> (entries: [SessionEntry], report: SessionStoreReport) {
        var entries: [SessionEntry] = []
        var discarded = 0
        var opened = 0
        for file in files {
            guard let data = try? fileSystem.readFile(atPath: file),
                  let text = String(data: data, encoding: .utf8)
            else {
                discarded += 1
                continue
            }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            let window = lines.suffix(Self.lineCap)
            opened += window.count
            for line in window {
                if let harvested = SessionLine.text(in: String(line)) {
                    entries.append(SessionEntry(harness: store.harness, text: harvested))
                } else {
                    discarded += 1
                }
            }
        }
        // A store whose every line was discarded is REPORTED READ with a reason, not reported
        // unread: the reader reached it, and saying otherwise would blame the machine for a format
        // this reader could not use.
        let reason = entries.isEmpty && opened > 0
            ? "every line in this store was discarded"
            : nil
        return (
            entries,
            SessionStoreReport(
                harness: store.harness, path: store.path, read: true, lines: entries.count,
                discarded: discarded, reason: reason
            )
        )
    }
}

/// Pulling the one piece of text a session line carries.
///
/// The five harnesses spell the member differently and none of them documents it, so the reader
/// tries the known spellings in order and **discards a line it cannot name a member in** rather
/// than stringifying the object. A stringified line puts JSON punctuation into the command
/// histogram, where `{"display":"docker` reads as a command called `{"display":"docker`.
enum SessionLine {
    static let members = ["display", "prompt", "text", "content", "command", "message"]

    static func text(in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parsed = try? JSONParser.parse(trimmed) else { return nil }
        for name in members {
            if let value = parsed.member(name)?.asString?.string, !value.isEmpty { return value }
        }
        return nil
    }
}
