import Foundation

/// The half of `buildManifest` that does not spawn anything.
///
/// The reference's `buildManifest` interleaves two jobs: starting an upstream and asking it for its
/// tools, and deciding what that answer means for the cache. Only the second is in this item — the
/// pool is the next one — so it is written as a pure function over an injected observation. That is
/// what lets the four branches below be tested before a pool exists, and it is where the
/// interesting behaviour lives: three of the four are about *not* destroying something.
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
    ///
    /// | Observation | Result |
    /// |---|---|
    /// | No previous digest | approve — a fresh entry of `hash`, `builtAt`, `tools`, `digest` |
    /// | Digest equal | the same, which is what clears a stale `error` and a stale `pending` |
    /// | Digest changed | keep the approved `tools`, `digest` and `builtAt`; set `pending`; update
    ///   `hash`; drop `error` |
    /// | Failure | `tools: []` plus the error — **the approved tools are destroyed** |
    ///
    /// The last row is a defect, not a design. Its consequence is that the placard `unionTools`
    /// carefully builds can never be reached through this path, because the entry it would placard
    /// now has no tools and is skipped first. It is ported faithfully and reported as a deferred
    /// child: a parity gate cannot run against a port that has quietly improved the thing it is
    /// measuring.
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
            // `!prev?.digest` is a truthiness test, so an entry whose digest is `""` takes the
            // approval branch exactly as one with no digest at all does.
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

            // `{ ...prev, hash, error: undefined, pending }` — the spread keeps every member the
            // previous entry had, including ones this item does not model, and keeps each at the
            // position it already occupied.
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

    /// Walks the upstreams, updating the manifest **in place**.
    ///
    /// `observe` is the seam the pool plugs into. Three of the reference's properties live here
    /// rather than in ``apply(previous:observation:configHash:nowMilliseconds:)``: an upstream that
    /// is no longer declared keeps its entry rather than being pruned, `force` bypasses the
    /// staleness check without changing anything else, and the two report lists follow the order
    /// the upstreams were declared in.
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
