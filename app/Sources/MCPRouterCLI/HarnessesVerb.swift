import Foundation
import RouterCore

/// `mcp-router harnesses` — **R7**.
///
/// The verb that makes the brief's measurement reproducible from the shipped binary instead of
/// from a page of `python3 -c` against the developer's own files. It answers, per harness: how it
/// reaches this router, what it declares that the router already fronts, and what a fix would
/// change.
///
/// It is dispatched **before** ``MCPRouterCLI/dispatchReferenceVerb(_:)``, exactly as
/// `install-entry` is, so the arm list that mirrors `src/index.ts` stays one-to-one and readable
/// against it. It is absent from `Copy.usage` for the same reason: `cli-help` is a proven parity
/// row comparing all four help arms at both binaries, and a verb in the usage block that the
/// reference does not have turns it red. `parity-cli.sh`'s unknown-verb arm uses the literal
/// `not-a-real-verb`, which this does not shadow.
///
/// **It writes nothing.** Every harness config is opened for reading; the plan it prints is
/// applied by nobody. See `planning/specs/spec-R7.md` §7.
enum HarnessesVerb {
    /// Exit 0 whenever the measurement succeeded, **including when what it found is bad**.
    ///
    /// A misconfigured harness is this command's subject, not its failure: a non-zero exit for a
    /// true report would make every caller unable to tell a finding from a broken tool. Exit 1 is
    /// for the router's own config being unreadable, which is the one case where the right-hand
    /// side of every comparison is missing and no answer can be given at all.
    static func run(_ arguments: [String]) throws {
        let options = try Flags(arguments)
        let port = try options.number("port") ?? RouterHome.defaultPort
        let home = RouterHome()
        let loaded = try ConfigLoader.load(
            options: ConfigLoader.Options(
                configPath: options.value("config"), port: options.number("port"),
                host: options.value("host"), idleMs: nil
            ),
            home: home,
            fileSystem: RealFileSystem()
        )
        let upstreams = loaded.config.upstreams
        let inventory = ClientConfigs.inventory(
            homeDirectory: RouterHome.resolvedHomeDirectory(),
            projectDirectory: FileManager.default.currentDirectoryPath,
            routerPort: port
        )
        let reports = HarnessReconciliation.reportAll(
            inventory: inventory, upstreams: upstreams, port: port
        )
        Out.print(
            options.has("json")
                ? json(reports, port: port)
                : text(reports, upstreams: upstreams, port: port)
        )
    }

    static func text(_ reports: [HarnessReport], upstreams: [UpstreamConfig], port: Int) -> String {
        var out = "router on 127.0.0.1:\(port) — \(upstreams.count) upstream(s)\n\n"
        for report in reports {
            out += "\(report.client.displayName)\n"
            out += "  \(report.path)\n"
            if let unreadable = report.unreadable {
                out += "  could not be read: \(unreadable)\n\n"
                continue
            }
            if !report.exists {
                out += "  no config file — this harness is not configured on this machine\n\n"
                continue
            }
            out += "  \(report.headline)\n"
            out += "  \(report.capability.summary)\n"
            if !report.duplicates.isEmpty {
                out += "  the router already serves:\n"
                for duplicate in report.duplicates {
                    out += "    \(duplicate.described)\n"
                }
            }
            for line in report.unparsed {
                out += "  unreadable entry, so it was not compared: \(line)\n"
            }
            if let remedy = report.remedy {
                out += "  \(remedy)\n"
            }
            out += "\n"
        }
        out += "Global scope only: project-scoped entries are not read (R7-C4).\n"
        out += "Nothing here writes a harness config. The plans below apply themselves to nothing.\n\n"
        for plan in reports.map({ ReconciliationPlan.from($0) }) where !plan.isEmpty {
            out += plan.render()
        }
        return out
    }

    /// The same report as JSON — encoded by ``HarnessReportJSON``, which `GET /harnesses` shares.
    ///
    /// It used to be built here, and M22 moved it because there are now two consumers of one
    /// measurement: this verb, which `scripts/acceptance/r7-harness-reconciliation.sh` asserts
    /// against, and the control route the Mac app draws. Two encoders would let the lane keep
    /// passing while the board read something else.
    ///
    /// **`unreadable` is still the member a consumer reads first**, for the reason recorded on the
    /// encoder: a config that could not be read reaches it as an empty report, so `state` says
    /// `not-wired` and `duplicateCount` says 0 — the same bytes a clean unwired harness produces.
    static func json(_ reports: [HarnessReport], port: Int) -> String {
        JSStringify.compact(
            HarnessReportJSON.envelope(
                reports, port: port, readAtMilliseconds: SystemClock().nowMilliseconds
            )
        ) + "\n"
    }
}
