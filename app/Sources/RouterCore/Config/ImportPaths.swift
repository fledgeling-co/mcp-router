import Foundation

/// The two paths `mcp-router import` reads and writes, resolved from **one** home.
///
/// The reference's `cmdImport` takes `~/.claude.json` from `join(homedir(), '.claude.json')` and
/// its destination from `ROUTER_HOME`, which is `process.env.MCP_ROUTER_HOME || join(homedir(),
/// '.claude', 'mcp-router')` (`src/config.ts:79`). **Both come from one `homedir()` call**, so two
/// homes in one import run is not a shape the reference can produce — the same invariant
/// ``WatchPaths`` records for the watcher.
///
/// This is a type rather than two lines inside `ImportVerb` because `MCPRouterCLI` is an executable
/// target with no test target: anything left in the verb is unreachable by `swift test`, and the
/// pairing is exactly the property that needs a test. Asserting on `RouterHome(homeDirectory:)`
/// with an already-resolved value instead would assert that `RouterHome.init` does what it plainly
/// does, and would stay green against the mutation it exists to catch.
///
/// `D-w2`: `ImportVerb.swift:22` used `NSHomeDirectory()`, which ignores `$HOME`. It was unreached
/// only because `cli-import` always passes `--from`; `docs/install.sh:77` runs `import` with
/// neither `--from` nor `MCP_ROUTER_HOME`, so the installer's own invocation depended on both
/// defaults being wrong together.
public struct ImportPaths: Sendable {
    /// The staging file, and the one path here that is **not** under `MCP_ROUTER_HOME` — moving the
    /// router's home must not move the file the router imports from.
    public let claudeJSON: String
    /// Where the adopted servers land. `MCP_ROUTER_HOME` still wins, exactly as before.
    public let routerHome: RouterHome

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) {
        let home = RouterHome.resolvedHomeDirectory(
            environment: environment, homeDirectory: homeDirectory
        )
        claudeJSON = (home as NSString).appendingPathComponent(".claude.json")
        routerHome = RouterHome(environment: environment, homeDirectory: home)
    }
}
