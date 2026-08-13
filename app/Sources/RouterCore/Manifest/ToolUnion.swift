import Foundation

/// The separator between a server namespace and the upstream's own tool name.
public let toolNameSeparator = JSString("__")

/// A server's tools, namespaced, filtered and placarded — the list a client is actually served.
public enum ToolUnion {
    /// True when the caller's directory is inside one of a server's allowed projects.
    ///
    /// A **lexical** test, not path normalisation, and the difference is the whole clause: `..`,
    /// doubled separators and symlinks are not resolved, the comparison is case-sensitive, and a
    /// project of `""` gets a trailing slash appended and so matches every absolute directory. A
    /// port that reached for `URL.standardized` here would quietly widen or narrow access.
    public static func visibleTo(_ upstream: UpstreamConfig, cwd: String?) -> Bool {
        guard let projects = upstream.projects, !projects.isEmpty else { return true }
        // A scoped server plus a caller who cannot be identified is not served.
        guard let cwd, !cwd.isEmpty else { return false }
        return projects.contains { project in
            cwd == project || cwd.hasPrefix(project.hasSuffix("/") ? project : "\(project)/")
        }
    }

    /// The reason a server's tools are listed but will not run, if there is one.
    ///
    /// A declared placard outranks an entry error, and an `error: ""` produces nothing because the
    /// reference tests it for truthiness.
    public static func placardFor(_ upstream: UpstreamConfig, entry: CachedServer?) -> Placard? {
        if let placard = upstream.placard { return placard }
        if let entry, entry.hasError, let reason = entry.error { return Placard(reason: reason.string) }
        return nil
    }

    /// True when the cache has no usable entry for this server's current config.
    ///
    /// Note what does **not** make an entry stale: a missing digest, an empty tool list, a pending
    /// surface, or an `error` of `""`. Only an absent entry, a hash mismatch, or a non-empty error
    /// does. Treating an empty tool list as stale would look like an improvement and would re-spawn
    /// every failed server on every call.
    public static func isStale(_ manifest: Manifest, _ upstream: UpstreamConfig) -> Bool {
        guard let entry = manifest.entry(named: upstream.name) else { return true }
        let expected = UpstreamHash.hash(upstream)
        guard case let .string(recorded)? = entry.member("hash"), recorded == JSString(expected) else {
            return true
        }
        return entry.hasError
    }

    /// The union of every server's tools, namespaced so names cannot collide.
    ///
    /// Serves the **approved** surface only; a pending change is held until it is accepted.
    ///
    /// The skip order is the part worth reading twice: an entry with no approved tools is dropped
    /// *before* a placard is considered, so the "INOPERATIVE — …" text below is unreachable through
    /// the normal failure path, because that path sets `tools: []`. That is a defect in the
    /// reference and it is ported rather than fixed — the parity gate has to run against the
    /// reference's real behaviour first, and it is reported as a deferred child.
    public static func unionTools(
        manifest: Manifest,
        upstreams: [UpstreamConfig],
        cwd: String? = nil
    ) -> [CachedTool] {
        var out: [CachedTool] = []
        for upstream in upstreams {
            guard visibleTo(upstream, cwd: cwd) else { continue }
            guard let entry = manifest.entry(named: upstream.name) else { continue }
            let tools = entry.tools
            guard !tools.isEmpty else { continue }

            let placard = placardFor(upstream, entry: entry)
            let namespace = JSString(upstream.name)
            for tool in tools {
                // `t.description ?? t.name` — nullish, so an empty description is kept and only an
                // absent or null one falls back to the name.
                let own = template(tool.descriptionValue ?? tool.rawMember("name"))
                let namespaced = namespace + toolNameSeparator + template(tool.rawMember("name"))
                out.append(
                    tool
                        .setting("name", to: .string(namespaced))
                        .setting("description", to: .string(describe(upstream.name, placard, own)))
                )
            }
        }
        return out
    }

    /// The served description, with the reference's exact punctuation.
    private static func describe(_ server: String, _ placard: Placard?, _ own: JSString) -> JSString {
        guard let placard else { return JSString("[\(server)] ") + own }
        var text = JSString("[\(server)] INOPERATIVE — \(placard.reason).")
        // Appended only when non-empty: an empty substitute would otherwise read "Use  instead."
        if let substitute = placard.substitute, !substitute.isEmpty {
            text = text + JSString(" Use \(substitute) instead.")
        }
        return text + JSString(" (When working: ") + own + JSString(")")
    }

    /// How a JavaScript template literal renders a value.
    ///
    /// An absent member interpolates as the literal text `undefined`, which is what the reference
    /// emits for a tool with no name. Objects and arrays would render as `[object Object]` and a
    /// comma join respectively; neither can reach here from an MCP server, and this renders them as
    /// JSON instead — stated rather than hidden.
    private static func template(_ value: JSONValue?) -> JSString {
        guard let value else { return JSString("undefined") }
        if case let .string(text) = value { return text }
        return JSString(value.jsDisplayString)
    }

    /// Split a namespaced tool name back into its server and the upstream's own name.
    ///
    /// The split is at the **first** separator, so `a__b__c` is server `a` and tool `b__c`, and
    /// `a____b` is server `a` and tool `__b`. Splitting at the last one passes every simple fixture
    /// and routes both of those to a server that does not exist.
    public static func splitToolName(_ name: JSString) -> (server: JSString, tool: JSString)? {
        let units = name.units
        let separator = toolNameSeparator.units
        guard units.count > separator.count else { return nil }
        var index: Int?
        for start in 0 ... (units.count - separator.count)
            where Array(units[start ..< start + separator.count]) == separator {
            index = start
            break
        }
        // `i <= 0` covers both "no separator" and a name that starts with one.
        guard let found = index, found > 0 else { return nil }
        let server = JSString(units: Array(units[0 ..< found]))
        let tool = JSString(units: Array(units[(found + separator.count)...]))
        guard !server.isEmpty, !tool.isEmpty else { return nil }
        return (server, tool)
    }

    public static func splitToolName(_ name: String) -> (server: String, tool: String)? {
        guard let split = splitToolName(JSString(name)) else { return nil }
        return (split.server.string, split.tool.string)
    }
}
