import Foundation

/// The half of `buildManifest` that does not spawn anything.
public enum ManifestBookkeeping {
    /// What asking an upstream for its tools produced.
    public enum Observation: Sendable {
        case tools([CachedTool])
        case failure(message: String)
    }

    public enum Outcome: Sendable, Hashable {
        /// First sight, or a surface identical to the approved one.
        case approved(toolCount: Int)
        /// A changed surface, held rather than served.
        case heldForApproval(changeCount: Int)
        case failed(message: String)
    }

    public struct Step: Sendable {
        public let entry: CachedServer
        public let outcome: Outcome
    }

    /// One server's entry, from its previous state and what the upstream just said.
    public static func apply(
        previous: CachedServer?,
        observation: Observation,
        configHash: String,
        nowMilliseconds: Double
    ) -> Step {
        let timestamp = JSString(JSDate.iso8601(milliseconds: nowMilliseconds))

        switch observation {
        case let .failure(message):
            // R18: Preserve the previous digest across failure so that subsequent
            // re-indexing can compare against the previously approved surface rather
            // than auto-approving a changed/tampered surface on first sight.
            var entry = previous ?? CachedServer(members: [])
            entry.set("hash", .string(JSString(configHash)))
            entry.set("builtAt", .string(timestamp))
            entry.set("tools", .array([]))
            entry.set("error", .string(JSString(message)))
            if let prevDigest = previous?.digest {
                entry.set("digest", .string(prevDigest))
            }
            return Step(entry: entry, outcome: .failed(message: message))

        case let .tools(tools):
            let digest = ToolsDigest.digest(of: tools)
            let hasComparableDigest = previous?.hasDigest ?? false
            let matches = previous?.digest == JSString(digest)

            if !hasComparableDigest || matches {
                var entry = CachedServer(members: [])
                entry.set("hash", .string(JSString(configHash)))
                entry.set("builtAt", .string(timestamp))
                entry.set("tools", .array(tools.map(\.value)))
                entry.set("digest", .string(JSString(digest)))
                return Step(entry: entry, outcome: .approved(toolCount: tools.count))
            }

            var entry = previous ?? CachedServer(members: [])
            entry.set("hash", .string(JSString(configHash)))
            entry.remove("error")
            entry.set("pending", .object([
                JSONMember(key: JSString("tools"), value: .array(tools.map(\.value))),
                JSONMember(key: JSString("digest"), value: .string(JSString(digest))),
                JSONMember(key: JSString("seenAt"), value: .string(timestamp))
            ]))
            let changes = DiffTools.diff(before: previous?.tools ?? [], after: tools)
            return Step(entry: entry, outcome: .heldForApproval(changeCount: changes.count))
        }
    }

    /// Walks the upstreams, updating the manifest in place.
    public static func build(
        manifest: inout Manifest,
        upstreams: [UpstreamConfig],
        force: Bool = false,
        nowMilliseconds: () -> Double,
        observe: (UpstreamConfig) -> Observation
    ) -> (built: [String], failed: [String]) {
        var built: [String] = []
        var failed: [String] = []

        for upstream in upstreams {
            guard force || ToolUnion.isStale(manifest, upstream) else { continue }
            let step = apply(
                previous: manifest.entry(named: upstream.name),
                observation: observe(upstream),
                configHash: UpstreamHash.hash(upstream),
                nowMilliseconds: nowMilliseconds()
            )
            manifest.setEntry(upstream.name, step.entry)
            switch step.outcome {
            case let .approved(count):
                built.append("\(upstream.name) (\(count) tools)")
            case let .heldForApproval(count):
                built.append("\(upstream.name) (\(count) change(s) held for approval)")
            case let .failed(message):
                failed.append("\(upstream.name): \(message)")
            }
        }
        return (built, failed)
    }
}
