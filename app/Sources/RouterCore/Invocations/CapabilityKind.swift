import Foundation

/// The three things an invocation can name.
///
/// Deliberately not ``ExtensionKind``. That enum is about what the router can *hold* — skills,
/// plugins, marketplaces — and a marketplace is never invoked: it is a list of things that are. A
/// server is invoked constantly and is not an extension at all. The two enums overlap on two cases
/// and mean different things, and folding them together would put a `marketplaces` row on a chart
/// of runs where its only honest value is a permanent zero.
public enum CapabilityKind: String, Sendable, Hashable, CaseIterable {
    /// A skill the harness loaded into an agent's context. Observed in the harness's own session
    /// transcript, never by the router — see ``TranscriptScan``.
    case skill
    /// A plugin, named the way Claude names one: `<plugin>@<marketplace>` (R30 §1.2).
    case plugin
    /// An upstream MCP server. Observed twice over: by the router when it relays a call, and in a
    /// transcript as `mcp__<server>__<tool>`.
    case server

    public var singular: String { rawValue }
}
