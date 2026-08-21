import Foundation

/// W3 — a server is indexed **before** it is adopted.
///
/// A server is written into the router's own list only once it has proved it starts and answers
/// `tools/list`. Otherwise a typo'd command is silently swallowed out of user scope and into a
/// config that cannot serve it — the entry disappears from the file the user typed it into and
/// reappears nowhere.
///
/// **The manifest is re-read for every entry (X4b).** The reference loads it once (`watch.ts:212`),
/// spends seconds spawning and indexing children, and saves the stale object at `:253` — so a user
/// who approves a held tool-change in the Mac app mid-adoption has that approval erased. That is
/// W10's own argument applied to the file W10 did not name. Re-reading per entry shrinks the window
/// from seconds to the same microseconds the daemon's own manifest writers already have; closing it
/// entirely is deferred child D-w3.
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

    public init(
        manifestPath: String,
        startupTimeoutMs: Int,
        transporting: any UpstreamTransporting,
        fileSystem: any FileSystem = RealFileSystem(),
        clock: any RouterClock = SystemClock(),
        poolLog: RouterLog? = nil
    ) {
        self.manifestPath = manifestPath
        self.startupTimeoutMs = startupTimeoutMs
        self.transporting = transporting
        self.fileSystem = fileSystem
        self.clock = clock
        self.poolLog = poolLog
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

    /// Apply one observation to a **freshly loaded** manifest and save it.
    ///
    /// `ManifestBookkeeping.build` is what applies it, with `force: true` because staleness was
    /// decided before indexing started. Going through `build` rather than `apply` is deliberate: it
    /// is the one function that owns the reference's `built` and `failed` string formats, and a
    /// second copy of `"\(name) (\(count) tools)"` here would be a place for them to drift.
    private func apply(
        _ observation: ManifestBookkeeping.Observation,
        to upstream: UpstreamConfig,
        into report: inout Report,
        logging pending: inout [LogEvent]
    ) {
        var manifest = ManifestIO.load(path: manifestPath, fileSystem: fileSystem).manifest
        // The reference's `buildManifest` logs one line per upstream, on the pool's own logger,
        // and `cli-watch` diffs that stream. The outcome is derived from the observation and the
        // previous entry rather than parsed back out of `build`'s report strings, which would make
        // a log line depend on the shape of a message.
        let previous = manifest.entry(named: upstream.name)
        let event: LogEvent = switch observation {
        case let .failure(message):
            .serverIndexFailed(server: upstream.name, reason: message)
        case let .tools(tools):
            if previous?.hasDigest == true,
               previous?.digest != JSString(ToolsDigest.digest(of: tools))
            {
                .serverSurfaceChanged(
                    server: upstream.name,
                    changeCount: DiffTools.diff(before: previous?.tools ?? [], after: tools).count
                )
            } else {
                .serverIndexed(server: upstream.name, toolCount: tools.count)
            }
        }
        let step = ManifestBookkeeping.build(
            manifest: &manifest,
            upstreams: [upstream],
            force: true,
            nowMilliseconds: { clock.nowMilliseconds },
            observe: { _ in observation }
        )
        // R17 — the failure entry `build` just wrote is KEPT, and the backoff records it too.
        //
        // Both sides used to delete it here, on the reasoning that an entry carrying an error still
        // *looks* indexed to the next reader. No reader reads it that way: `WatchAdoption`'s own
        // gate rejects an entry with an error, `ToolUnion.isStale` returns true for it,
        // `ToolUnion.union` skips a zero-tool entry, and `UpstreamStateReport` reads `error` as the
        // `detail` it puts in front of the user. Deleting it erased the only durable record that
        // the router had tried the server at all — measured on the owner's machine on 2026-08-21,
        // where `namecheap` failed `Connection closed` every five minutes and `/servers` reported
        // `error: None, tools: 0, state: idle`, the reason surviving only in watch-state.json.
        //
        // The backoff is untouched: it is the retry policy, and this row is the record.
        try? ManifestIO.save(manifest, toPath: manifestPath, fileSystem: fileSystem)
        pending.append(event)
        report.built.append(contentsOf: step.built)
        report.failed.append(contentsOf: step.failed)
    }
}
