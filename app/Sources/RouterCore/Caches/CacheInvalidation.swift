import Foundation

/// What a request asked to invalidate.
public enum CacheTarget: Sendable, Hashable {
    /// One configured server: its manifest row, and the npx tree its command resolves to.
    case server(String)
    /// One npm package, by name — every `~/.npm/_npx` entry fetched for it.
    case npxPackage(String)
    /// `<marketplace>/<plugin>` or `<marketplace>/<plugin>/<version>`.
    case plugin(String)
    /// The whole npx cache. A **fallback with a stated cost**, never the mechanism.
    case everyNpxEntry

    public var description: String {
        switch self {
        case let .server(name): "server \(name)"
        case let .npxPackage(name): "npx package \(name)"
        case let .plugin(path): "plugin \(path)"
        case .everyNpxEntry: "every npx entry"
        }
    }
}

/// One thing the plan would do, and what brings it back.
public struct CacheStep: Sendable, Hashable {
    public enum Effect: Sendable, Hashable {
        /// Delete a tree. Only reachable for a row that named a refetch.
        case removeDirectory(String)
        /// Re-derive a manifest row by starting the child and asking it for its tools.
        case reindexServer(String)
    }

    public let cache: CacheName
    public let subject: String
    public let effect: Effect
    public let bytes: Int?
    /// Never optional here, unlike on ``CacheRow``. A row with no refetch cannot become a step.
    public let refetch: String

    public init(cache: CacheName, subject: String, effect: Effect, bytes: Int?, refetch: String) {
        self.cache = cache
        self.subject = subject
        self.effect = effect
        self.bytes = bytes
        self.refetch = refetch
    }
}

/// A refusal, carrying the status the control API answers with and a slug beside the sentence.
public struct CacheRefusal: Sendable, Hashable {
    public let status: Int
    public let reason: String
    public let message: String
    /// The wholesale action that would work, when there is one, with what it costs.
    public let fallback: String?
    public let fallbackBytes: Int?

    public init(
        status: Int,
        reason: String,
        message: String,
        fallback: String? = nil,
        fallbackBytes: Int? = nil
    ) {
        self.status = status
        self.reason = reason
        self.message = message
        self.fallback = fallback
        self.fallbackBytes = fallbackBytes
    }
}

/// What would happen, before anything happens.
public struct CachePlan: Sendable {
    public let target: CacheTarget
    public let steps: [CacheStep]
    /// Rows that match the target and cannot be acted on, with the reason each carries.
    public let held: [CacheRow]
    public let refusal: CacheRefusal?
    /// Bytes across the steps whose size was measured.
    public let bytes: Int
    /// How many steps could not be measured, so the figure above is read as a floor.
    public let unmeasured: Int

    public init(
        target: CacheTarget, steps: [CacheStep], held: [CacheRow] = [], refusal: CacheRefusal? = nil
    ) {
        self.target = target
        self.steps = steps
        self.held = held
        self.refusal = refusal
        bytes = steps.compactMap(\.bytes).reduce(0, +)
        unmeasured = steps.count { $0.bytes == nil }
    }

    public var isActionable: Bool { refusal == nil && !steps.isEmpty }
}

/// Working out the narrowest set of things to invalidate, and refusing rather than widening it.
///
/// Three properties this type exists to hold, each of which is a line of the brief:
///
/// * **Narrow, not wholesale.** A target names a server, a package or a plugin version, and the
///   plan holds only what that names. Discarding 2.0 GB of npx cache to update one package is a
///   cost the next twenty starts pay, so wholesale is a separate target that has to be asked for.
/// * **An invalidation that cannot be scoped says so and asks.** ``everyNpxEntry`` is refused
///   unless the caller names the byte count it is about to spend, and a target that matches nothing
///   is a 404 rather than a quiet no-op.
/// * **Nothing is deleted that cannot be re-fetched.** A ``CacheRow`` with no refetch never becomes
///   a ``CacheStep``; it is held, and reported in `held` with the reason.
public enum CacheInvalidation {
    public static func plan(
        target: CacheTarget,
        inventory: CacheInventory,
        upstreams: [UpstreamConfig],
        probe: any CacheProbing,
        acknowledgedBytes: Int? = nil
    ) -> CachePlan {
        switch target {
        case let .server(name):
            return serverPlan(name: name, inventory: inventory, upstreams: upstreams, probe: probe)
        case let .npxPackage(name):
            let matched = npxRows(for: name, inventory: inventory, probe: probe)
            guard !matched.isEmpty else {
                return CachePlan(target: target, steps: [], refusal: CacheRefusal(
                    status: 404, reason: "no-such-entry",
                    message: "no entry under the npx cache was fetched for \"\(name)\""
                ))
            }
            return split(target: target, rows: matched)
        case let .plugin(path):
            let matched = inventory.pluginRows.filter { row in
                row.subject == path || row.subject.hasPrefix("\(path)/")
            }
            guard !matched.isEmpty else {
                return CachePlan(target: target, steps: [], refusal: CacheRefusal(
                    status: 404, reason: "no-such-entry",
                    message: "no cached plugin version is named \"\(path)\""
                ))
            }
            return split(target: target, rows: matched)
        case .everyNpxEntry:
            return wholesalePlan(inventory: inventory, acknowledgedBytes: acknowledgedBytes)
        }
    }

    /// A server's own plan: **the npx tree first, then the re-index.**
    ///
    /// The order is the whole point and it is enforced by construction rather than by a comment on
    /// the caller. Re-deriving the manifest while the old package tree is still cached asks the old
    /// code what its tools are, records the answer as fresh, and leaves the router more confident
    /// in a staler row than it was before.
    static func serverPlan(
        name: String, inventory: CacheInventory, upstreams: [UpstreamConfig], probe: any CacheProbing
    ) -> CachePlan {
        guard let upstream = upstreams.first(where: { $0.name == name }) else {
            return CachePlan(target: .server(name), steps: [], refusal: CacheRefusal(
                status: 404, reason: "no-such-server", message: "no server named \"\(name)\""
            ))
        }
        var steps: [CacheStep] = []
        var held: [CacheRow] = []
        if ContentResolution.isNpx(upstream.command ?? ""),
           let spec = ContentResolution.packageSpec(upstream.args)
        {
            let package = ContentResolution.packageName(spec)
            for row in npxRows(for: package, inventory: inventory, probe: probe) {
                if let refetch = row.refetch {
                    steps.append(CacheStep(
                        cache: .npx, subject: row.subject,
                        effect: .removeDirectory(row.path ?? ""), bytes: row.bytes, refetch: refetch
                    ))
                } else {
                    held.append(row)
                }
            }
        }
        steps.append(CacheStep(
            cache: .manifest, subject: name, effect: .reindexServer(name), bytes: nil,
            refetch: "mcp-router index"
        ))
        return CachePlan(target: .server(name), steps: steps, held: held)
    }

    /// The wholesale fallback, and the one place a cost has to be named before it is paid.
    ///
    /// The caller must send the byte figure the router itself measured. Anything else — an absent
    /// acknowledgement, or a stale one taken before another entry landed — is refused with the
    /// current figure, so the reply to "clear it all" is always the size of what that means.
    static func wholesalePlan(inventory: CacheInventory, acknowledgedBytes: Int?) -> CachePlan {
        let rows = inventory.npxRows
        let removable = rows.filter { $0.refetch != nil }
        let total = removable.compactMap(\.bytes).reduce(0, +)
        guard acknowledgedBytes == total else {
            return CachePlan(
                target: .everyNpxEntry, steps: [],
                held: rows.filter { $0.refetch == nil },
                refusal: CacheRefusal(
                    status: 409, reason: "cost-not-acknowledged",
                    message: "clearing the npx cache discards \(removable.count) entries and"
                        + " \(total) bytes that the next runs re-fetch;"
                        + " send acknowledgeBytes: \(total) to ask for it anyway",
                    fallback: "acknowledgeBytes: \(total)", fallbackBytes: total
                )
            )
        }
        return split(target: .everyNpxEntry, rows: rows)
    }

    /// Rows into steps and holds, on the one question of whether a refetch could be named.
    static func split(target: CacheTarget, rows: [CacheRow]) -> CachePlan {
        var steps: [CacheStep] = []
        var held: [CacheRow] = []
        for row in rows {
            guard let refetch = row.refetch, let path = row.path else {
                held.append(row)
                continue
            }
            steps.append(CacheStep(
                cache: row.cache, subject: row.subject, effect: .removeDirectory(path),
                bytes: row.bytes, refetch: refetch
            ))
        }
        return CachePlan(target: target, steps: steps, held: held)
    }

    static func npxRows(
        for package: String, inventory: CacheInventory, probe: any CacheProbing
    ) -> [CacheRow] {
        let wanted = probe.npxEntries()
            .filter { entry in entry.requested.contains { $0.name == package } }
            .map(\.directory)
        guard !wanted.isEmpty else { return [] }
        return inventory.npxRows.filter { row in row.path.map(wanted.contains) ?? false }
    }

    // MARK: - Applying

    /// What one applied plan did.
    public struct Applied: Sendable, Hashable {
        public let removed: [String]
        public let reindexed: [String]
        /// Steps that failed, as `path: reason`. A failure stops nothing: the remaining steps still
        /// run, because a plan half-applied and reported is recoverable and a plan abandoned at the
        /// first error leaves a state nobody described.
        public let failures: [String]
    }

    /// Runs the removals. Re-indexing is the caller's, because it needs a live pool.
    ///
    /// Removals run **before** the returned `reindexed` names are acted on, which is what the
    /// ordering in ``serverPlan(name:inventory:upstreams:probe:)`` buys.
    public static func apply(_ plan: CachePlan, probe: any CacheProbing) -> Applied {
        guard plan.isActionable else { return Applied(removed: [], reindexed: [], failures: []) }
        var removed: [String] = []
        var reindexed: [String] = []
        var failures: [String] = []
        for step in plan.steps {
            switch step.effect {
            case let .removeDirectory(path):
                if let problem = probe.removeDirectory(path) {
                    failures.append("\(path): \(problem)")
                } else {
                    removed.append(path)
                }
            case let .reindexServer(name):
                reindexed.append(name)
            }
        }
        return Applied(removed: removed, reindexed: reindexed, failures: failures)
    }
}
