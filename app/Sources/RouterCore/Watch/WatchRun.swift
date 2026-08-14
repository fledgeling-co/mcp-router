import Foundation

/// One-shot: absorb newly-added MCP servers out of `~/.claude.json` into the router's own list.
///
/// `~/.claude.json` is the staging area. `claude mcp add` writes a server into its `mcpServers`,
/// launchd fires this on the file change, and the server is moved into the router's own list,
/// indexed, and deleted from user scope. From then on it reaches every session through the router
/// instead of starting a copy per session.
///
/// Two facts shape the whole design, and both survive the port unchanged:
///
/// 1. That file is ~268 KB and Claude Code rewrites it constantly with session state, so this runs
///    *very* often. The common case — nothing about `mcpServers` changed — must be a read, a hash
///    and an exit, with nothing spawned and nothing written (W1).
/// 2. It holds live session state for every project on the machine. So: back up before writing,
///    write temp-plus-rename rather than truncating in place, and abandon the run entirely rather
///    than write anything derived from a parse that failed (W2, W4).
///
/// What does **not** survive unchanged is the concurrency story: three processes write
/// `servers.json` here, and this one holds its read-modify-write open across seconds of indexing.
/// See ``WatchAdoption`` for the protocol, and ``WatchRestart`` for the restart the reference loses.
public struct WatchRunner: Sendable {
    /// The reference's `FAILURE_BACKOFF_MS` — how long a server that failed to index is left alone.
    public static let failureBackoffMs: Double = 5 * 60000

    let paths: WatchPaths
    let home: RouterHome
    let fileSystem: any FileSystem & FileModeWriting
    let clock: any RouterClock
    let transporting: any UpstreamTransporting
    let kick: WatchRestart.Kick
    let processIdentifier: Int32
    let lockTimeoutMs: Int
    let log: WatchLog
    let poolLog: RouterLog
    let emit: @Sendable (String) -> Void

    public init(
        paths: WatchPaths = WatchPaths(),
        // `nil` resolves to `paths.routerHome`, which is derived from the **same** `HOME` as
        // `~/.claude.json`. Defaulting this to `RouterHome()` instead is the shape this had, and it
        // splits the run across two homes: `WatchPaths` honours `$HOME` (X10, W-D2) while
        // `RouterHome()` reads `NSHomeDirectory()`, which ignores it. Under a scratch `HOME` with no
        // `MCP_ROUTER_HOME` the watcher then read the scratch `~/.claude.json` and wrote the real
        // account's `servers.json` — the precise hazard X10 exists to prevent, left open on the
        // other half of the pair. The reference cannot produce it: one `homedir()` feeds both
        // (`src/config.ts:79`, `src/watch.ts:45`).
        home: RouterHome? = nil,
        fileSystem: any FileSystem & FileModeWriting = RealFileSystem(),
        clock: any RouterClock = SystemClock(),
        transporting: (any UpstreamTransporting)? = nil,
        kick: @escaping WatchRestart.Kick = WatchRestart.launchctl,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        lockTimeoutMs: Int = ConfigMutationLock.timeoutMilliseconds(
            default: ConfigMutationLock.watcherTimeoutMs
        ),
        // No stdout default, deliberately. `RouterCore` is linked into a process that speaks MCP
        // over stdio, so a stray byte on that stream corrupts the protocol — `LogParityTests`
        // enforces it across this whole target. The two `--verbose` lines are the CLI's to print,
        // and `WatchVerb` passes `Out.print`.
        emit: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.paths = paths
        self.home = home ?? paths.routerHome
        self.fileSystem = fileSystem
        self.clock = clock
        // `cmdWatch` never calls `log.configure`, so the reference's pool logs to **stderr** — the
        // spawn and reap lines a `watch` run emits are on that stream, and `cli-watch` diffs it. An
        // unconfigured `RouterLog` is already a `StandardErrorSink`, so this is the reference's
        // behaviour rather than a choice.
        poolLog = RouterLog()
        self.transporting = transporting ?? RoutingUpstreamTransport(log: poolLog)
        self.kick = kick
        self.processIdentifier = processIdentifier
        self.lockTimeoutMs = lockTimeoutMs
        self.emit = emit
        log = WatchLog(path: paths.logPath, fileSystem: fileSystem, clock: clock)
    }

    public func run(verbose: Bool = false) async throws {
        guard fileSystem.fileExists(atPath: paths.claudeJSON) else { return }
        let data = try fileSystem.readFile(atPath: paths.claudeJSON)
        let parsed: JSONValue
        do {
            parsed = try JSONParser.parse(data)
        } catch {
            // A parse failure here is almost always a read that landed mid-write. Writing anything
            // derived from it would destroy the file, so this run simply ends (W2). Deliberately
            // narrower than "any parse failure": the same failure at the *re-read* is handled
            // differently, because by then `servers.json` may already have been written.
            log.record(.configDidNotParse(reason: "\(error)"))
            return
        }

        let staged = WatchStaging.stagedServers(of: parsed)
        let hash = StableHash.hash(of: .object(staged))
        var state = WatchState.load(path: paths.statePath, fileSystem: fileSystem)

        // Before anything else, including the fast path: a restart owed from an earlier fire must
        // be retried even on a run where nothing has changed, because the fire that owes it is
        // exactly the one whose next fire takes the fast path (X7).
        if state.restartPending {
            log.record(.retryingOwedRestart)
            settleOwedRestart(&state)
        }

        // The whole point of the hash: this is the path taken on nearly every fire.
        if state.mcpServersHash == hash {
            if verbose { emit("mcpServers unchanged; nothing to do\n") }
            return
        }

        let candidates = WatchStaging.candidates(in: staged, log: log)
        if candidates.isEmpty {
            state.mcpServersHash = hash
            try save(state)
            if verbose { emit("no entries to adopt\n") }
            return
        }

        guard fileSystem.fileExists(atPath: home.configPath) else {
            log.record(.noRouterConfig(path: home.configPath))
            return
        }
        // Parsed **before** anything is indexed. The reference reads and parses the router config at
        // `watch.ts:200`, before it constructs a pool, so a corrupt `servers.json` costs it no child
        // processes. Failing only at the merge — after seconds of spawning — would be a divergence
        // nobody declared, and the expensive direction of one.
        try requireParseableRouterConfig()

        try await adopt(candidates, state: &state, stagedHash: hash)
    }

    // MARK: - The adoption

    private func adopt(
        _ candidates: [WatchStaging.Candidate], state: inout WatchState, stagedHash: String
    ) async throws {
        // A failure record for a server that is no longer staged is dead weight.
        let names = Set(candidates.map(\.name))
        state.failures = state.failures.filter { names.contains($0.key) }

        let now = clock.nowMilliseconds
        var manifest = ManifestIO.load(
            path: home.manifestPath, fileSystem: fileSystem
        ).manifest

        var live: [WatchStaging.Candidate] = []
        var pending: [String] = []
        var toIndex: [UpstreamConfig] = []
        for candidate in candidates {
            let identity = UpstreamHash.hash(candidate.upstream)
            if let failure = state.failures[candidate.name],
               failure.hash == identity,
               now - failure.at < Self.failureBackoffMs
            {
                // Backed off, and therefore still pending — which withholds the state hash, so the
                // next fire after the window retries rather than skipping it forever.
                pending.append(candidate.name)
                continue
            }
            live.append(candidate)
            if ToolUnion.isStale(manifest, candidate.upstream) { toIndex.append(candidate.upstream) }
        }

        if !toIndex.isEmpty {
            let report = await WatchIndexer(
                manifestPath: home.manifestPath,
                startupTimeoutMs: startupTimeoutMs(),
                transporting: transporting,
                fileSystem: fileSystem,
                clock: clock,
                poolLog: poolLog
            ).index(toIndex)
            record(report, into: &state, at: now, upstreams: toIndex)
            manifest = ManifestIO.load(path: home.manifestPath, fileSystem: fileSystem).manifest
        }

        // Adopt = present in the manifest, error-free, at the current config identity.
        var adopted: [(name: String, raw: JSONValue)] = []
        for candidate in live {
            let entry = manifest.entry(named: candidate.name)
            guard let entry, !entry.hasError,
                  entry.hash == JSString(UpstreamHash.hash(candidate.upstream))
            else {
                pending.append(candidate.name)
                continue
            }
            adopted.append((candidate.name, candidate.raw))
        }

        let configChanged = try mergeIntoRouterConfig(adopted, state: &state, at: now)
        // X6 — issued here, before `~/.claude.json` is touched at all, so no later early return can
        // skip it. That is the whole of divergence W-D1.
        if configChanged { settleOwedRestart(&state) }

        guard !adopted.isEmpty else {
            try sealOrWithhold(
                state: &state, hash: stagedHash, pending: pending, announcing: false
            )
            return
        }
        try deleteFromStaging(adopted, state: &state, pending: pending)
    }

    /// The merge, under the lock. Returns whether `servers.json` changed.
    private func mergeIntoRouterConfig(
        _ adopted: [(name: String, raw: JSONValue)], state: inout WatchState, at now: Double
    ) throws -> Bool {
        guard !adopted.isEmpty else { return false }
        var owed = state
        do {
            return try WatchAdoption.merge(
                adopted: adopted,
                into: WatchAdoption.Destination(
                    path: home.configPath,
                    backupDirectory: paths.backupDirectory,
                    processIdentifier: processIdentifier,
                    lockTimeoutMs: lockTimeoutMs
                ),
                fileSystem: fileSystem,
                nowMilliseconds: now
            ) {
                // Inside the lock, before the rename (X7). A process killed between the rename and
                // any later save still leaves the debt on disk.
                owed.restartPending = true
                try save(owed)
            }
        } catch let problem as WatchAdoption.Problem {
            if case let .flatRouterConfig(path) = problem { log.record(.flatRouterConfig(path: path)) }
            throw problem
        }
    }

    /// Issue the restart if one is owed, clearing the debt only when launchd accepted it.
    func settleOwedRestart(_ state: inout WatchState) {
        state.restartPending = true
        if let reason = kick(paths.launchdLabel) {
            log.record(.restartFailed(label: paths.launchdLabel, reason: reason))
            try? save(state)
            return
        }
        log.record(.restarted(label: paths.launchdLabel))
        state.restartPending = false
        try? save(state)
    }

    // MARK: - Small pieces

    private func record(
        _ report: WatchIndexer.Report,
        into state: inout WatchState,
        at now: Double,
        upstreams: [UpstreamConfig]
    ) {
        for failure in report.failed {
            let name = String(failure.prefix(while: { $0 != ":" }))
            log.record(.indexFailed(entry: failure))
            guard let upstream = upstreams.first(where: { $0.name == name }) else { continue }
            state.failures[name] = WatchState.Failure(
                hash: UpstreamHash.hash(upstream), at: now, error: failure
            )
        }
        for entry in report.built {
            log.record(.adopted(entry: entry))
            state.failures.removeValue(forKey: String(entry.prefix(while: { $0 != " " })))
        }
    }

    func save(_ state: WatchState) throws {
        try state.save(
            path: paths.statePath, fileSystem: fileSystem, processIdentifier: processIdentifier
        )
    }

    /// Read and parse `servers.json`, throwing before any child is spawned.
    ///
    /// The parse result is deliberately discarded: the object this run merges into is re-read
    /// **inside** the lock (W10), and holding this one would be the stale snapshot the whole item
    /// exists to avoid. What is wanted here is only the failure, and only this early.
    private func requireParseableRouterConfig() throws {
        let data = try fileSystem.readFile(atPath: home.configPath)
        do {
            _ = try JSONParser.parse(data)
        } catch {
            throw WatchAdoption.Problem.unparseableRouterConfig(
                path: home.configPath, reason: "\(error)"
            )
        }
    }

    /// `(routerCfg.startupTimeoutMs as number) ?? 60_000`, read straight off the file rather than
    /// through `ConfigLoader` — the reference reads only this one key here, and a full load would
    /// fail the run on a config the adoption path is about to rewrite anyway.
    private func startupTimeoutMs() -> Int {
        guard let data = try? fileSystem.readFile(atPath: home.configPath),
              let parsed = try? JSONParser.parse(data),
              let members = parsed.asObjectMembers,
              let value = members.first(where: { $0.key == JSString("startupTimeoutMs") })?
              .value.asNumber
        else { return RouterHome.defaultStartupTimeoutMs }
        // `Int(_: Double)` **traps** on a value that is infinite, NaN, or outside `Int`'s range, and
        // every one of those is reachable from this file: `JSONCursor.parseNumber` turns `1e400`
        // into an infinity exactly as `JSON.parse` does, and `1e300` is finite but far past
        // `Int.max`. Measured: `Int(Double("1e400")!)` aborts with "Double value cannot be converted
        // to Int because it is either infinite or NaN". The reference has no such edge — it hands
        // the raw number to the pool — so a `servers.json` the reference merely finds odd would
        // crash this launchd one-shot on every fire.
        //
        // `JSNumber.int` is the shared guard; falling back to the default here matches what a
        // non-numeric `startupTimeoutMs` already does two lines above.
        return JSNumber.int(value) ?? RouterHome.defaultStartupTimeoutMs
    }
}
