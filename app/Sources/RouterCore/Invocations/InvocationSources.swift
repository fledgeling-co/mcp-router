import Foundation

/// Where the router looks for session transcripts — and the fact that it looks nowhere by default.
///
/// **`MCP_ROUTER_TRANSCRIPTS` is the whole of the configuration, and unset is the shipped state.**
/// The router could discover `~/.claude/projects` on almost every machine it runs on. It does not,
/// and the reason is the difference between a product that reads your sessions and one that reads
/// them because you asked: a default here would mean an upgrade silently started opening 59,476
/// files of somebody's agent history, and no release note would make that the same act.
///
/// The value is a colon-separated list of `<harness>=<root>` pairs, the shape `PATH` already
/// teaches, and a pair naming a root that is not a directory is **dropped and counted** rather than
/// treated as an empty corpus — a root that vanished and a corpus with nothing in it are not the
/// same fact.
///
///     MCP_ROUTER_TRANSCRIPTS='claude-code=/Users/x/.claude/projects'
public enum InvocationSources {
    public static let environmentKey = "MCP_ROUTER_TRANSCRIPTS"

    /// Harnesses that have session files on disk and whose files record no capability call.
    ///
    /// Measured 2026-08-29 on the author's machine. These carry `nil` runs and their reason rather
    /// than `0`, for ``HarnessInvocationCount``'s reason: a zero here reads as *this harness ran no
    /// skills*, which is the finding, and it would be fabricated.
    public static let unobservable: [HarnessInvocationCount] = [
        HarnessInvocationCount(
            harness: "codex", runs: nil,
            reason: "its rollouts are `{timestamp, type, payload}` lines with no skill concept, "
                + "so there is nothing here to adapt yet"
        ),
        HarnessInvocationCount(
            harness: "grok", runs: nil,
            reason: "its 2,169 jsonl files are sandbox events rather than transcripts, and hold "
                + "no tool call"
        )
    ]

    /// Parse the variable. An empty or unset value yields no sources, which is not an error.
    ///
    /// - Returns: the sources, and how many pairs were discarded — a malformed pair, an empty
    ///   half, or a root that is not a directory. Returned rather than logged, because a variable
    ///   with one good pair and one typo produces a partial reading, and a caller that cannot see
    ///   the second number reports it as a whole one.
    /// Whether a path is a directory that can be walked.
    ///
    /// `FileManager` directly rather than the ``FileSystem`` seam, and it is
    /// ``DiskExtensionStore``'s reason unchanged: the seam expresses single files and has no way to
    /// ask whether a path is a directory. Its in-memory double answers `contentsOfDirectory` for a
    /// path that does not exist by filtering its key set and returning `[]`, so a guard written
    /// against the seam accepts a root that is not there — measured here, where the first version
    /// of this function admitted `/no/such/place` and the test that caught it was the one written
    /// to see it dropped.
    public static let realDirectoryTest: @Sendable (String) -> Bool = { path in
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    public static func parse(
        _ raw: String?, isDirectory: @Sendable (String) -> Bool = realDirectoryTest
    ) -> (sources: [TranscriptSource], discarded: Int) {
        guard let raw, !raw.isEmpty else { return ([], 0) }
        var out: [TranscriptSource] = []
        var discarded = 0
        for pair in raw.split(separator: ":", omittingEmptySubsequences: false) {
            let halves = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard halves.count == 2, !halves[0].isEmpty, !halves[1].isEmpty else {
                discarded += 1
                continue
            }
            let root = String(halves[1])
            // A file rather than a directory, or nothing at all.
            guard isDirectory(root) else {
                discarded += 1
                continue
            }
            out.append(TranscriptSource(harness: String(halves[0]), root: root))
        }
        return (out, discarded)
    }

    /// The history the daemon holds, or nil when nothing named a corpus.
    ///
    /// Nil rather than an empty history, and the distinction is the one every optional port in
    /// `ControlDeps` draws: a router nobody pointed anywhere and a machine on which nothing ran
    /// produce the same empty table, and only one of them is a measurement.
    public static func history(
        // swift-wire-exempt: the process environment, read for one key and never serialised. It is
        // Foundation's own type at the boundary; nothing here reaches the wire.
        environment: [String: String],
        home: RouterHome,
        fileSystem: any FileSystem,
        isDirectory: @Sendable (String) -> Bool = realDirectoryTest
    ) -> InvocationHistory? {
        let parsed = parse(environment[environmentKey], isDirectory: isDirectory)
        guard !parsed.sources.isEmpty else { return nil }
        return InvocationHistory(
            sources: parsed.sources,
            invocationsPath: home.invocationsPath,
            ledgerPath: home.versionLedgerPath,
            watermarkPath: home.invocationWatermarkPath,
            unobservableHarnesses: unobservable,
            fileSystem: fileSystem
        )
    }
}
