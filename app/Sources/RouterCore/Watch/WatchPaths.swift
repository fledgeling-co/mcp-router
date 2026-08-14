import Foundation

/// Where the watcher reads and writes, and what it restarts.
///
/// **`~/.claude.json` is resolved from `HOME` in the environment**, not from `NSHomeDirectory()`
/// (X10, W-D2). Measured on 2026-08-15: under `HOME=/tmp/fakehome`, node's `os.homedir()` returns
/// `/tmp/fakehome` and `NSHomeDirectory()` returns the real account's directory. Reproducing the
/// reference therefore *requires* reading the environment — and a watcher that did not would, the
/// first time the parity lane ran it, adopt and delete servers out of the developer's own
/// `~/.claude.json`. This is a safety property as much as a parity one.
public struct WatchPaths: Sendable {
    public let claudeJSON: String
    public let statePath: String
    public let logPath: String
    public let backupDirectory: String
    /// The launchd job restarted after an adoption.
    ///
    /// The reference hardcodes this (`watch.ts:49`). It is overridable here because it is not
    /// otherwise testable: measured on 2026-08-15, `gg.rhodes.mcp-router` was loaded and serving on
    /// this machine, so an un-overridable label would make every run of the parity lanes restart the
    /// developer's live router — a test whose cost is the thing under test. The default is the
    /// reference's value, so an unset environment behaves identically (W-D8).
    public let launchdLabel: String

    public static let defaultLaunchdLabel = "gg.rhodes.mcp-router"

    /// `~/.claude.json` is the staging area every MCP client writes into, and it is the one path
    /// here that is **not** under `MCP_ROUTER_HOME` — moving the router's home must not move the
    /// file the router is watching.
    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory(),
        home: RouterHome? = nil
    ) {
        let resolvedHome = environment["HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? homeDirectory
        claudeJSON = (resolvedHome as NSString).appendingPathComponent(".claude.json")

        let routerHome = home ?? RouterHome(
            environment: environment, homeDirectory: resolvedHome
        )
        let root = routerHome.root as NSString
        statePath = root.appendingPathComponent("watch-state.json")
        logPath = root.appendingPathComponent("watch.log")
        backupDirectory = root.appendingPathComponent("backups")
        launchdLabel = environment["MCPR_LAUNCHD_LABEL"].flatMap { $0.isEmpty ? nil : $0 }
            ?? Self.defaultLaunchdLabel
    }
}
