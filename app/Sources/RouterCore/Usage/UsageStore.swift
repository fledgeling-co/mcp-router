import Foundation

/// Appends every call to a JSONL file, keeps the recent tail in memory, and maintains a durable
/// per-server aggregate.
///
/// The aggregate is separate from the log on purpose: the log rotates, and a server that has not
/// been called for six months is exactly the one whose evidence rotates out first — so "never used"
/// computed from the log alone would be a lie that grows more confident the longer it is true.
public final class UsageStore: @unchecked Sendable {
    // @unchecked: every mutable field below is guarded by `lock`, and nothing escapes without it.
    private let lock = NSLock()
    private var ring: [UsageRecord] = []
    private var since: String
    private var servers: [JSONMember] = []
    private var dirty = false
    private var subscribers: [UUID: @Sendable (UsageRecord) -> Void] = [:]

    private let logPath: String
    private let statsPath: String
    private let fileSystem: any FileSystem
    private let clock: any RouterClock

    public static let ringSize = 500
    /// 8 MiB. Compared with `>=`, and tested at the boundary rather than near it.
    public static let maxLogBytes = 8 * 1024 * 1024
    public static let tailWindowBytes = 512 * 1024
    public static let flushDebounceMilliseconds = 3000.0

    public init(
        logPath: String,
        statsPath: String,
        fileSystem: any FileSystem = RealFileSystem(),
        clock: any RouterClock = SystemClock()
    ) {
        self.logPath = logPath
        self.statsPath = statsPath
        self.fileSystem = fileSystem
        self.clock = clock
        since = JSDate.iso8601(milliseconds: clock.nowMilliseconds)
        try? fileSystem.createDirectory(atPath: (logPath as NSString).deletingLastPathComponent)
        readStats()
        ring = readTail()
    }

    // MARK: - Loading

    /// An unreadable or wrong-version stats file starts fresh.
    ///
    /// **B52 also requires a warning here, and there is none** — this type holds no logger, so
    /// saying so costs a dependency threaded from `RouterService`. Recorded as deferred child
    /// `D-v1c` rather than left as the previous comment's claim that the emptiness "is labelled by
    /// the warning": a comment asserting evidence that does not exist is what stops the next reader
    /// checking, which is exactly how B50 and B51 reached merge with no test at all.
    private func readStats() {
        guard fileSystem.fileExists(atPath: statsPath),
              let data = try? fileSystem.readFile(atPath: statsPath),
              let parsed = try? JSONParser.parse(data),
              parsed.member("version")?.asNumber == 1,
              let serverMembers = parsed.member("servers")?.asObjectMembers
        else { return }
        since = parsed.member("since")?.asString?.string ?? since
        servers = serverMembers
    }

    /// Warm the ring from the tail of the log so a restart is not a blank screen.
    ///
    /// **The byte-offset-into-a-UTF-16-string slice is reproduced deliberately (N5).** The reference
    /// takes the cut point from `statSync().size`, a byte count, and applies it to `String.indexOf`,
    /// which counts UTF-16 units. For an all-ASCII log the two coincide; for a log carrying any
    /// multi-byte text they do not, and the reference cuts in a different place than a
    /// byte-correct implementation would. Parity is what R4 measures, so this cuts where it cuts.
    private func readTail() -> [UsageRecord] {
        guard fileSystem.fileExists(atPath: logPath),
              let data = try? fileSystem.readFile(atPath: logPath) else { return [] }
        let size = data.count
        // Node decodes the log lossily, substituting U+FFFD for invalid bytes. The failable
        // initializer returns nil there instead, which would drop a tail the reference reads.
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: data, as: UTF8.self)
        var units = Array(text.utf16)

        if size > Self.tailWindowBytes {
            let offset = size - Self.tailWindowBytes
            if offset < units.count {
                let newline = UInt16(10)
                if let index = units[offset...].firstIndex(of: newline) {
                    units = Array(units[(index + 1)...])
                }
            } else {
                units = []
            }
        }

        var out: [UsageRecord] = []
        for line in JSString(units: units).split(on: 10) where !line.isEmpty {
            // A torn last line is normal after a hard kill, and is skipped rather than failing
            // the whole read.
            guard let parsed = try? JSONParser.parse(line.string),
                  let record = UsageRecord(parsed) else { continue }
            out.append(record)
        }
        return Array(out.suffix(Self.ringSize))
    }

    // MARK: - Recording

    public func record(_ record: UsageRecord) {
        var toNotify: [@Sendable (UsageRecord) -> Void] = []
        lock.lock()
        ring.append(record)
        if ring.count > Self.ringSize { ring.removeFirst(ring.count - Self.ringSize) }

        var stat = statLocked(record.server) ?? .fresh()
        stat.set("calls", .number(stat.calls + 1))
        if !record.ok { stat.set("errors", .number(stat.errors + 1)) }
        // `??=` — **nullish**, so a present `null` is replaced and a present empty string is kept.
        // Testing `== nil` alone is absence only, which leaves `"firstSeen": null` on the wire
        // forever where the reference would fill it in on the next call (S2).
        switch stat.member("firstSeen") {
        case nil, .some(.null):
            stat.set("firstSeen", .string(JSString(record.ts)))
        default:
            break
        }
        stat.set("lastUsed", .string(JSString(record.ts)))
        if let cwd = record.cwd, !cwd.isEmpty {
            var projects = stat.projects
            let key = JSString(cwd)
            let previous = projects.first { $0.key == key }?.value.asNumber ?? 0
            if let index = projects.firstIndex(where: { $0.key == key }) {
                projects[index] = JSONMember(key: key, value: .number(previous + 1))
            } else {
                projects.append(JSONMember(key: key, value: .number(previous + 1)))
            }
            stat.set("projects", .object(JSONMember.ecmaOrdered(projects)))
        }
        setStatLocked(record.server, stat)
        dirty = true
        toNotify = Array(subscribers.values)
        lock.unlock()

        // The reference wraps the rotation and the append in ONE `try`, so a rename that fails
        // **skips the append** rather than writing the record into a log that was supposed to have
        // been rotated away. Reproduced here: a later step must not run when an earlier one fails
        // (S7). Doing these as two independent `try?`s appends to the un-rotated log, which is a
        // divergence the register does not list.
        //
        // A failure is swallowed rather than propagated: losing the router because a disk filled is
        // a worse outcome than losing one log line. The reference additionally logs a warning here;
        // this type has no log seam, and that gap is reported rather than papered over.
        do {
            try rotateIfBig()
            try fileSystem.appendFile(
                Data((JSStringify.compact(record.value) + "\n").utf8), atPath: logPath
            )
        } catch {
            // Intentionally silent — see above.
        }

        // A broken subscriber must not stop the others.
        for notify in toNotify {
            notify(record)
        }
    }

    /// Throws when the rename fails, which is load-bearing: the reference's `renameSync` is inside
    /// the same `try` as the append, so a failed rotation stops the record being written. The
    /// `statSync` is caught *inside* the reference's own helper and returns, so a missing file is
    /// "nothing to rotate" rather than an error — hence `try?` on the stamp and `try` on the move.
    private func rotateIfBig() throws {
        guard let stamp = try? fileSystem.attributes(atPath: logPath),
              stamp.size >= Self.maxLogBytes else { return }
        // One generation kept. The aggregate is what makes history disposable.
        try fileSystem.moveItem(atPath: logPath, toPath: "\(logPath).1")
    }

    // MARK: - Reading

    public func recent(limit: Double?, server: String?, cwd: String?) -> [UsageRecord] {
        lock.lock()
        defer { lock.unlock() }
        var out = ring
        if let server, !server.isEmpty { out = out.filter { $0.server == server } }
        if let cwd, !cwd.isEmpty { out = out.filter { $0.cwd == cwd } }
        // `out.slice(-(limit ?? 200)).reverse()`. The negation is done first and then fed through
        // ECMAScript's own index rules, because every interesting case lives in them:
        //
        //   * `?limit=` and `?limit=0` produce `Number("") === 0`, so the slice is `slice(-0)`, and
        //     `-0` is not negative — the start index is 0 and **every** record is returned. Reading
        //     this as `suffix(0)` returns none, which is the opposite answer to the same request.
        //   * `?limit=abc` is NaN, which `ToIntegerOrInfinity` maps to 0 — everything, again.
        //   * `?limit=-5` slices from the front, dropping the five oldest (N4).
        //   * `?limit=1e300` is reachable from the wire and unbounded here, unlike the registry's
        //     `min(…, 60)`. The clamp happens in `Double` space on purpose: `Int(1e300)` traps, so
        //     converting first would let any caller halt the router with a query string.
        let effective = limit ?? 200
        var start = -effective
        if start.isNaN { start = 0 }
        start = start < 0 ? start.rounded(.up) : start.rounded(.down)

        let total = out.count
        let index: Int
        if start < 0 {
            let from = Double(total) + start
            index = from <= 0 ? 0 : Int(from)
        } else {
            index = start >= Double(total) ? total : Int(start)
        }
        return Array(out[index...]).reversed()
    }

    /// The call log folded into a window — the three counted charts on the Insights board.
    ///
    /// Reads the log from **disk** rather than the in-memory ring, and the difference is the point:
    /// the ring holds 500 records, so a day of traffic on a busy machine sits entirely outside it
    /// and a per-hour chart built from it would draw the wrong shape at the wrong height while
    /// looking perfectly plausible.
    ///
    /// A missing or unreadable log yields an empty window rather than throwing. That is the same
    /// judgement `readTail` makes, for the same reason: a board that cannot draw a chart is a far
    /// better outcome than a control endpoint that fails, and the empty window is distinguishable
    /// from a busy one because ``UsageInsights/horizon`` is nil.
    public func insights(nowMilliseconds: Double, windowHours: Int = 24) -> UsageInsights {
        guard fileSystem.fileExists(atPath: logPath),
              let data = try? fileSystem.readFile(atPath: logPath)
        else {
            return UsageInsights.over(
                lines: [], nowMilliseconds: nowMilliseconds, windowHours: windowHours
            )
        }
        // Lossy, matching `readTail`: a log carrying one invalid byte must not cost the whole
        // window, and the line that carries it is counted as unreadable rather than dropped
        // silently.
        // swiftlint:disable:next optional_data_string_conversion
        let text = String(decoding: data, as: UTF8.self)
        return UsageInsights.over(
            lines: text.split(separator: "\n").lazy.map(String.init),
            nowMilliseconds: nowMilliseconds,
            windowHours: windowHours
        )
    }

    public func summarySince() -> String {
        lock.lock(); defer { lock.unlock() }
        return since
    }

    public func summaryServers() -> [JSONMember] {
        lock.lock(); defer { lock.unlock() }
        return servers
    }

    public func statFor(_ server: String) -> ServerStat? {
        lock.lock(); defer { lock.unlock() }
        return statLocked(server)
    }

    private func statLocked(_ server: String) -> ServerStat? {
        let key = JSString(server)
        guard let value = servers.first(where: { $0.key == key })?.value,
              let members = value.asObjectMembers else { return nil }
        return ServerStat(members: members)
    }

    private func setStatLocked(_ server: String, _ stat: ServerStat) {
        let key = JSString(server)
        if let index = servers.firstIndex(where: { $0.key == key }) {
            servers[index] = JSONMember(key: key, value: stat.value)
        } else {
            servers.append(JSONMember(key: key, value: stat.value))
        }
        servers = JSONMember.ecmaOrdered(servers)
    }

    // MARK: - Subscription

    public func subscribe(_ handler: @escaping @Sendable (UsageRecord) -> Void) -> () -> Void {
        let id = UUID()
        lock.lock()
        subscribers[id] = handler
        lock.unlock()
        return { [weak self] in
            guard let self else { return }
            lock.lock()
            subscribers[id] = nil
            lock.unlock()
        }
    }

    // MARK: - Mutation

    public func flush() {
        lock.lock()
        guard dirty else { lock.unlock(); return }
        dirty = false
        let snapshot = JSONValue.object([
            JSONMember(key: "version", value: .number(1)),
            JSONMember(key: "since", value: .string(JSString(since))),
            JSONMember(key: "servers", value: .object(servers))
        ])
        lock.unlock()
        let temporary = "\(statsPath).tmp-\(ProcessInfo.processInfo.processIdentifier)"
        guard (try? fileSystem.writeFile(
            Data(JSStringify.prettyTwoSpace(snapshot).utf8), atPath: temporary
        )) != nil else { return }
        try? fileSystem.moveItem(atPath: temporary, toPath: statsPath)
    }

    /// Forget everything. `since` moves to now, which is what keeps "never used" honest after a
    /// reset: a server with no calls since a reset an hour ago is not the same claim as one with no
    /// calls since the router was installed.
    public func reset() {
        lock.lock()
        ring = []
        servers = []
        since = JSDate.iso8601(milliseconds: clock.nowMilliseconds)
        dirty = true
        lock.unlock()
        flush()
        for path in [logPath, "\(logPath).1"] where fileSystem.fileExists(atPath: path) {
            try? fileSystem.removeItem(atPath: path)
        }
    }

    /// Drop one server's aggregate — called when a server is removed.
    public func forget(_ server: String) {
        lock.lock()
        let key = JSString(server)
        servers.removeAll { $0.key == key }
        // Compared as a JavaScript string, like the aggregate above. Swift's `String ==` is
        // canonical equivalence, so a decomposed ring entry matched a composed request and this
        // dropped a *different* server's history alongside the one asked for (S5).
        ring.removeAll { JSString($0.server) == key }
        dirty = true
        lock.unlock()
        flush()
    }
}

/// `basename(cwd)` — the last path segment, for display.
public func projectOf(_ cwd: String?) -> String? {
    guard let cwd, !cwd.isEmpty else { return nil }
    return jsBasename(cwd)
}

/// Node's `path.basename` for a POSIX path, which is **not** `NSString.lastPathComponent`.
///
/// The two disagree on the root: Node's `basename('/')` is the empty string and `basename('//')`
/// is too, while `lastPathComponent` answers `"/"` for both. A call made from `/` — a launchd
/// job, a daemon that never chdir'd — therefore recorded a project literally named `/`, which then
/// appeared as a project in the usage summary and as a `projects` key on the wire (B47).
func jsBasename(_ path: String) -> String {
    // Trailing separators are ignored, so `/a/b/` is `b`.
    var end = path.endIndex
    while end > path.startIndex, path[path.index(before: end)] == "/" {
        end = path.index(before: end)
    }
    // Nothing but separators — the root, and Node calls that empty.
    guard end > path.startIndex else { return "" }
    let trimmed = path[path.startIndex ..< end]
    guard let slash = trimmed.lastIndex(of: "/") else { return String(trimmed) }
    return String(trimmed[trimmed.index(after: slash)...])
}
