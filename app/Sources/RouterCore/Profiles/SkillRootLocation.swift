import Foundation

/// Where one harness keeps its skills, and **how that was established**.
///
/// The provenance sits in the type rather than in a comment, for the reason ``HTTPCapability``
/// carries its own: this is a fact about somebody else's program, and a claim about another
/// program's layout is worth exactly what produced it. `DESIGN.md` §6 forbids presenting an
/// inference as an observation, and a reader can tell a walk of the real directory from a guess
/// without having to trust prose.
///
/// **Three shapes the obvious model gets wrong**, all measured on this machine on 2026-08-29:
///
///   * `codexCLI` and `chatGPTCLI` share `~/.codex/skills`. One reading, reported once — the same
///     thing `ClientConfigs` already does for their configuration file.
///   * `cursor` has **two** roots with different shapes: `~/.cursor/skills`, 87 entries and every
///     one a symlink into Claude's plugin cache, and `~/.cursor/skills-cursor`, 22 real
///     directories. Merging them would report 109 entries against a denominator describing
///     neither.
///   * `claudeDesktop` and `grokCLI` have **no** skills directory. They are absent from
///     ``all(homeDirectory:)`` rather than present and empty, because a harness with nowhere to put
///     a skill and a harness with an empty place to put one need different answers.
public struct SkillRootLocation: Sendable, Hashable {
    public let client: MCPClient
    /// The absolute path of the directory.
    public let path: String
    /// What distinguishes this root from the same client's other one, or nil when it has one.
    public let variant: String?
    /// How the path was established.
    public let provenance: SkillRootProvenance

    public init(
        client: MCPClient, path: String, variant: String? = nil, provenance: SkillRootProvenance
    ) {
        self.client = client
        self.path = path
        self.variant = variant
        self.provenance = provenance
    }

    /// A stable identifier for one root, since a client can have more than one.
    public var identifier: String {
        variant.map { "\(client.rawValue).\($0)" } ?? client.rawValue
    }

    /// Every known root, in ``MCPClient/allCases`` order, with a client's variants adjacent.
    ///
    /// The two harnesses with no root are **not** in this list. `GET /profiles/:name/projection`
    /// reports them from ``MCPClient/allCases`` as `noSkillRoot`, so they are named rather than
    /// silently missing — an enumeration whose absences are invisible is the failure this
    /// repository files as a coverage hole.
    public static func all(homeDirectory: String) -> [SkillRootLocation] {
        func under(_ relative: String) -> String {
            (homeDirectory as NSString).appendingPathComponent(relative)
        }
        let walked = "walked read-only with python3 os.listdir/os.path.islink on 2026-08-29"
        return [
            SkillRootLocation(
                client: .claudeCode, path: under(".claude/skills"),
                provenance: .walked(reading: "\(walked): 23 entries, 21 symlinks, 1 dangling")
            ),
            SkillRootLocation(
                client: .codexCLI, path: under(".codex/skills"),
                provenance: .walked(reading: "\(walked): 1 entry, 1 symlink, 0 dangling")
            ),
            SkillRootLocation(
                client: .chatGPTCLI, path: under(".codex/skills"),
                provenance: .sharedWith(
                    client: .codexCLI,
                    note: "the same directory, as their MCP configuration file already is"
                )
            ),
            SkillRootLocation(
                client: .cursor, path: under(".cursor/skills"), variant: "linked",
                provenance: .walked(
                    reading: "\(walked): 87 entries, 87 symlinks, 27 dangling, 86 of them into "
                        + "~/.claude/plugins/cache"
                )
            ),
            SkillRootLocation(
                client: .cursor, path: under(".cursor/skills-cursor"), variant: "native",
                provenance: .walked(reading: "\(walked): 22 entries, 0 symlinks, 22 directories")
            ),
            SkillRootLocation(
                client: .geminiCLI, path: under(".gemini/skills"),
                provenance: .walked(reading: "\(walked): 1 entry, 1 symlink, 0 dangling")
            ),
            SkillRootLocation(
                client: .opencode, path: under(".config/opencode/skills"),
                provenance: .walked(reading: "\(walked): 1 entry, 1 symlink, 0 dangling")
            )
        ]
    }

    /// The clients that have no root here, derived from the list above rather than written twice.
    ///
    /// Derived so the two cannot drift: adding a root to ``all(homeDirectory:)`` removes its client
    /// from this set with no second edit, which is the property `planning/parity/surface.tsv`'s
    /// header asks of every census in this repository.
    public static func clientsWithoutRoot(homeDirectory: String) -> [MCPClient] {
        let covered = Set(all(homeDirectory: homeDirectory).map(\.client))
        return MCPClient.allCases.filter { !covered.contains($0) }
    }
}

/// How a root's path was established.
public enum SkillRootProvenance: Sendable, Hashable {
    /// The directory was listed. `reading` is what came back, so the claim can be re-taken.
    case walked(reading: String)
    /// This client reads another client's root. Not a second reading.
    case sharedWith(client: MCPClient, note: String)

    public var summary: String {
        switch self {
        case let .walked(reading): reading
        case let .sharedWith(client, note): "shares \(client.displayName)'s root — \(note)"
        }
    }
}
