import Foundation

/// Where the three caches this item is about actually live.
///
/// Injected rather than read from `$HOME` at the point of use, and that is load-bearing rather
/// than tidy: `~/.npm/_npx` held **2.0 GB across 48 entries** on this machine on 2026-08-28 and
/// `~/.claude/plugins/cache` held **2.6 GB across 12 directories**. A gate run that defaulted to
/// the developer's own home would put those inside a test, which is the failure
/// `div-m22-harnesses` already records for `GET /harnesses`.
public struct CacheRoots: Sendable, Hashable {
    /// npm's cache of `npx`-fetched package trees.
    public let npx: String
    /// Claude's plugin cache — one directory per marketplace, then plugin, then version.
    public let pluginCache: String

    public init(npx: String, pluginCache: String) {
        self.npx = npx
        self.pluginCache = pluginCache
    }

    /// The locations on a real machine, derived from a home directory rather than from `$HOME`
    /// directly so a caller can still point this at a scratch directory.
    public static func under(home: String) -> CacheRoots {
        CacheRoots(
            npx: (home as NSString).appendingPathComponent(".npm/_npx"),
            pluginCache: (home as NSString).appendingPathComponent(".claude/plugins/cache")
        )
    }
}

/// One package `npx` was asked for, and what it currently resolves to.
///
/// `installedVersion` is read from the fetched tree rather than from the spec, because the spec is
/// what does **not** change. `npx -y media-gen-pro-mcp@latest` is a real upstream on this machine:
/// its command, args and env are identical forever while the package under them moves on every
/// publish, and that gap is the whole subject of this item.
public struct NpxRequest: Sendable, Hashable {
    public let name: String
    /// The dependency range as `package.json` records it, e.g. `^0.3.2`.
    public let spec: String
    /// `nil` when the tree does not hold the package the entry was created for.
    public let installedVersion: String?

    public init(name: String, spec: String, installedVersion: String?) {
        self.name = name
        self.spec = spec
        self.installedVersion = installedVersion
    }
}

/// One `~/.npm/_npx/<hash>` directory.
///
/// `requested` is empty for an entry with no readable `package.json`. Two of the 48 entries
/// measured on this machine are in that state — one holding a bare `node_modules` and one holding
/// nothing at all — and they are the reason ``CacheInvalidation`` refuses a removal it cannot name
/// a refetch for rather than sweeping a directory it cannot explain.
public struct NpxEntry: Sendable, Hashable {
    public let directory: String
    public let requested: [NpxRequest]
    /// Bytes on disk, or `nil` when the walk could not be taken. Never `0` for "not measured":
    /// a zero here is a measurement (`DESIGN.md` §6).
    public let bytes: Int?

    public init(directory: String, requested: [NpxRequest], bytes: Int?) {
        self.directory = directory
        self.requested = requested
        self.bytes = bytes
    }
}

/// One cached plugin version: `<marketplace>/<plugin>/<version>`.
public struct PluginVersion: Sendable, Hashable {
    public let marketplace: String
    public let plugin: String
    public let version: String
    public let directory: String
    public let bytes: Int?

    public init(marketplace: String, plugin: String, version: String, directory: String, bytes: Int?) {
        self.marketplace = marketplace
        self.plugin = plugin
        self.version = version
        self.directory = directory
        self.bytes = bytes
    }
}

/// Reading the caches, and removing one entry from one of them.
///
/// A port for the reason every other port in this router is one: the states that matter — an npx
/// entry with no `package.json`, a plugin directory whose marketplace has gone, a removal that
/// fails halfway — are states a developer's machine will not enter on request.
public protocol CacheProbing: Sendable {
    /// Every `~/.npm/_npx/<hash>` directory, in name order.
    func npxEntries() -> [NpxEntry]
    /// Every cached plugin version, in `<marketplace>/<plugin>/<version>` order.
    func pluginVersions() -> [PluginVersion]
    /// A stamp identifying the bytes of one file — its size and modification time — or `nil` when
    /// the path is not a readable regular file.
    func fileStamp(_ path: String) -> String?
    /// Delete one directory. Returns `nil` on success, or the reason it failed.
    ///
    /// Deletion rather than the reversible move ``DiskExtensionStore`` makes, and the difference is
    /// the subject rather than a relaxation: an extension's bytes exist only where the router put
    /// them, while every path this removes is a cache the router can cause to be re-fetched. That
    /// is the invariant ``CacheInvalidation`` enforces before anything reaches here.
    func removeDirectory(_ path: String) -> String?
}
