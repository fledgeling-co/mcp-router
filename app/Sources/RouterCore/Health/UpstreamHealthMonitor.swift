import Foundation

/// Every declared upstream's health, and the two ways it gets measured.
///
/// ## Two probe paths, and only one of them may spawn
///
/// A **manual** probe — `POST /servers/:name/probe` — is a person asking, so it is allowed to cold
/// start an upstream. A **scheduled** sweep is not: it probes only what is already live, and
/// declines everything else. Without that term a background health check on twenty-one stdio
/// servers holds twenty-one children open forever, which is `REQ-001` — *at rest there are zero
/// child processes* — inverted by the feature meant to watch it.
///
/// A disabled server is declined on **both** paths. `UpstreamConfig.disabled` means the server is
/// never spawned to be warmed or indexed and is reaped if it happens to be up; a probe route that
/// spawned one anyway would be a hole in the switch rather than a health check.
///
/// ## It does not log
///
/// Deliberate, and cheap to get wrong. `parity-log.sh` diffs this router's log line sequence
/// against the reference's, and the reference has no health probing at all, so every line emitted
/// here would be a line that lane has to be taught to ignore. The record is the report; the route
/// is where it is read.
public actor UpstreamHealthMonitor {
    private let orderedNames: [String]
    private let disabledNames: Set<String>
    private let probing: any UpstreamProbing
    private let clock: any RouterClock
    private var records: [String: UpstreamHealthRecord]
    private var inFlight: Set<String> = []
    private var loop: Task<Void, Never>?

    public init(
        upstreams: [UpstreamConfig],
        global: HealthPolicy,
        globalRefusals: [HealthPolicyRefusal] = [],
        probing: any UpstreamProbing,
        clock: any RouterClock = SystemClock()
    ) {
        orderedNames = upstreams.map(\.name)
        disabledNames = Set(upstreams.filter { $0.disabled == true }.map(\.name))
        self.probing = probing
        self.clock = clock
        var seeded: [String: UpstreamHealthRecord] = [:]
        for upstream in upstreams {
            let resolved = HealthPolicy.resolve(global: global, override: upstream.health)
            // Global refusals first: they are true of every server, and a reader scanning one
            // row should not have to visit another to learn that the file's top-level block was
            // not taken either.
            seeded[upstream.name] = UpstreamHealthRecord(
                server: upstream.name,
                policy: resolved.policy,
                refusals: globalRefusals + resolved.refusals
            )
        }
        records = seeded
    }

    // MARK: - Reading

    /// Every declared upstream, in configuration order.
    ///
    /// A never-probed server is present and `unprobed` rather than omitted: a caller cannot tell an
    /// absent row from a server the router does not know about, and the second is a different
    /// problem with a different fix.
    public func snapshot() -> [UpstreamHealthRecord] {
        orderedNames.compactMap { records[$0] }
    }

    public func record(for name: String) -> UpstreamHealthRecord? {
        records[name]
    }

    // MARK: - Probing

    /// Probe one upstream now, cold-starting it if it is not live. `nil` for a server this router
    /// does not declare.
    public func probeNow(_ name: String) async -> UpstreamHealthRecord? {
        guard records[name] != nil else { return nil }
        if let reason = declineReason(name) {
            return apply(.declined(reason: reason), to: name)
        }
        return await run(name)
    }

    /// One pass over every upstream whose interval has come round.
    ///
    /// Returns the records it touched — attempted or declined — rather than the whole set, so a
    /// caller can tell "the sweep ran and did nothing because nothing was due" from "the sweep did
    /// not run". A pass that returns an empty array is the first of those and is not a failure.
    @discardableResult
    public func sweepOnce() async -> [UpstreamHealthRecord] {
        let now = clock.nowMilliseconds
        let due = orderedNames.filter { records[$0]?.isDue(atMs: now) ?? false }
        var touched: [UpstreamHealthRecord] = []
        for name in due {
            var reason = declineReason(name)
            if reason == nil, await !probing.isLive(name) {
                // The term that keeps `REQ-001` true. A scheduled sweep observes; it does not
                // create the thing it is observing.
                reason = "the upstream is not live, and a scheduled probe does not cold start one"
            }
            if let reason {
                if let updated = apply(.declined(reason: reason), to: name) { touched.append(updated) }
                continue
            }
            if let updated = await run(name) { touched.append(updated) }
        }
        return touched
    }

    /// Why this upstream will not be probed on either path, or `nil` to go ahead.
    ///
    /// The scheduled path adds one more reason on top of these — that the upstream is not live —
    /// and it lives in ``sweepOnce()`` because it suspends and these do not.
    private func declineReason(_ name: String) -> String? {
        if disabledNames.contains(name) { return "the server is disabled" }
        if inFlight.contains(name) { return "a probe is already in flight" }
        return nil
    }

    private func run(_ name: String) async -> UpstreamHealthRecord? {
        guard let record = records[name] else { return nil }
        inFlight.insert(name)
        let outcome = await probing.probe(name, timeoutMilliseconds: record.policy.probeTimeoutMs)
        inFlight.remove(name)
        return apply(outcome, to: name)
    }

    @discardableResult
    private func apply(_ outcome: ProbeOutcome, to name: String) -> UpstreamHealthRecord? {
        guard var record = records[name] else { return nil }
        record.apply(outcome, atMs: clock.nowMilliseconds)
        records[name] = record
        return record
    }

    // MARK: - The background loop

    /// The interval the loop ticks at: the smallest positive one any server configured.
    ///
    /// One timer for the fleet rather than one per server. Each server's own interval is still what
    /// decides whether it is due — ``UpstreamHealthRecord/isDue(atMs:)`` — so a server on ten
    /// minutes is visited on its own schedule by a loop that wakes every minute for its neighbour.
    var tickMilliseconds: Int? {
        let positive = orderedNames.compactMap { records[$0]?.policy.probeIntervalMs }
            .filter { $0 > 0 }
        return positive.min()
    }

    /// Arm the loop, or do nothing at all when no server configured an interval.
    ///
    /// Doing nothing is the default configuration, and it arms **no task**: a loop that wakes every
    /// minute to discover that nothing is due is a timer nobody asked for, and it would be
    /// indistinguishable in a process listing from probing that is switched on.
    public func start() {
        guard loop == nil, let tick = tickMilliseconds else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(tick) * 1_000_000)
                guard !Task.isCancelled else { return }
                await self?.sweepOnce()
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Whether a background loop is armed right now — for asserting that there is **none**, which
    /// is a claim no amount of waiting can establish.
    public var isProbingInBackground: Bool { loop != nil }
}
