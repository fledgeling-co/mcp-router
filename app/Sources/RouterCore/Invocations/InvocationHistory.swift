import Foundation

/// The whole of F5, assembled: scan the corpora, append what is new, fold a window against the
/// ledger.
///
/// **Everything it touches is named here, and nothing else is opened.** Three files under
/// `<router home>` — the invocation log, the version ledger, the watermarks — and, read-only, the
/// session files under each ``TranscriptSource``'s root. There is no network call on any path
/// through this type, and `scripts/lint/no-telemetry-egress.sh` is what keeps that true as it
/// changes rather than this sentence.
public final class InvocationHistory: InvocationReporting, @unchecked Sendable {
    // @unchecked: every mutable field is guarded by `lock`, and nothing escapes without it.
    private let lock = NSLock()
    private var ledger = VersionLedger(observations: [])
    private var watermarks = TranscriptWatermarks()
    /// What the last ``refresh()`` reported, or nil when none has run in this process.
    ///
    /// Held rather than recomputed, because the accounting is a property of **reading the corpus**
    /// and ``window(nowMilliseconds:days:)`` does not read the corpus — it folds a log. An earlier
    /// version of that function filled a `TranscriptAccounting` from the invocation log's own line
    /// count and served it under the same member names, so `linesRead` on the wire was a count of
    /// invocations rather than a count of transcript lines. That is `G4`'s subject exactly: a
    /// figure named for one quantity that reads a different one, whose right answer and whose
    /// wrong answer look identical.
    private var lastScan: TranscriptAccounting?
    /// Lines of `invocations.jsonl` that could not be read back. Kept apart from the scan's
    /// `unparseable`, which counts transcript lines — two corpora, two numbers.
    private var unreadableLogLines = 0

    private let sources: [TranscriptSource]
    private let invocationsPath: String
    private let ledgerPath: String
    private let watermarkPath: String
    private let fileSystem: any FileSystem

    /// Harnesses that have a root here but whose transcripts hold no capability call, with the
    /// reason. Reported as `null` runs rather than `0` — see ``HarnessInvocationCount``.
    private let unobservable: [HarnessInvocationCount]

    public init(
        sources: [TranscriptSource],
        invocationsPath: String,
        ledgerPath: String,
        watermarkPath: String,
        unobservableHarnesses: [HarnessInvocationCount] = [],
        fileSystem: any FileSystem = RealFileSystem()
    ) {
        self.sources = sources
        self.invocationsPath = invocationsPath
        self.ledgerPath = ledgerPath
        self.watermarkPath = watermarkPath
        unobservable = unobservableHarnesses
        self.fileSystem = fileSystem
        try? fileSystem.createDirectory(
            atPath: (invocationsPath as NSString).deletingLastPathComponent
        )
        reload()
    }

    // MARK: - Loading

    /// Read the ledger and the watermarks off disk. Either being unreadable starts that one empty,
    /// which costs a re-scan and never a wrong answer — ``UsageStore``'s judgement for its stats
    /// file, for the same reason.
    public func reload() {
        lock.lock()
        defer { lock.unlock() }
        ledger = Self.readLedger(at: ledgerPath, fileSystem: fileSystem)
        watermarks = Self.readWatermarks(at: watermarkPath, fileSystem: fileSystem)
    }

    private static func readLedger(at path: String, fileSystem: any FileSystem) -> VersionLedger {
        guard fileSystem.fileExists(atPath: path),
              let data = try? fileSystem.readFile(atPath: path)
        else { return VersionLedger(observations: []) }
        // Lossy, matching `UsageStore.readTail`: one invalid byte must not cost the whole ledger.
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: data, as: UTF8.self)
        return VersionLedger.read(lines: text.split(separator: "\n").map(String.init)).ledger
    }

    private static func readWatermarks(
        at path: String, fileSystem: any FileSystem
    ) -> TranscriptWatermarks {
        guard fileSystem.fileExists(atPath: path),
              let data = try? fileSystem.readFile(atPath: path),
              let parsed = try? JSONParser.parse(data)
        else { return TranscriptWatermarks() }
        return TranscriptWatermarks.read(parsed)
    }

    // MARK: - Observing

    /// Append boundaries the ledger does not already hold.
    ///
    /// **Append-on-change**: an observation whose version matches the newest one already recorded
    /// for that capability adds nothing, so the file holds moments at which something moved rather
    /// than a restatement of the installed set per reading. That is what makes
    /// ``VersionLedger/horizon`` a fact about history instead of a fact about uptime.
    ///
    /// - Returns: how many boundaries were actually new.
    @discardableResult
    public func observe(_ candidates: [VersionObservation]) -> Int {
        lock.lock()
        var appended: [VersionObservation] = []
        for candidate in candidates {
            let existing = ledger.boundaries(candidate.kind, candidate.name)
                + appended.filter { $0.kind == candidate.kind && $0.name == candidate.name }
            if let newest = existing.max(by: { $0.ts < $1.ts }), newest.version == candidate.version {
                continue
            }
            appended.append(candidate)
        }
        if !appended.isEmpty {
            ledger = VersionLedger(observations: ledger.observations + appended)
        }
        lock.unlock()
        guard !appended.isEmpty else { return 0 }
        append(appended.map(\.value), to: ledgerPath)
        return appended.count
    }

    /// Scan every source from its watermark, append what is new, and persist the watermarks.
    ///
    /// - Returns: the accounting for this pass — what was skipped, read, dropped and why.
    @discardableResult
    public func refresh() -> TranscriptAccounting {
        var total = TranscriptAccounting()
        for source in sources {
            let walk = TranscriptCorpus.files(under: source.root, fileSystem: fileSystem)
            lock.lock()
            let starting = watermarks
            lock.unlock()
            let result = TranscriptScan.scan(
                files: walk.paths, harness: source.harness,
                fileSystem: fileSystem, watermarks: starting
            )
            lock.lock()
            watermarks = result.watermarks
            lock.unlock()
            if !result.events.isEmpty {
                append(result.events.map(\.value), to: invocationsPath)
            }
            total = Self.merge(
                total, result.accounting, unreadableDirectories: walk.unreadableDirectories
            )
        }
        lock.lock()
        let snapshot = watermarks.value
        lock.unlock()
        try? fileSystem.writeFile(Data(JSStringify.compact(snapshot).utf8), atPath: watermarkPath)
        lock.lock()
        lastScan = total
        lock.unlock()
        return total
    }

    private static func merge(
        _ left: TranscriptAccounting, _ right: TranscriptAccounting, unreadableDirectories: Int
    ) -> TranscriptAccounting {
        var out = left
        out.filesSkipped += right.filesSkipped
        out.filesRead += right.filesRead
        out.filesReread += right.filesReread
        // A directory that could not be listed hides an unknown number of files, so it is counted
        // in the same column a file that could not be read is: both are corpus this pass did not
        // see, and a fold that reported neither would look identical to a complete one.
        out.filesUnreadable += right.filesUnreadable + unreadableDirectories
        out.linesRead += right.linesRead
        out.unparseable += right.unparseable
        out.withoutTimestamp += right.withoutTimestamp
        out.notAnInvocation += right.notAnInvocation
        out.unnamedTool += right.unnamedTool
        out.builtInTool += right.builtInTool
        return out
    }

    // MARK: - Reading

    /// Fold the log into a window. **It reads no transcript**, which is why the accounting it
    /// carries is the last scan's rather than one taken here: this function reads
    /// `invocations.jsonl`, and a figure describing that read would answer a question nobody asked
    /// while wearing the name of the one they did.
    ///
    /// Before any scan has run in this process the accounting is all zeros, and that is honest
    /// rather than empty — nothing has been read, so there is nothing to report about what was
    /// dropped. ``unreadableEventLines`` is the separate figure for this log's own damage.
    public func window(nowMilliseconds: Double, days: Int) -> CapabilityUseWindow {
        let (events, unparseable) = readEvents()
        lock.lock()
        let snapshot = ledger
        let reading = lastScan ?? TranscriptAccounting()
        unreadableLogLines = unparseable
        lock.unlock()
        return InvocationInsights.fold(
            events: events,
            ledger: snapshot,
            reading: InvocationReading(
                harnesses: harnessCounts(events), accounting: reading
            ),
            nowMilliseconds: nowMilliseconds,
            days: days
        )
    }

    /// Lines of `invocations.jsonl` the last ``window(nowMilliseconds:days:)`` could not parse.
    ///
    /// A torn last line is ordinary after a hard kill. Exposed so a caller can tell a quiet window
    /// from a damaged log — the distinction `UsageInsights.unreadableLines` exists for one
    /// directory over — and kept apart from the scan's `unparseable` because they count lines in
    /// two different files.
    public var unreadableEventLines: Int {
        lock.lock(); defer { lock.unlock() }
        return unreadableLogLines
    }

    /// One row per harness that has a root here, whether or not anything was observed in it.
    ///
    /// A harness declared unobservable keeps its `null` even when the log happens to hold a row for
    /// it: the declaration says the router cannot see that harness's capability calls, and a count
    /// taken anyway would be a partial reading presented as a total.
    private func harnessCounts(_ events: [InvocationEvent]) -> [HarnessInvocationCount] {
        var out: [HarnessInvocationCount] = []
        for source in sources {
            if let declared = unobservable.first(where: { $0.harness == source.harness }) {
                out.append(declared)
                continue
            }
            out.append(HarnessInvocationCount(
                harness: source.harness,
                runs: events.count { $0.harness == source.harness }
            ))
        }
        out.append(contentsOf: unobservable.filter { declared in
            !sources.contains { $0.harness == declared.harness }
        })
        return out
    }

    private func readEvents() -> (events: [InvocationEvent], unparseable: Int) {
        guard fileSystem.fileExists(atPath: invocationsPath),
              let data = try? fileSystem.readFile(atPath: invocationsPath)
        else { return ([], 0) }
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: data, as: UTF8.self)
        var out: [InvocationEvent] = []
        var unparseable = 0
        for line in text.split(separator: "\n") where !line.isEmpty {
            guard let parsed = try? JSONParser.parse(String(line)),
                  let event = InvocationEvent(parsed)
            else {
                unparseable += 1
                continue
            }
            out.append(event)
        }
        return (out, unparseable)
    }

    /// Append JSONL. A failure is swallowed for ``UsageStore/record(_:)``'s reason: losing the
    /// router because a disk filled is a worse outcome than losing one line of history.
    private func append(_ values: [JSONValue], to path: String) {
        let text = values.map { JSStringify.compact($0) + "\n" }.joined()
        try? fileSystem.appendFile(Data(text.utf8), atPath: path)
    }
}
