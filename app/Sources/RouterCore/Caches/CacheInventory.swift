import Foundation

/// Which of the three caches a row belongs to.
public enum CacheName: String, Sendable, Hashable, CaseIterable {
    /// The router's own `tools/list` cache — the one it can re-derive without the network.
    case manifest
    /// `~/.npm/_npx`, npm's cache of `npx`-fetched package trees.
    case npx
    /// `~/.claude/plugins/cache`, one directory per marketplace, plugin and version.
    case plugins
}

/// One thing that sits between a change and a call.
///
/// `refetch` is the member the rest of this file is built around: it is the command that brings the
/// row back, and a row with **no** refetch is a row this router refuses to remove. That is the
/// brief's *nothing is deleted that the router cannot cause to be re-fetched*, expressed as a field
/// rather than as a habit — a candidate whose refetch is `nil` cannot reach ``CacheInvalidation``'s
/// apply path at all, because the type it would have to become does not accept one.
public struct CacheRow: Sendable, Hashable {
    public let cache: CacheName
    /// How a request names this row: a server name, a package name, or `<marketplace>/<plugin>/<version>`.
    public let subject: String
    /// Where it is on disk. `nil` for a manifest row, which is a member of a file rather than a tree.
    public let path: String?
    /// Bytes on disk, or `nil` when the walk could not be taken. Never `0` for "not measured".
    public let bytes: Int?
    /// What brings it back, or `nil` when the router cannot say.
    public let refetch: String?
    /// Why it cannot be named, when `refetch` is `nil`.
    public let problem: String?

    /// `problem` has no default, so every construction states whether there is one. A row whose
    /// `refetch` is `nil` and whose `problem` is too would be a refusal with no sentence on it.
    public init(
        cache: CacheName, subject: String, path: String?, bytes: Int?, refetch: String?, problem: String?
    ) {
        self.cache = cache
        self.subject = subject
        self.path = path
        self.bytes = bytes
        self.refetch = refetch
        self.problem = problem
    }
}

/// Everything the three caches hold right now, read on every call.
///
/// There is no index and nothing is remembered between calls, for the reason `GET /extensions` is
/// built the same way: a cache is exactly the kind of thing that changes behind the router's back,
/// so a remembered count would be the first thing to be wrong.
public struct CacheInventory: Sendable {
    public let manifestRows: [CacheRow]
    public let npxRows: [CacheRow]
    public let pluginRows: [CacheRow]

    public init(manifestRows: [CacheRow], npxRows: [CacheRow], pluginRows: [CacheRow]) {
        self.manifestRows = manifestRows
        self.npxRows = npxRows
        self.pluginRows = pluginRows
    }

    public func rows(_ cache: CacheName) -> [CacheRow] {
        switch cache {
        case .manifest: manifestRows
        case .npx: npxRows
        case .plugins: pluginRows
        }
    }

    public static func read(
        manifest: Manifest, upstreams: [UpstreamConfig], probe: any CacheProbing
    ) -> CacheInventory {
        CacheInventory(
            manifestRows: manifestRows(manifest: manifest, upstreams: upstreams),
            npxRows: npxRows(probe.npxEntries()),
            pluginRows: pluginRows(probe.pluginVersions())
        )
    }

    // MARK: - The three readings

    /// One row per cached manifest entry.
    ///
    /// Always refetchable, and this is the one cache where that is a property of the router rather
    /// than of the network: re-deriving a tool list means starting the child and asking it, which
    /// is the thing the router already does on `index`.
    static func manifestRows(manifest: Manifest, upstreams: [UpstreamConfig]) -> [CacheRow] {
        let configured = Set(upstreams.map(\.name))
        return manifest.serverEntries.map { name, entry in
            let tools = entry.tools.count
            return CacheRow(
                cache: .manifest,
                subject: name.string,
                path: nil,
                bytes: nil,
                // A row for a server no longer configured cannot be re-derived: there is nothing
                // left to start. It is reported rather than dropped, because a row this router
                // cannot rebuild is precisely what a reader needs to see.
                refetch: configured.contains(name.string) ? "mcp-router index" : nil,
                problem: configured.contains(name.string)
                    ? nil
                    : "\"\(name.string)\" holds \(tools) cached tools and is no longer a configured server"
            )
        }
    }

    /// One row per `~/.npm/_npx/<hash>` directory.
    ///
    /// An entry with no readable `package.json` gets **no** refetch, and that is measured rather
    /// than defensive: two of the 48 entries on this machine on 2026-08-28 are in that state, one
    /// holding a bare `node_modules` and one holding nothing at all. Neither names a package, so
    /// neither can be re-fetched by naming one, and both stay.
    static func npxRows(_ entries: [NpxEntry]) -> [CacheRow] {
        entries.map { entry in
            let name = (entry.directory as NSString).lastPathComponent
            guard let first = entry.requested.first else {
                return CacheRow(
                    cache: .npx, subject: name, path: entry.directory, bytes: entry.bytes,
                    refetch: nil,
                    problem: "this entry names no package, so nothing can be said to re-fetch it"
                )
            }
            let packages = entry.requested.map { "\($0.name)@\($0.spec)" }.sorted()
            return CacheRow(
                cache: .npx,
                subject: first.name,
                path: entry.directory,
                bytes: entry.bytes,
                refetch: "npx -y \(packages.joined(separator: " "))", problem: nil
            )
        }
    }

    /// One row per cached plugin version.
    ///
    /// A directory that is not `<marketplace>/<plugin>/<version>` carries no refetch. Five of the
    /// twelve directories under this cache on 2026-08-28 are `temp_git_<millis>_<suffix>` clone
    /// leftovers with no plugin layout under them at all, and naming a marketplace that would
    /// restore one would be an invention.
    static func pluginRows(_ versions: [PluginVersion]) -> [CacheRow] {
        versions.map { version in
            let subject = "\(version.marketplace)/\(version.plugin)/\(version.version)"
            guard !version.plugin.isEmpty, !version.version.isEmpty else {
                return CacheRow(
                    cache: .plugins, subject: version.marketplace, path: version.directory,
                    bytes: version.bytes, refetch: nil,
                    problem: "\(version.marketplace) is not a <marketplace>/<plugin>/<version> tree"
                )
            }
            return CacheRow(
                cache: .plugins, subject: subject, path: version.directory, bytes: version.bytes,
                refetch: "claude plugin install \(version.plugin)@\(version.version)"
                    + " --marketplace \(version.marketplace)",
                problem: nil
            )
        }
    }
}
