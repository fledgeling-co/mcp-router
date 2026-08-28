import Foundation
import RouterCore

/// `mcp-router index` and `refresh`.
///
/// Split out of `MCPRouterCLI.swift` because that file outgrew the 400-line limit when M29 taught
/// this verb to leave disabled upstreams alone. The cut is at the MARK that was already there.
extension MCPRouterCLI {
    /// Which upstreams this run has to spawn, and why.
    ///
    /// Lifted out of ``index(_:)`` when R31 gave it a second staleness question and took it past
    /// this repository's 60-line body cap. The split is real rather than arithmetic: what a run
    /// has to do is decided from three readings and is worth being able to state on its own.
    struct Work {
        /// Servers this verb will consider at all.
        ///
        /// A disabled server is not indexed here, and the count says so rather than quietly
        /// shrinking. Indexing spawns the child process, which is the one thing disabling is for,
        /// and there is nothing to gain: disabling leaves the manifest row, the digest and the
        /// approved surface exactly where they were. `POST /servers/:name/reindex` names one
        /// server and is the user asking, so it stays available on a disabled upstream.
        let servable: [UpstreamConfig]
        let disabled: Int
        /// The server's **identity** moved — the reference's own test, unchanged by R31.
        let stale: [UpstreamConfig]
        /// The code behind an identity that stayed put moved — R31's content component.
        ///
        /// This is what an `npx -y pkg@latest` upstream needs: its command, args and env are the
        /// same bytes on every publish. It is asked HERE and not in `serve`, because a content
        /// probe at start-up would re-derive every row the first time a router met a manifest
        /// written before that member existed, and re-deriving a row means spawning the child.
        /// That is the cost the router exists to remove; paying it on a deliberate `index` is a
        /// different trade from paying it on boot.
        let moved: [UpstreamConfig]
        private let movedNames: Set<String>

        init(upstreams: [UpstreamConfig], manifest: Manifest, probe: any CacheProbing) {
            servable = upstreams.filter { $0.disabled != true }
            disabled = upstreams.count - servable.count
            stale = servable.filter { ToolUnion.isStale(manifest, $0) }
            moved = servable.filter { upstream in
                !ToolUnion.isStale(manifest, upstream)
                    && ContentStaleness.verdict(
                        manifest: manifest, upstream: upstream, probe: probe
                    ).hasMoved
            }
            movedNames = Set(moved.map(\.name))
        }

        func needsIndexing(_ upstream: UpstreamConfig) -> Bool {
            stale.contains { $0.name == upstream.name } || movedNames.contains(upstream.name)
        }
    }

    static func index(_ arguments: [String]) async throws {
        let options = try Flags(arguments)
        let (loaded, home) = try load(options)
        let log = RouterLog()
        await log.configure(file: loaded.config.logPath, verbose: options.has("verbose"))

        // R31. The content component of the manifest key: what the upstream currently runs, as
        // opposed to what its config says. `MCP_ROUTER_CACHE_HOME` moves both cache roots together
        // so a lane never reaches the operator's own 2.0 GB npx cache.
        let probe = DiskCacheProbe(roots: CacheRoots.under(
            home: ProcessInfo.processInfo.environment["MCP_ROUTER_CACHE_HOME"] ?? NSHomeDirectory()
        ))
        let indexer = ManifestIndexer(
            startupTimeoutMs: loaded.config.startupTimeoutMs,
            transporting: RoutingUpstreamTransport(log: log),
            manifestPath: loaded.config.manifestPath, log: log, contentProbe: probe
        )
        let force = options.has("force")
        let manifest = ManifestIO.load(
            path: loaded.config.manifestPath, fileSystem: RealFileSystem()
        ).manifest
        let work = Work(upstreams: loaded.config.upstreams, manifest: manifest, probe: probe)
        Out.print(
            "\(loaded.config.upstreams.count) upstreams, \(work.stale.count) need indexing"
                + (work.moved.isEmpty ? "" : ", \(work.moved.count) changed behind an unchanged config")
                + (force ? " (forced: all)" : "")
                + (work.disabled > 0 ? ", \(work.disabled) disabled and not indexed" : "") + "\n"
        )

        var report = IndexReport()
        for upstream in work.servable where force || work.needsIndexing(upstream) {
            let outcome = await indexer.index(upstream)
            report.add(upstream, outcome)
        }

        for line in report.built {
            Out.print("  ok    \(line)\n")
        }
        for line in report.failed {
            Out.print("  FAIL  \(line)\n")
        }
        // Deliberately not folded into `FAIL`, and deliberately not aligned with the other two.
        // These servers started, answered, and produced a row that never reached the manifest —
        // reporting that as either half of the ordinary pass/fail pair is what let DEF-049 print
        // `ok` over a file that does not exist.
        for line in report.lost {
            Out.print("  not cached  \(line)\n")
        }
        let after = ManifestIO.load(
            path: loaded.config.manifestPath, fileSystem: RealFileSystem()
        ).manifest
        let count = ToolUnion.unionTools(
            manifest: after, upstreams: loaded.config.upstreams
        ).count
        Out.print("\n\(count) tools cached -> \(loaded.config.manifestPath)\n")
        // The count above is re-read from disk. Without this line a run whose writes were all
        // refused prints the same `0 tools cached` as a run with nothing to cache, and the reader
        // cannot tell which they are looking at.
        //
        // The claim is about what was RECORDED, not about what the count contains, and it is scoped
        // to the lost servers. Four wordings died on four different shapes this verb reaches:
        //
        // - "these are missing from that count" — false when a server's previous row is still on
        //   disk and being counted.
        // - "the count is as it stood before this run" — false when a SIBLING server's write landed
        //   and moved it.
        // - "nothing this run read from them is in that count" — false when the refused update
        //   carried the SAME tools the older row already holds: `echo` is then both what this run
        //   read and what the count includes.
        // - "whatever they contribute to it is from an earlier run" — vacuous, and misleading, on
        //   the shape the defect was FOUND in: a home that has never been written has no earlier
        //   run and no file, and a reader is told to go looking for one.
        //
        // A statement about the write survives all four, because the write is the thing that did
        // not happen. Nothing from this run was recorded for these servers, whatever the count
        // happens to hold and wherever it came from.
        if !report.lost.isEmpty {
            Out.print(
                "\(report.lost.count) server(s) above did not reach the manifest, so nothing this "
                    + "run indexed for them was recorded in that count.\n"
            )
        }
        Out.print("All upstreams closed; none will open again until a tool is called.\n")
        _ = home
    }
}
