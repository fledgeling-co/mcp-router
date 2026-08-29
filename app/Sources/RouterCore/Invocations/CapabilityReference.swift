import Foundation

/// What one `tool_use` name in a transcript refers to.
///
/// Three shapes, measured against a 200-file sample of this machine's corpus on 2026-08-29:
///
/// | shape | count in sample | refers to |
/// |---|---|---|
/// | `Bash`, `Read`, `Edit`, `Write`, … | 3,241 | a harness built-in — no capability at all |
/// | `Skill` with input `{skill: "…"}` | 15 | a skill, sometimes qualified by the plugin supplying it |
/// | `mcp__<server>__<tool>` | 64 | one tool on one upstream server |
public enum CapabilityReference: Sendable, Hashable {
    case skill(name: String, providedByPlugin: String?)
    case server(name: String, tool: String)
    /// A harness built-in. Named rather than returned as nil, so the reader counts it as the class
    /// it is instead of as an unnamed tool.
    case builtIn

    /// The name Claude Code gives the skill tool.
    public static let skillToolName = "Skill"
    /// The prefix Claude Code gives every MCP tool.
    public static let mcpToolPrefix = "mcp__"
    /// The separator between the segments of an MCP tool name.
    public static let mcpSeparator = "__"

    /// Read a reference from a tool name and, for a `Skill` call, its `skill` input.
    ///
    /// `skillInput` is the **only** member of a tool's input this reader ever looks at. `args` sits
    /// beside it on 13 of the 15 sampled `Skill` blocks and is never read: it is whatever the caller
    /// typed, which is prompt text by another name.
    public static func parse(toolName: String, skillInput: String?) -> CapabilityReference? {
        if toolName == skillToolName {
            guard let skillInput, !skillInput.isEmpty else { return nil }
            return .skill(name: skillInput, providedByPlugin: pluginPrefix(of: skillInput))
        }
        guard toolName.hasPrefix(mcpToolPrefix) else {
            return toolName.isEmpty ? nil : .builtIn
        }
        let rest = String(toolName.dropFirst(mcpToolPrefix.count))
        let parts = rest.components(separatedBy: mcpSeparator)
        // `mcp__router__diolog-tasks__get_issue` is a real name from the sample: the router relays,
        // so the tool half can itself contain the separator. The server is the first segment and
        // the tool is everything after it, rejoined — splitting into exactly two would drop the
        // relayed server's own name from the tool.
        guard parts.count >= 2, !parts[0].isEmpty else { return nil }
        let tool = parts.dropFirst().joined(separator: mcpSeparator)
        guard !tool.isEmpty else { return nil }
        return .server(name: parts[0], tool: tool)
    }

    /// `ship-feature:ship-feature` → `ship-feature`; `tailings` → nil.
    ///
    /// The prefix is the plugin's **short** name, which is not its identity: R30 measured 13 plugin
    /// names installed from two marketplaces at once on this machine, and Claude's own identity for
    /// a plugin is `<plugin>@<marketplace>`. So this is a lead for the version lookup to follow, and
    /// the lookup refuses when it resolves to more than one — it is not an answer by itself.
    static func pluginPrefix(of skill: String) -> String? {
        guard let colon = skill.firstIndex(of: ":") else { return nil }
        let prefix = String(skill[skill.startIndex ..< colon])
        return prefix.isEmpty ? nil : prefix
    }

    /// The event this reference becomes, at a moment, in a harness.
    public func event(at timestamp: String, harness: String) -> InvocationEvent? {
        switch self {
        case let .skill(name, _):
            InvocationEvent(ts: timestamp, kind: .skill, name: name, harness: harness)
        case let .server(name, tool):
            InvocationEvent(ts: timestamp, kind: .server, name: name, harness: harness, tool: tool)
        case .builtIn:
            nil
        }
    }
}
