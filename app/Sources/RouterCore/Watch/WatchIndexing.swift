import Foundation

/// W3 — a server is indexed **before** it is adopted.
///
/// A server is written into the router's own list only once it has proved it starts and answers
/// `tools/list`. Otherwise a typo'd command is silently swallowed out of user scope and into a
/// config that cannot serve it — the entry disappears from the file the user typed it into and
/// reappears nowhere.
///
/// **The manifest is re-read for every entry, inside the lock (X4b, closed by R19).** The reference
/// used to load it once at the top of `cmdWatch`, spend seconds spawning and indexing children, and
/// save that stale object at the end — so a user who approved a held tool-change in the Mac app
/// mid-adoption had that approval erased. That is W10's own argument applied to the file W10 did not
/// name. Re-reading per entry shrank the window from seconds to microseconds; D-w3 was the deferred
/// child for closing it entirely, and R19 is where that happened, on both routers: the re-read now
/// happens under ``ConfigMutationLock`` on `manifest.json`'s own sidecar, so the entry that is
/// merged is the one on disk and no second writer can be between the two.
///
/// R19 demonstrated that stale save rather than arguing it: a fire held open six seconds while
/// `index --force` wrote another server's row left the manifest holding only what the fire had in
/// hand.
///
/// **The two inventories were not a pairing, and now they are.** R17 recorded them as different
/// sizes: FIVE `saveManifest` call sites on the reference against THREE `ManifestIO.save` sites
/// here, so "five" was the reference's own count and neither list mapped onto the other site for
/// site. R19 put all eight of those writers under the lock and collapsed the reference's five to
/// three, so the lists are the same length and line up verb for verb — `manifestCommitter` against
/// `ManifestIndexer` for index, import and the control re-index; `cmdWatch`'s commit closure
/// against this type; the control API's approve against `AuthRoutes`. All six commit per entry, so
/// the per-entry-against-per-run asymmetry R17 recorded is gone too. This side's count did not
/// change, but one of its sites did: R19 lifted `ManifestIndexer` out of `ServicePorts`.
///
/// R17 declared a divergence here, because the two sides disagreed about WHEN the manifest is read
/// and `parity-cli.sh` runs the binaries sequentially over separate homes, so no scenario it can
/// hold reaches the property. R19 closed it by CONVERGENCE — the reference re-reads per entry too,
/// under the same lock on the same sidecar — and the property it was declared for is now held by
/// `scripts/acceptance/parity-overlap.sh`, which drives a second writer into the middle of a watch
/// fire's window on both binaries. There is nothing left to declare, so the declaration is gone
/// rather than restated.
public struct WatchIndexer: Sendable {
    public struct Report: Sendable, Equatable {
        public var built: [String] = []
        public var failed: [String] = []
    }

    let manifestPath: String
    let startupTimeoutMs: Int
    let transporting: any UpstreamTransporting
    let fileSystem: any FileSystem
    let clock: any RouterClock
    /// The pool's own logger. The reference never configures its watcher's log, so the spawn, ready
    /// and reap lines land on **stderr** — and `cli-watch` diffs that stream.
    let poolLog: RouterLog?
    /// The watcher's bound rather than the daemon's: this is a launchd one-shot with nothing waiting
    /// on it, so it can afford to wait out a whole control-API burst rather than abandon an entry it
    /// has already paid seconds to index.
    let lockTimeoutMs: Int

    public init(
        manifestPath: String,
        startupTimeoutMs: Int,
        transporting: any UpstreamTransporting,
        fileSystem: any FileSystem = RealFileSystem(),
        clock: any RouterClock = SystemClock(),
        poolLog: RouterLog? = nil,
        lockTimeoutMs: Int = ConfigMutationLock.timeoutMilliseconds(
            default: ConfigMutationLock.watcherTimeoutMs
        )
    ) {
        self.manifestPath = manifestPath
        self.startupTimeoutMs = startupTimeoutMs
        self.transporting = transporting
        self.fileSystem = fileSystem
        self.clock = clock
        self.poolLog = poolLog
        self.lockTimeoutMs = lockTimeoutMs
    }

    /// Index every upstream in `toIndex`, writing each result as it arrives.
    ///
    /// One pool for the whole set, `idleMs` 60 000, torn down on every path — the reference's shape
    /// in `cmdWatch`'s index block, where the teardown is a `finally`. (R17 cited that block by line
    /// span; R19 changed its length, so it is cited by name here.) Not a `defer`, because `defer`
    /// cannot await and a fire-and-forget teardown would leave children alive after this returns.
    public func index(_ toIndex: [UpstreamConfig]) async -> Report {
        guard !toIndex.isEmpty else { return Report() }
        let pool = UpstreamPool(
            upstreams: toIndex,
            defaultIdleMilliseconds: 60000,
            defaultStartupTimeoutMilliseconds: startupTimeoutMs,
            transporting: transporting,
            clock: clock,
            log: poolLog
        )
        var report = Report()
        for upstream in toIndex {
            let observation = await observe(upstream, using: pool)
            // `apply` is synchronous so it can write the manifest without a suspension point in the
            // middle; the log events it produces are recorded here, where awaiting is allowed.
            var events: [LogEvent] = []
            apply(observation, to: upstream, into: &report, logging: &events)
            for event in events {
                await poolLog?.record(event)
            }
        }
        await pool.shutdown()
        return report
    }

    /// Lease, list, release. A throw anywhere becomes the failure observation, with the pool's own
    /// message so a startup timeout reads as a startup timeout.
    private func observe(
        _ upstream: UpstreamConfig, using pool: UpstreamPool
    ) async -> ManifestBookkeeping.Observation {
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
                  case let .array(items)? = members
                  .first(where: { $0.key == JSString("tools") })?.value
            else {
                return .failure(message: "the upstream returned no tools array")
            }
            return .tools(items.compactMap(CachedTool.init))
        } catch {
            return .failure(message: (error as? PoolError)?.message ?? "\(error)")
        }
    }

    /// What one locked application produced: the log line, and the report lines it contributes.
    private struct Applied {
        let event: LogEvent
        let built: [String]
        let failed: [String]
    }

    /// Apply one observation to a **freshly loaded** manifest and save it, **under the lock**.
    ///
    /// `ManifestBookkeeping.build` is what applies it, with `force: true` because staleness was
    /// decided before indexing started. Going through `build` rather than `apply` is deliberate: it
    /// is the one function that owns the reference's `built` and `failed` string formats, and a
    /// second copy of `"\(name) (\(count) tools)"` here would be a place for them to drift.
    ///
    /// The load, the merge and the save are all inside ``ConfigMutationLock`` (R19). Everything
    /// expensive is already out — the child was spawned, asked and torn down before this is called
    /// — so the hold is a parse, a dictionary write and a rename, and a concurrent control-API
    /// request never reaches the daemon's own 2000 ms bound waiting for it.
    private func apply(
        _ observation: ManifestBookkeeping.Observation,
        to upstream: UpstreamConfig,
        into report: inout Report,
        logging pending: inout [LogEvent]
    ) {
        let outcome: Applied
        do {
            outcome = try ConfigMutationLock.withExclusiveLock(
                forConfigAt: manifestPath, timeoutMs: lockTimeoutMs
            ) { () -> Applied in
                var manifest = ManifestIO.load(path: manifestPath, fileSystem: fileSystem).manifest
                let event = Self.event(
                    for: observation,
                    previous: manifest.entry(named: upstream.name),
                    server: upstream.name
                )
                let step = ManifestBookkeeping.build(
                    manifest: &manifest,
                    upstreams: [upstream],
                    force: true,
                    nowMilliseconds: { clock.nowMilliseconds },
                    observe: { _ in observation }
                )
                // R17 — the failure entry `build` just wrote is KEPT, and the backoff records it
                // too.
                //
                // Both sides used to delete it here, on the reasoning that an entry carrying an
                // error still *looks* indexed to the next reader. No reader reads it that way:
                // `WatchAdoption`'s own gate rejects an entry with an error, `ToolUnion.isStale`
                // returns true for it, `ToolUnion.union` skips a zero-tool entry, and
                // `UpstreamStateReport` reads `error` as the `detail` it puts in front of the user.
                // Deleting it erased the attempt from the one file those readers join through;
                // `watch-state.json` kept the reason, and nothing reads it — measured on the
                // owner's machine on 2026-08-21, where `namecheap` failed `Connection closed` every
                // five minutes and `/servers` reported `error: None, tools: 0, state: idle`, the
                // reason surviving only in watch-state.json.
                //
                // That account is SUFFICIENT and not EXCLUSIVE — R19. A second mechanism erased a
                // freshly-written row even after this fix, on the reference side, with no delete
                // statement in its path: it loaded the manifest once per run and saved that same
                // object at the end. The owner's measurement came from a timeline where the launchd
                // watch agent and an `index --force` were both live, so what was seen is consistent
                // with either. R19 has since CLOSED that mechanism on both routers — this save and
                // the load above it are one locked span, and the reference's run-level save is gone
                // — so it is history rather than a live alternative. The route account is kept for
                // the ASYMMETRY between the two servers, which is what makes it survive R19 rather
                // than merely fit beside it: a stale save can only erase a row written by SOMEONE
                // ELSE during the window, and a staged server is in every fire's own hand, so an
                // R19-only world predicts `namecheap` KEEPS its row while unstaged `lifeline` loses
                // one — the opposite of what was measured. The pre-registered prediction held too:
                // stage `lifeline` as well and its row starts disappearing.
                //
                // The backoff is untouched: it is the retry policy, and this row is the record.
                try? ManifestIO.save(manifest, toPath: manifestPath, fileSystem: fileSystem)
                return Applied(event: event, built: step.built, failed: step.failed)
            }
        } catch {
            // The lock was refused, so nothing was read and nothing was written — which is what
            // `try?` around the save already meant for a write that failed. The INDEX still
            // happened, and it is still reported: a server that vanishes from the report entirely
            // is how DEF-049 printed `ok` over a manifest that did not exist.
            //
            // Derived against an empty manifest, because with no previous entry there is no
            // held-for-approval case — and that is the one verdict the observation alone cannot
            // decide. A run that could not read the file cannot know which of the two it was, and
            // claiming the held one would be inventing a diff against a surface nobody read.
            var unread = Manifest.empty
            let step = ManifestBookkeeping.build(
                manifest: &unread,
                upstreams: [upstream],
                force: true,
                nowMilliseconds: { clock.nowMilliseconds },
                observe: { _ in observation }
            )
            outcome = Applied(
                event: Self.event(for: observation, previous: nil, server: upstream.name),
                built: step.built,
                failed: step.failed
            )
        }
        pending.append(outcome.event)
        report.built.append(contentsOf: outcome.built)
        report.failed.append(contentsOf: outcome.failed)
    }

    /// The line the reference's `buildManifest` logs for one upstream.
    ///
    /// Derived from the observation and the previous entry rather than parsed back out of `build`'s
    /// report strings, which would make a log line depend on the shape of a message. `cli-watch`
    /// diffs that stream, so it is one function and not two.
    private static func event(
        for observation: ManifestBookkeeping.Observation,
        previous: CachedServer?,
        server: String
    ) -> LogEvent {
        switch observation {
        case let .failure(message):
            .serverIndexFailed(server: server, reason: message)
        case let .tools(tools):
            if previous?.hasDigest == true,
               previous?.digest != JSString(ToolsDigest.digest(of: tools))
            {
                .serverSurfaceChanged(
                    server: server,
                    changeCount: DiffTools.diff(before: previous?.tools ?? [], after: tools).count
                )
            } else {
                .serverIndexed(server: server, toolCount: tools.count)
            }
        }
    }
}
