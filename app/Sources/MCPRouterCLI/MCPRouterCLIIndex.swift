import Foundation
import RouterCore

/// `mcp-router index` and `refresh`.
///
/// Split out of `MCPRouterCLI.swift` because that file outgrew the 400-line limit when M29 taught
/// this verb to leave disabled upstreams alone. The cut is at the MARK that was already there.
extension MCPRouterCLI {
    static func index(_ arguments: [String]) async throws {
        let options = try Flags(arguments)
        let (loaded, home) = try load(options)
        let log = RouterLog()
        await log.configure(file: loaded.config.logPath, verbose: options.has("verbose"))

        let indexer = ManifestIndexer(
            startupTimeoutMs: loaded.config.startupTimeoutMs,
            transporting: RoutingUpstreamTransport(log: log),
            manifestPath: loaded.config.manifestPath, log: log
        )
        let force = options.has("force")
        let manifest = ManifestIO.load(
            path: loaded.config.manifestPath, fileSystem: RealFileSystem()
        ).manifest
        // A disabled server is not indexed by this verb, and the count says so rather than quietly
        // shrinking. Indexing spawns the child process, which is the one thing disabling is for,
        // and there is nothing to gain: disabling leaves the manifest row, the digest and the
        // approved surface exactly where they were. `POST /servers/:name/reindex` names one server
        // and is the user asking, so it stays available on a disabled upstream.
        let servable = loaded.config.upstreams.filter { $0.disabled != true }
        let off = loaded.config.upstreams.count - servable.count
        let stale = servable.filter { ToolUnion.isStale(manifest, $0) }
        Out.print(
            "\(loaded.config.upstreams.count) upstreams, \(stale.count) need indexing"
                + (force ? " (forced: all)" : "")
                + (off > 0 ? ", \(off) disabled and not indexed" : "") + "\n"
        )

        var report = IndexReport()
        for upstream in servable where force || ToolUnion.isStale(manifest, upstream) {
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
