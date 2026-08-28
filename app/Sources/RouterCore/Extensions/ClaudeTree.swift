import Foundation

/// The Claude-shaped directory an ingestion reads from, addressed by root rather than assumed.
///
/// **Every path this type answers is derived from `root`, and nothing in R30 defaults that root
/// silently.** The scan, the plan, the apply and the undo all take a `ClaudeTree`, and the CLI verb
/// requires `--claude-home` unless the caller passes `--live`. That is the whole mechanism behind
/// the promise this item is held to: a run against a fixture and a run against the real
/// `~/.claude` differ by one argument that has to be typed, not by a flag that has to be
/// remembered.
///
/// The layout is measured rather than assumed, on this machine on 2026-08-28:
///
/// | kind | where Claude keeps it | how many were there |
/// |---|---|---|
/// | skills | `<root>/skills/<name>/SKILL.md` | 24 directories, 22 carrying `SKILL.md` |
/// | plugins | a version directory named by `<root>/plugins/installed_plugins.json` | 127 records |
/// | marketplaces | `<root>/plugins/marketplaces/<name>/.claude-plugin/marketplace.json` | 7, all readable |
///
/// The plugin row is the one that is not a directory walk, and the reason is in
/// ``ClaudeExtensionScan``: the cache holds far more directories than there are installed plugins,
/// and no property of a directory distinguishes the installed one.
public struct ClaudeTree: Sendable, Hashable {
    public let root: String

    public init(root: String) {
        self.root = root
    }

    /// `<home>/.claude`, off the same `$HOME` reading every other path in this router derives from.
    ///
    /// `RouterHome.resolvedHomeDirectory()` rather than `NSHomeDirectory()` — measured under
    /// `HOME=/tmp/fakehome`, the second returns the real account's directory, so a scratch run
    /// would read the developer's own files. That is a safety property here rather than a parity
    /// one, and it is the same reasoning `WatchPaths` records.
    public init(homeDirectory: String = RouterHome.resolvedHomeDirectory()) {
        root = (homeDirectory as NSString).appendingPathComponent(".claude")
    }

    private func path(_ component: String) -> String {
        (root as NSString).appendingPathComponent(component)
    }

    public var skillsDirectory: String { path("skills") }
    public var pluginsDirectory: String { path("plugins") }
    public var pluginCacheDirectory: String { path("plugins/cache") }
    public var marketplacesDirectory: String { path("plugins/marketplaces") }
    /// The register that says which version of a plugin is installed — see ``ClaudeExtensionScan``.
    public var installedPluginsPath: String { path("plugins/installed_plugins.json") }
    /// The file this item is most careful with: it carries `hooks`, `permissions`, `model` and
    /// `env` for every project on the machine, and only two of its members are R30's to touch.
    public var settingsPath: String { path("settings.json") }

    /// Where one entry of a kind lives, given the name the router stores it under.
    ///
    /// For a plugin the name is `<plugin>@<marketplace>` and the directory is a *version* under the
    /// cache, so the path cannot be reconstructed from the name alone — the scan carries the source
    /// path with the candidate and the manifest records it. This answers only for the two kinds
    /// whose location is a function of their name.
    public func directory(for kind: ExtensionKind, name: String) -> String? {
        switch kind {
        case .skills: (skillsDirectory as NSString).appendingPathComponent(name)
        case .marketplaces: (marketplacesDirectory as NSString).appendingPathComponent(name)
        case .plugins: nil
        }
    }

    /// Which member of `settings.json` records that Claude knows about this kind.
    ///
    /// Measured: `enabledPlugins` is keyed by `<plugin>@<marketplace>` — the same string this item
    /// uses as a plugin's router name, which is why that name was chosen — and
    /// `extraKnownMarketplaces` is keyed by the marketplace's directory name. Skills have no
    /// registration at all: a directory under `skills/` is the whole of a skill's installation, so
    /// removing the directory is the whole of its removal.
    public static func settingsContainer(for kind: ExtensionKind) -> String? {
        switch kind {
        case .plugins: "enabledPlugins"
        case .marketplaces: "extraKnownMarketplaces"
        case .skills: nil
        }
    }
}
