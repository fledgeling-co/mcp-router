import Foundation
import Testing
@testable import RouterCore

/// `D-w2` — `import` resolved `~/.claude.json` from `NSHomeDirectory()`, which ignores `$HOME`.
///
/// The pairing lives in ``ImportPaths`` rather than in `ImportVerb` because `MCPRouterCLI` is an
/// executable target with no test target: a test written against `RouterHome(homeDirectory:)` with
/// an already-resolved value would assert that `RouterHome.init` does what it plainly does, and
/// would stay green against the very mutation it exists to catch.
@Suite("Import paths")
struct ImportPathsTests {
    @Test("P1 — the home comes from the environment, as os.homedir() does")
    func homeComesFromTheEnvironment() {
        let paths = ImportPaths(
            environment: ["HOME": "/tmp/fakehome"], homeDirectory: "/Users/real"
        )
        #expect(paths.claudeJSON == "/tmp/fakehome/.claude.json")
    }

    @Test("P2 — an empty HOME falls back to the account directory")
    func anEmptyHomeFallsBackToTheAccount() {
        let paths = ImportPaths(environment: ["HOME": ""], homeDirectory: "/Users/real")
        #expect(paths.claudeJSON == "/Users/real/.claude.json")
    }

    @Test("P3 — an absent HOME falls back to the account directory")
    func anAbsentHomeFallsBackToTheAccount() {
        let paths = ImportPaths(environment: [:], homeDirectory: "/Users/real")
        #expect(paths.claudeJSON == "/Users/real/.claude.json")
    }

    /// The A2.2 invariant, and the assertion that kills the mutation.
    ///
    /// `docs/install.sh:77` runs `import` with neither `--from` nor `MCP_ROUTER_HOME`, so the
    /// staging file and the destination both come off `homedir()`. Two homes in one run is not a
    /// shape the reference can produce (`src/config.ts:79`).
    @Test("P4 — both paths come from one resolved home when MCP_ROUTER_HOME is unset")
    func bothPathsComeFromOneHome() {
        let paths = ImportPaths(
            environment: ["HOME": "/tmp/fakehome"], homeDirectory: "/Users/real"
        )
        #expect(paths.claudeJSON == "/tmp/fakehome/.claude.json")
        #expect(paths.routerHome.configPath == "/tmp/fakehome/.claude/mcp-router/servers.json")
        // Stated as the property rather than as two literals: neither path may reach the account
        // directory when HOME says otherwise.
        #expect(!paths.routerHome.root.hasPrefix("/Users/real"))
    }

    @Test("P5 — MCP_ROUTER_HOME still wins for the destination only")
    func mcpRouterHomeStillWins() {
        let paths = ImportPaths(
            environment: ["HOME": "/tmp/fakehome", "MCP_ROUTER_HOME": "/tmp/elsewhere"],
            homeDirectory: "/Users/real"
        )
        #expect(paths.routerHome.root == "/tmp/elsewhere")
        // The staging file is NOT under the router home — moving the home must not move the file
        // the router imports from.
        #expect(paths.claudeJSON == "/tmp/fakehome/.claude.json")
    }

    @Test("P6 — WatchPaths and ImportPaths agree on the same environment")
    func theTwoResolversAgree() {
        let environment = ["HOME": "/tmp/fakehome"]
        let watch = WatchPaths(environment: environment, homeDirectory: "/Users/real")
        let importing = ImportPaths(environment: environment, homeDirectory: "/Users/real")
        // One rule, one implementation. If these ever disagree the refactor that unified them has
        // been undone.
        #expect(watch.claudeJSON == importing.claudeJSON)
        #expect(watch.routerHome.root == importing.routerHome.root)
    }
}
