import Foundation

/// W3 — a server is indexed **before** it is adopted.
///
/// A server is written into the router's own list only once it has proved it starts and answers
/// `tools/list`. Otherwise a typo'd command is silently swallowed out of user scope and into a
/// config that cannot serve it — the entry disappears from the file the user typed it into and
/// reappears nowhere.
///
/// **The manifest is re-read for every entry, inside the lock (X4b, closed by R19).** The reference
/// used to load it once (`watch.ts:212`), spend seconds spawning and indexing children, and save
/// the stale object — so a user who approved a held tool-change in the Mac app mid-adoption had that
/// approval erased. That is W10's own argument applied to the file W10 did not name. Re-reading per
/// entry shrank the window from seconds to microseconds; D-w3 was the deferred child for closing it
/// entirely, and R19 is where that happened, on both routers: the re-read now happens under
/// ``ConfigMutationLock`` on `manifest.json`'s own sidecar, so the entry that is merged is the one
/// on disk and no second writer can be between the two.
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
    /// at `watch.ts:232-256`, where the teardown is a `finally`. Not a `defer`, because `defer`
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
                // A failure is recorded in this watcher's own backoff, never as a manifest entry: an
                // entry carrying an error still *looks* indexed to the next reader, and the
                // reference deletes it for exactly that reason. Inside the same locked span as the
                // write that produced it, so no reader can observe the row this watcher has already
                // decided not to keep.
                if !step.failed.isEmpty {
                    Self.removeEntry(named: upstream.name, from: &manifest)
                }
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

    /// `delete manifest.servers[name]`, preserving the order of everything else.
    ///
    /// Local rather than a new method on ``Manifest``: that type is R1's and is byte-identical on
    /// several in-flight branches, so adding to it would manufacture a merge conflict for a
    /// capability only this file needs.
    static func removeEntry(named name: String, from manifest: inout Manifest) {
        guard case let .object(entries)? = manifest.serversValue else { return }
        let target = JSString(name)
        manifest.setTopLevel("servers", .object(entries.filter { $0.key != target }))
    }
}
