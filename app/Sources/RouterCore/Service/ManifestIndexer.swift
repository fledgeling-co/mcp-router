import Foundation

// Split out of `ServicePorts.swift` by R19, which took this type past that file's 400-line lint
// ceiling. A move rather than a trim: the alternative was deleting the comments that record why the
// load is inside the lock, and this type was already the one thing in that file with its own
// lifecycle — `POST /servers/:name/reindex` and `mcp-router index` both run it.

/// `indexOne`: lease an upstream, ask it for its tools, and write the entry.
///
/// The seam R3 declared and nobody implemented. It is what `POST /servers/:name/reindex` and
/// `mcp-router index` both run, which is why it lives here rather than inside either.
public struct ManifestIndexer: UpstreamIndexerPort {
    let startupTimeoutMs: Int
    let transporting: any UpstreamTransporting
    let manifestPath: String
    let fileSystem: any FileSystem
    let clock: any RouterClock
    let log: RouterLog?
    /// The daemon's bound, because `POST /servers/:name/reindex` runs this inside an async control
    /// handler. `mcp-router index` runs it too and could afford to wait longer, but the two share
    /// this type and a one-shot that fails a contended write reports it and exits — where a control
    /// handler that stalls parks a cooperative-pool thread.
    let lockTimeoutMs: Int

    public init(
        startupTimeoutMs: Int,
        transporting: any UpstreamTransporting,
        manifestPath: String,
        fileSystem: any FileSystem = RealFileSystem(),
        clock: any RouterClock = SystemClock(),
        log: RouterLog? = nil,
        lockTimeoutMs: Int = ConfigMutationLock.timeoutMilliseconds(
            default: ConfigMutationLock.daemonTimeoutMs
        )
    ) {
        self.startupTimeoutMs = startupTimeoutMs
        self.transporting = transporting
        self.manifestPath = manifestPath
        self.fileSystem = fileSystem
        self.clock = clock
        self.log = log
        self.lockTimeoutMs = lockTimeoutMs
    }

    public func index(_ upstream: UpstreamConfig) async -> IndexOutcome {
        // A pool of ONE, idle 0, torn down before this returns — `control.ts:191-199` constructs
        // exactly this and shuts it down in a `finally`, so indexing never touches the serving pool.
        //
        // It used to lease from the serving pool. That left the child alive for the whole idle
        // window after a reindex, which is two defects rather than one: the next `tools/call`
        // recorded `cold:false` where the reference records `cold:true` (the stream lane's frame
        // diff is what caught it), and a reindex from the Mac app left a subprocess running that
        // the user never called a tool on — the opposite of what this router is for.
        let pool = UpstreamPool(
            upstreams: [upstream],
            defaultIdleMilliseconds: 0,
            defaultStartupTimeoutMilliseconds: startupTimeoutMs,
            transporting: transporting,
            clock: clock,
            log: log
        )
        let outcome = await index(upstream, using: pool)
        // Not a `defer`: `defer` cannot await, and a fire-and-forget teardown would let the caller
        // observe the child still live — which is the bug this replaced.
        await pool.shutdown()
        return outcome
    }

    private func index(_ upstream: UpstreamConfig, using pool: UpstreamPool) async -> IndexOutcome {
        let tools: [CachedTool]
        do {
            let lease = try await pool.lease(upstream.name)
            let listed: JSONValue
            do {
                listed = try await lease.session.listTools()
            } catch {
                await pool.release(lease)
                throw error
            }
            await pool.release(lease)
            guard case let .object(members) = listed,
                  case let .array(items)? = members.first(where: { $0.key == JSString("tools") })?.value
            else {
                // No `cacheFailure`: nothing was written here, but nothing was ATTEMPTED either,
                // and `cacheFailure` means "the save was refused". Reporting an upstream's
                // unusable answer as a caching failure puts a filesystem line in front of a reader
                // whose filesystem is fine. `error` already carries this one.
                return IndexOutcome(tools: 0, error: "the upstream returned no tools array")
            }
            tools = items.compactMap(CachedTool.init)
        } catch {
            let reason = (error as? PoolError)?.message ?? "\(error)"
            await log?.record(LogEvent.serverIndexFailed(server: upstream.name, reason: reason))
            // The entry is still written, carrying the error — the reference records a failure
            // rather than leaving the previous tools looking current.
            let recorded = record(upstream, tools: [], error: reason)
            await reportIfLost(upstream, recorded)
            return IndexOutcome(tools: 0, error: reason, cacheFailure: recorded.cacheFailure)
        }

        let recorded = record(upstream, tools: tools, error: nil)
        var heldChanges: Int?
        if case let .heldForApproval(changeCount) = recorded.outcome {
            heldChanges = changeCount
            await log?.record(LogEvent.serverSurfaceChanged(
                server: upstream.name, changeCount: changeCount
            ))
        } else {
            await log?.record(LogEvent.serverIndexed(server: upstream.name, toolCount: tools.count))
        }
        // After the outcome's own line rather than before it: the reader wants "this is what the
        // index found" and then "and here is what happened to it", not the correction first.
        //
        // The control API's reindex route has no field to carry this, so without the log line that
        // path stays exactly as silent as the CLI's used to be.
        await reportIfLost(upstream, recorded)
        // `heldChanges` travels with `tools` rather than replacing it. Both numbers are true and
        // they answer different questions — how many tools the upstream listed, and how many of
        // them are being withheld — and the caller that prints one of them needs to know which.
        return IndexOutcome(
            tools: tools.count, cacheFailure: recorded.cacheFailure, heldChanges: heldChanges
        )
    }

    private func reportIfLost(_ upstream: UpstreamConfig, _ recorded: Recorded) async {
        guard let reason = recorded.cacheFailure else { return }
        await log?.record(IndexLogEvent.manifestNotWritten(
            server: upstream.name, path: manifestPath, reason: reason
        ))
    }

    /// What ``record(_:tools:error:)`` did: the bookkeeping's own verdict, and why the entry it
    /// produced is not on disk — `nil` when it is.
    private struct Recorded {
        let outcome: ManifestBookkeeping.Outcome
        let cacheFailure: String?
    }

    /// Write the entry through R1's bookkeeping, which owns the pending/approved rules — a second
    /// implementation here would be a second place for the surface-change semantics to drift.
    ///
    /// Returns the change count when the surface moved, so the caller can log the reference's
    /// "changed its tool surface" warning rather than reporting a silent success — and whether the
    /// entry reached disk.
    ///
    /// The save used to be `try?`, which is DEF-049: the one call that makes an index durable was
    /// the one call whose failure nothing downstream could observe. `index --force` against a home
    /// the process may read and traverse but not write printed `ok <server> (N tools)` and then, at
    /// the foot of the same run, `0 tools cached` — the second line re-reads the manifest and is
    /// right by accident of how it was written, the first reports what this function intended.
    ///
    /// The error is reported, not thrown. Propagating it would change the CLI's exit code and the
    /// control API's status for a manifest that failed to write, and both are contracts this repo
    /// has taken a decision on elsewhere (`ControlApproveDispatchTests.swift:114-118`); moving
    /// either is its own item.
    ///
    /// **R19 puts the load inside the lock.** The load was already adjacent to the save here — the
    /// window this closes is microseconds rather than the reference's seconds — but a microsecond
    /// window is still a window, and `manifest.json` had no exclusion of any kind while
    /// `servers.json` has had one since R2-W. A lock failure lands in `cacheFailure` beside a write
    /// failure, because they are the same thing to a reader: the row is not on disk and the run
    /// says so.
    private func record(
        _ upstream: UpstreamConfig, tools: [CachedTool], error: String?
    ) -> Recorded {
        // Resolved before the `do`, because `catch` binds its own `error` and shadows this one.
        let observation = error.map { ManifestBookkeeping.Observation.failure(message: $0) }
            ?? .tools(tools)
        let configHash = UpstreamHash.hash(upstream)
        // The verdict, kept where the `catch` can still read it: a save that throws has already
        // produced one, and the caller's report needs it whether or not the bytes landed.
        var applied: ManifestBookkeeping.Step?
        do {
            let step = try ConfigMutationLock.withExclusiveLock(
                forConfigAt: manifestPath, timeoutMs: lockTimeoutMs
            ) { () -> ManifestBookkeeping.Step in
                var manifest = ManifestIO.load(path: manifestPath, fileSystem: fileSystem).manifest
                let step = ManifestBookkeeping.apply(
                    previous: manifest.entry(named: upstream.name),
                    observation: observation,
                    configHash: configHash,
                    nowMilliseconds: clock.nowMilliseconds
                )
                applied = step
                manifest.setEntry(upstream.name, step.entry)
                try ManifestIO.save(manifest, toPath: manifestPath, fileSystem: fileSystem)
                return step
            }
            return Recorded(outcome: step.outcome, cacheFailure: nil)
        } catch {
            // A refused lock and a refused write are the same fact to a reader — the row is not on
            // disk — so both land in `cacheFailure`. `applied` is nil only on the first of the two,
            // where nothing was read at all; the bookkeeping against no previous entry is the
            // honest verdict there, because that is what an entry with no history produces.
            let verdict = applied ?? ManifestBookkeeping.apply(
                previous: nil,
                observation: observation,
                configHash: configHash,
                nowMilliseconds: clock.nowMilliseconds
            )
            // `localizedDescription` on a bare Swift error bridges to "the operation couldn’t be
            // completed", which would replace the lock's own sentence with nothing. A filesystem
            // error keeps it, because there it is the readable half.
            let reason = (error as? ConfigMutationLock.LockProblem)?.description
                ?? error.localizedDescription
            return Recorded(outcome: verdict.outcome, cacheFailure: reason)
        }
    }
}
