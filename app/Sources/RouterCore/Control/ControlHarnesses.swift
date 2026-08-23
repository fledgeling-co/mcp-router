import Foundation

/// Where the harness reading comes from.
///
/// A seam rather than a direct call for the reason every other port in this directory is one: the
/// interesting states are ones a real machine will not enter on request. A harness whose config is
/// unreadable, a machine with no harnesses at all, and a harness that is wired *and* duplicating
/// are the three readings this route exists to carry, and a test that can only produce the
/// developer's own `$HOME` can produce none of them.
public protocol HarnessInventorySource: Sendable {
    /// Every detected harness compared against the router's own upstreams, in
    /// ``MCPClient/allCases`` order so two reads agree.
    func reports(upstreams: [UpstreamConfig], port: Int) -> [HarnessReport]
}

/// The real one: read every harness config off disk and diff it against the router's upstreams.
///
/// **Global scope only.** `projectDirectory` is deliberately nil — the daemon's working directory
/// is wherever launchd started it, never the project a session is running in, so asking for
/// project scope here would compare against a directory nobody chose. R7-C4 owns project-scoped
/// entries and R16 is the same blind spot from the adoption side.
public struct DiskHarnessInventory: HarnessInventorySource {
    let homeDirectory: String

    public init(homeDirectory: String = RouterHome.resolvedHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }

    public func reports(upstreams: [UpstreamConfig], port: Int) -> [HarnessReport] {
        HarnessReconciliation.reportAll(
            inventory: ClientConfigs.inventory(
                homeDirectory: homeDirectory, projectDirectory: nil, routerPort: port
            ),
            upstreams: upstreams,
            port: port
        )
    }
}

/// `GET /harnesses` — the route `R7-C1` deferred and `M22` absorbed.
///
/// It exists because the Mac app may not read a harness configuration file itself:
/// `scripts/lint/no-raw-design-values.sh`'s A36 rule forbids `FileManager`, `Data(contentsOf:)`,
/// `URL(fileURLWithPath:)`, `Bundle`, `Process(` and every socket type anywhere under `Boards/`,
/// with the note that reading a file is one of the ways past the API. So the board and this route
/// ship together or neither does.
///
/// **This file names ``HarnessReport`` and writes nothing, and that is load-bearing.**
/// `scripts/lint/no-harness-config-writes.sh` rule 2 fails any file that pairs R7's reconciliation
/// API with a write call — which is why this is not a case inside `ControlHandler.swift`, where
/// `ConfigEdit.edit` writes `servers.json` two screens away.
///
/// It **diverges from `src/control.ts`**, which answers this path 404. That divergence is declared
/// in `planning/parity/surface.tsv` as `div-m22-harnesses` and asserted at both binaries by
/// `scripts/acceptance/parity-divergence.sh`, so it can never quietly become an accidental one.
extension ControlHandler {
    func harnessesResponse(_ deps: ControlDeps) -> ControlAPIResponse {
        guard let source = deps.harnesses else {
            // The same shape `/registry/search` uses when its one dependency is absent: say which
            // capability is missing rather than answering an empty list, because an empty list is
            // indistinguishable from a machine with no harnesses on it — and that is the exact
            // reading this board exists to make.
            return .error(503, "harness detection is unavailable: this router has no inventory source")
        }
        let reports = source.reports(
            upstreams: deps.upstreams.map(\.upstream), port: deps.config.port
        )
        return .json(200, HarnessReportJSON.envelope(
            reports, port: deps.config.port, readAtMilliseconds: deps.clock.nowMilliseconds
        ))
    }
}
