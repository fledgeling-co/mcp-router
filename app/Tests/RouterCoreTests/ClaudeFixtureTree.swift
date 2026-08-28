import Foundation
@testable import RouterCore

/// A `~/.claude`-shaped directory, built from nothing, for R30's suite to move things out of.
///
/// **The real tree is never read and never written by anything in this suite.** The shape here is
/// copied from a measurement of the real one taken on 2026-08-28, and every number the tests assert
/// is a number this builder chose:
///
/// | what | in the real tree | here |
/// |---|---|---|
/// | skills, of which readable | 24, 22 | 3, 2 |
/// | installed plugin records | 127 | 3 |
/// | records whose `installPath` is missing | 1 | 1 |
/// | records resolving without a descriptor | 2 | 1 |
/// | marketplaces | 7 | 2 |
/// | plugin names in two marketplaces at once | 13 | 2 |
/// | `settings.json` top-level members | 22 | 8 |
///
/// The `settings.json` written here carries the real file's **shape** — `env`, `permissions`,
/// `hooks`, `model`, `statusLine`, `includeCoAuthoredBy`, `enabledPlugins`,
/// `extraKnownMarketplaces` — with values invented for the fixture. No value from the real file is
/// reproduced anywhere in this repository.
enum ClaudeFixtureTree {
    @discardableResult
    static func build(at root: String) -> String {
        let manager = FileManager.default
        try? manager.createDirectory(atPath: root, withIntermediateDirectories: true)

        // Two readable skills and one that carries no SKILL.md at all — the unidentifiable case,
        // which must be reported and left where it is.
        skill("graphify", at: root, description: "turns a folder into a graph")
        skill("mermaid-diagrams", at: root, description: "draws diagrams", extra: "notes/why.md")
        write("", to: "\(root)/skills/half-installed/README.md")

        // Two marketplaces, both readable. `fledgeling-plugins` is in extraKnownMarketplaces and
        // `claude-code-plugins` is not, which is the built-in-versus-added split the real tree has.
        marketplace("fledgeling-plugins", at: root)
        marketplace("claude-code-plugins", at: root)

        // The colliding pair: one plugin name, two marketplaces, exactly as `code-review`,
        // `design-craft` and eleven others sit on the real machine.
        plugin("code-review", marketplace: "fledgeling-plugins", version: "2.1.0", at: root)
        plugin("code-review", marketplace: "claude-code-plugins", version: "1.4.2", at: root)
        // A version directory with no descriptor: resolvable, unidentifiable, left alone.
        try? manager.createDirectory(
            atPath: "\(root)/plugins/cache/fledgeling-plugins/swift-lsp/1.0.0",
            withIntermediateDirectories: true
        )
        write("nothing here", to: "\(root)/plugins/cache/fledgeling-plugins/swift-lsp/1.0.0/README.md")

        write(installedPlugins(root: root), to: "\(root)/plugins/installed_plugins.json")
        write(settings(), to: "\(root)/settings.json")
        return root
    }

    /// The register, naming four plugins: two readable, one with no descriptor, and one whose
    /// `installPath` is not on disk at all.
    static func installedPlugins(root: String) -> String {
        let cache = "\(root)/plugins/cache"
        return """
        {
          "version": 1,
          "plugins": {
            "code-review@fledgeling-plugins": [
              {"scope": "user", "installPath": "\(cache)/fledgeling-plugins/code-review/2.1.0",
               "version": "2.1.0"}
            ],
            "code-review@claude-code-plugins": [
              {"scope": "user", "installPath": "\(cache)/claude-code-plugins/code-review/1.4.2",
               "version": "1.4.2"}
            ],
            "swift-lsp@fledgeling-plugins": [
              {"scope": "user", "installPath": "\(cache)/fledgeling-plugins/swift-lsp/1.0.0",
               "version": "1.0.0"}
            ],
            "studio-proxy@fledgeling-plugins": [
              {"scope": "user", "installPath": "\(cache)/fledgeling-plugins/studio-proxy/0.9.0",
               "version": "0.9.0"}
            ]
          }
        }
        """
    }

    /// Eight top-level members, in the real file's own order. Seven of them are none of R30's
    /// business, and the whole preservation claim is that all seven come back untouched.
    static func settings() -> String {
        """
        {
          "env": {
            "CLAUDE_CODE_MAX_RETRIES": "4",
            "DISABLE_AUTOUPDATER": "1"
          },
          "includeCoAuthoredBy": false,
          "permissions": {
            "allow": ["Bash(git status)"],
            "deny": [],
            "ask": [],
            "defaultMode": "acceptEdits"
          },
          "model": "fixture-model",
          "hooks": {
            "SessionStart": [{"hooks": [{"type": "command", "command": "echo start"}]}],
            "Stop": [{"hooks": [{"type": "command", "command": "echo stop"}]}]
          },
          "statusLine": {
            "type": "command",
            "command": "echo line",
            "padding": 0
          },
          "enabledPlugins": {
            "code-review@fledgeling-plugins": true,
            "code-review@claude-code-plugins": false,
            "swift-lsp@fledgeling-plugins": true
          },
          "extraKnownMarketplaces": {
            "fledgeling-plugins": {"source": {"source": "github", "repo": "example/one"}}
          }
        }
        """
    }

    /// The seven members `settings.json` carries that this item must never touch.
    static let untouchableSettingsKeys = [
        "env", "includeCoAuthoredBy", "permissions", "model", "hooks", "statusLine"
    ]

    // MARK: - Builders

    static func skill(_ name: String, at root: String, description: String, extra: String? = nil) {
        let directory = "\(root)/skills/\(name)"
        write(
            "---\nname: \(name)\ndescription: \(description)\n---\n\n# \(name)\n",
            to: "\(directory)/SKILL.md"
        )
        guard let extra else { return }
        write("a second file, so the tree is not one file deep\n", to: "\(directory)/\(extra)")
    }

    static func marketplace(_ name: String, at root: String) {
        write(
            "{\"name\":\"\(name)\",\"owner\":{\"name\":\"someone\"},\"plugins\":[]}",
            to: "\(root)/plugins/marketplaces/\(name)/.claude-plugin/marketplace.json"
        )
    }

    static func plugin(_ name: String, marketplace: String, version: String, at root: String) {
        let directory = "\(root)/plugins/cache/\(marketplace)/\(name)/\(version)"
        write(
            "{\"name\":\"\(name)\",\"version\":\"\(version)\",\"description\":\"from \(marketplace)\"}",
            to: "\(directory)/.claude-plugin/plugin.json"
        )
        write("# \(name)\n\nfrom \(marketplace)\n", to: "\(directory)/README.md")
        write("marker\n", to: "\(directory)/.in_use")
    }

    static func write(_ text: String, to path: String) {
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true
        )
        try? Data(text.utf8).write(to: URL(fileURLWithPath: path))
    }

    /// Read one top-level member back as its compact JSON, for the preservation assertions.
    static func settingsMember(_ key: String, at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8),
              let parsed = try? JSONParser.parse(text),
              let value = parsed.member(key)
        else { return nil }
        return JSStringify.compact(value)
    }

    static func settingsKeys(at path: String) -> [String] {
        guard let data = FileManager.default.contents(atPath: path),
              let text = String(data: data, encoding: .utf8),
              let parsed = try? JSONParser.parse(text),
              let members = parsed.asObjectMembers
        else { return [] }
        return members.map(\.key.string)
    }
}

/// A fixture tree, a router store beside it, and a clock far enough ahead that everything just
/// written is settled.
///
/// Its own type rather than a member of either suite: R30's tests are split across two files to
/// stay inside the type-body limit, and a bench duplicated across them is two benches that drift.
struct IngestBench {
    let root: String
    let claude: ClaudeTree
    let store: DiskExtensionStore
    let clock: SteppingMillisecondClock

    init(_ tag: String) {
        root = NSTemporaryDirectory() + "mcprouter-r30-\(tag)-" + UUID().uuidString
        ClaudeFixtureTree.build(at: "\(root)/claude")
        claude = ClaudeTree(root: "\(root)/claude")
        // An hour ahead of real time, so the settle window is satisfied by construction in every
        // test whose subject is not the window. `G3` is the one that sets its own clock.
        clock = SteppingMillisecondClock(
            start: Date().timeIntervalSince1970 * 1000 + 3_600_000, step: 1
        )
        store = DiskExtensionStore(root: "\(root)/router/extensions", clock: clock)
    }

    func scan(settleMilliseconds: Double = 60000) -> ClaudeScan {
        ClaudeExtensionScan.scan(
            tree: claude, store: store, settleMilliseconds: settleMilliseconds,
            now: clock.nowMilliseconds
        )
    }

    func ingest() -> ExtensionIngest {
        ExtensionIngest(store: store, tree: claude, clock: clock, fileSystem: RealFileSystem())
    }

    func settingsDestination() -> ClaudeSettingsEdit.Destination {
        ClaudeSettingsEdit.Destination(
            path: claude.settingsPath, backupDirectory: "\(root)/backups",
            processIdentifier: 1, nowMilliseconds: 1000
        )
    }

    func tearDown() {
        try? FileManager.default.removeItem(atPath: root)
    }
}
