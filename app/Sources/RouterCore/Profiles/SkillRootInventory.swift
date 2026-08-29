import Foundation

/// What one entry in a harness's skills directory turned out to be.
///
/// `dangling` is the case this type exists for. Measured on this machine on 2026-08-29,
/// `~/.cursor/skills` held 87 entries and **27 of them were symlinks resolving to nothing** — every
/// one of them into `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, which an upgrade
/// replaces. The harness that loses the skill is not the harness the upgrade happened in, and
/// nothing on the machine said so.
///
/// It is deliberately **not** folded into `absent`. A link that points at nothing is a repair with
/// a known target; an entry that is not there at all is an install. Reporting the first as the
/// second would offer the wrong fix.
public enum SkillEntryKind: Sendable, Hashable {
    /// A real directory holding the skill's own bytes.
    case directory
    /// A symlink whose target exists. `target` is the resolved path.
    case linked(target: String)
    /// A symlink whose target does not exist. `target` is what it still claims.
    case dangling(target: String)
    /// Something that is neither — a stray file in a directory of skills.
    case other
}

public struct SkillEntry: Sendable, Hashable {
    public let name: String
    public let kind: SkillEntryKind

    public init(name: String, kind: SkillEntryKind) {
        self.name = name
        self.kind = kind
    }

    public var isDangling: Bool {
        if case .dangling = kind { return true }
        return false
    }
}

/// One harness's skills directory, read.
///
/// Three states, and keeping them apart is most of the value: `exists == false` is a harness with
/// no skills directory at all (Claude Desktop and grok, measured 2026-08-29); `exists == true` with
/// no entries is a harness with an empty one; and `unreadable` is a directory that is there and
/// could not be opened. All three would collapse to "no rows" in a count.
public struct SkillRootInventory: Sendable {
    public let client: MCPClient
    public let path: String
    public let exists: Bool
    public let entries: [SkillEntry]
    public let unreadable: String?

    public init(
        client: MCPClient,
        path: String,
        exists: Bool,
        entries: [SkillEntry],
        unreadable: String? = nil
    ) {
        self.client = client
        self.path = path
        self.exists = exists
        self.entries = entries
        self.unreadable = unreadable
    }

    public var danglingCount: Int { entries.filter(\.isDangling).count }

    /// The names this root holds, whatever state each is in. A dangling link still occupies its
    /// name, so a projection must not offer to add one over the top of it.
    public var names: Set<String> { Set(entries.map(\.name)) }

    public func entry(named name: String) -> SkillEntry? {
        entries.first { $0.name == name }
    }
}

/// Where the skill-root readings come from.
///
/// A seam rather than a direct call, for the reason ``HarnessInventorySource`` is one: the
/// interesting states are ones a real machine will not enter on request. A dangling symlink, an
/// unreadable directory and a harness with no root at all are the three readings this type exists
/// to carry, and a test that can only produce the developer's own `$HOME` can produce none of them
/// deliberately.
public protocol SkillRootReading: Sendable {
    /// Every harness that has a known skill root, in ``MCPClient/allCases`` order so two reads
    /// agree. A harness with no known root is absent from the result rather than present and empty.
    func inventories() -> [SkillRootInventory]

    /// The harnesses this reader knows of and has no root for.
    ///
    /// Reported rather than derived by the caller, because a caller deriving it from
    /// ``MCPClient/allCases`` would name every client a *fixture* reader does not cover as one the
    /// machine has no root for — which is a different claim and a wrong one.
    func clientsWithoutRoot() -> [MCPClient]
}

/// The real one: `FileManager` over the roots ``SkillRootLocation`` names.
///
/// **Read-only, and structurally so.** Nothing in this file or in ``SkillRootLocation`` creates,
/// moves, links or removes anything; `scripts/lint/no-harness-skill-writes.sh` fails the build if a
/// mutating call appears in either. That is `spec-R7.md` §7's boundary extended one kind further:
/// this router reads another program's tree and does not write it.
public struct DiskSkillRoots: SkillRootReading {
    let homeDirectory: String

    public init(homeDirectory: String = RouterHome.resolvedHomeDirectory()) {
        self.homeDirectory = homeDirectory
    }

    public func inventories() -> [SkillRootInventory] {
        SkillRootLocation.all(homeDirectory: homeDirectory).map(Self.read)
    }

    public func clientsWithoutRoot() -> [MCPClient] {
        SkillRootLocation.clientsWithoutRoot(homeDirectory: homeDirectory)
    }

    static func read(_ location: SkillRootLocation) -> SkillRootInventory {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        let present = manager.fileExists(atPath: location.path, isDirectory: &isDirectory)
        guard present, isDirectory.boolValue else {
            return SkillRootInventory(
                client: location.client, path: location.path, exists: false, entries: []
            )
        }
        let names: [String]
        do {
            names = try manager.contentsOfDirectory(atPath: location.path)
        } catch {
            return SkillRootInventory(
                client: location.client, path: location.path, exists: true, entries: [],
                unreadable: "\(location.path) could not be read: \(error.localizedDescription)"
            )
        }
        let entries = names.filter { !$0.hasPrefix(".") }.sorted().map { name in
            SkillEntry(
                name: name,
                kind: classify((location.path as NSString).appendingPathComponent(name))
            )
        }
        return SkillRootInventory(
            client: location.client, path: location.path, exists: true, entries: entries
        )
    }

    /// `destinationOfSymbolicLink` first, and the order matters.
    ///
    /// `fileExists(atPath:)` **follows** symlinks, so a dangling link answers false to it and a live
    /// one is indistinguishable from a real directory. Asking whether the path is a link before
    /// asking whether anything is there is what separates the three cases; the reverse order
    /// reports every dangling link as absent, which is the reading `spec-F8.md` §1.1 says nothing
    /// on this machine was making.
    static func classify(_ path: String) -> SkillEntryKind {
        let manager = FileManager.default
        if let target = try? manager.destinationOfSymbolicLink(atPath: path) {
            let resolved = target.hasPrefix("/")
                ? target
                : ((path as NSString).deletingLastPathComponent as NSString)
                .appendingPathComponent(target)
            let standardised = (resolved as NSString).standardizingPath
            return manager.fileExists(atPath: standardised)
                ? .linked(target: standardised)
                : .dangling(target: standardised)
        }
        var isDirectory: ObjCBool = false
        guard manager.fileExists(atPath: path, isDirectory: &isDirectory) else { return .other }
        return isDirectory.boolValue ? .directory : .other
    }
}
