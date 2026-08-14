#if os(macOS)
    import Foundation
    import MCPRouterKit

    /// The app's record of check runs it has performed, bounded and stamped.
    ///
    /// **This holds history and nothing else.** No verdict the boards render is ever read back from
    /// here: every one is computed from the response the board just fetched. That separation is the
    /// whole correction this item's spec gate forced, and it is what makes "a stale verdict cannot
    /// render as current" a property of the architecture rather than a promise — the code path a stale
    /// verdict would need does not exist, and `M7SourceGuardTests` asserts no board row type
    /// references this type.
    ///
    /// **Why local persistence is not a second channel.** The Mac app talks to the router only over
    /// the loopback control API, and that is untouched: this file records *the app's own observations
    /// of what the router served*, stamped with a time and a version. It sends nothing, and it asks
    /// the router for nothing it does not already serve. The brief asks for history across versions
    /// and the router stores none, so the alternative is not a different channel — it is no history.
    @MainActor
    public final class CheckHistoryStore {
        /// Runs kept per subject. The 21st evicts the oldest.
        ///
        /// Bounded because an unbounded local file is a slow leak nobody notices until it is large,
        /// and because history past twenty runs answers no question this pane asks.
        public static let capacity = 20

        private let fileURL: URL
        private var runs: [String: [StoredRun]]
        /// Why the history could not be read, when it could not. Kept rather than swallowed: the pane
        /// must be able to say "the history could not be read" rather than "there is none", which are
        /// different claims (`SWIFT_PRACTICES.md` §3).
        public private(set) var loadError: String?

        /// The directory is injected so tests write to a temp dir rather than the real one.
        public init(directory: URL) {
            fileURL = directory.appendingPathComponent("check-history.json")
            let (loaded, error) = Self.read(fileURL)
            runs = loaded
            loadError = error
        }

        /// The default location: this app's Application Support directory.
        public static func defaultDirectory() -> URL {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
            let directory = base.appendingPathComponent("MCPRouter", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        }

        // MARK: - Reading

        /// One subject's runs, newest first.
        public func history(for subject: SubjectKey) -> [StoredRun] {
            runs[Self.key(subject)] ?? []
        }

        // MARK: - Writing

        /// Records one run, and reports whether it was recorded.
        ///
        /// **Returns `false` and writes nothing when there is no stamp**, which is the structural half
        /// of "no result without a version": a `.standalone` skill has no `pluginVersion` anywhere in
        /// `SkillSource` and a never-declared server has no `hash`, so `Stamp`'s failable initialiser
        /// yields nil and there is nothing to pass. Storing such a result would create a row that
        /// could never be known to be out of date, which is a worse answer than no row.
        @discardableResult
        public func record(
            subject: SubjectKey,
            stamp: Stamp?,
            results: [CheckResult],
            at date: Date = Date()
        ) -> Bool {
            guard let stamp else { return false }
            let key = Self.key(subject)
            var existing = runs[key] ?? []
            existing.insert(StoredRun(stamp: stamp, ranAt: date, results: results), at: 0)
            if existing.count > Self.capacity {
                existing.removeSubrange(Self.capacity...)
            }
            runs[key] = existing
            write()
            return true
        }

        // MARK: - Disk

        private static func key(_ subject: SubjectKey) -> String {
            "\(subject.kind.rawValue):\(subject.id)"
        }

        /// Reads the file, and never fails the caller for a bad one.
        ///
        /// A corrupt or unreadable history starts empty and keeps the error. Refusing to open the
        /// board because a cache file is malformed would be trading a complete surface for a partial
        /// one over data nothing depends on — but the pane still says the history could not be read
        /// rather than claiming the checks never ran, which is why the error is returned and not
        /// discarded.
        private static func read(_ url: URL) -> ([String: [StoredRun]], String?) {
            guard FileManager.default.fileExists(atPath: url.path) else { return ([:], nil) }
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try (decoder.decode([String: [StoredRun]].self, from: data), nil)
            } catch {
                return ([:], String(describing: error))
            }
        }

        private func write() {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                try encoder.encode(runs).write(to: fileURL, options: .atomic)
            } catch {
                // A failed write leaves the in-memory history intact and the board working. There is
                // nothing useful to tell the user about a cache that could not be saved, and nothing
                // they could do about it, so it is not surfaced as an error state.
                loadError = String(describing: error)
            }
        }
    }
#endif
