import Foundation

/// Driving one real request at an upstream and reporting what happened.
///
/// A protocol so the monitor's state machine can be exercised without spawning anything, and a
/// protocol whose **production conformer is named in the requirement inventory**: a health check is
/// a claim about the world outside this process, so the symbol that reaches outside it has to
/// exist and has to be the one the route calls. ``PoolUpstreamProbe`` is that symbol, and its path
/// through ``UpstreamPool/lease(_:)`` to `StdioUpstreamTransport`'s `Process()` is what the
/// effect witness records.
public protocol UpstreamProbing: Sendable {
    /// Whether this upstream is live right now — the test a scheduled sweep uses to decide whether
    /// probing it would cost a cold start.
    func isLive(_ name: String) async -> Bool

    /// Ask the upstream for its tools, bounded by `timeoutMilliseconds`.
    func probe(_ name: String, timeoutMilliseconds: Int) async -> ProbeOutcome
}

/// The real thing: a lease on the pool and a `tools/list` down it.
///
/// `tools/list` rather than a dedicated ping, because the MCP protocol this router speaks has no
/// ping that every server answers, and a health check that uses a method half the fleet does not
/// implement reports a protocol gap as an outage. `tools/list` is the one request every upstream
/// here must answer — the router's own cache is built from it — so a server that cannot answer it
/// is a server this router cannot use, which is exactly the question being asked.
public struct PoolUpstreamProbe: UpstreamProbing {
    private let pool: UpstreamPool
    private let clock: any RouterClock

    public init(pool: UpstreamPool, clock: any RouterClock = SystemClock()) {
        self.pool = pool
        self.clock = clock
    }

    public func isLive(_ name: String) async -> Bool {
        await pool.isLive(name)
    }

    public func probe(_ name: String, timeoutMilliseconds: Int) async -> ProbeOutcome {
        let started = clock.nowMilliseconds
        let lease: UpstreamLease
        do {
            lease = try await pool.lease(name)
        } catch {
            // A failure to acquire is reported as the pool's own words rather than as a timeout,
            // even when the pool gave up on a startup budget. "the child never started" and "the
            // child answered too slowly" are different things to act on and `PoolError` already
            // distinguishes them.
            return .failed(reason: (error as? PoolError)?.description ?? error.localizedDescription)
        }
        let answer = await Self.listBounded(lease.session, timeoutMilliseconds: timeoutMilliseconds)
        await pool.release(lease)

        let elapsed = Int((clock.nowMilliseconds - started).rounded())
        switch answer {
        case let .listed(value):
            // The count is reported, never judged. A server that legitimately advertises no tools
            // is healthy; treating an empty list as a failure would trip it forever.
            return .ok(latencyMs: elapsed, tools: value.member("tools")?.asArray?.count ?? 0)
        case .timedOut:
            return .timedOut(afterMs: timeoutMilliseconds)
        case let .failed(reason):
            return .failed(reason: reason)
        }
    }

    enum Answer: Sendable {
        case listed(JSONValue)
        case timedOut
        case failed(String)
    }

    /// Race the request against the budget, with the loser abandoned rather than awaited.
    ///
    /// Not a task group, for the reason `StdioUpstreamTransport.handshake` is not one: a group does
    /// not return until every child finishes, so racing an uncancellable await against a timer
    /// inside one can only be won by the branch you were trying to escape. A wedged upstream leaves
    /// the request parked forever and the group parked with it — the exact hang the bound exists to
    /// prevent. The winner is published to a box and the loser is dropped; the session's own idle
    /// reap is what eventually unblocks it.
    static func listBounded(
        _ session: any UpstreamSession, timeoutMilliseconds: Int
    ) async -> Answer {
        let outcome = FirstOutcome<Answer>()
        let listing = Task {
            do {
                try await outcome.offer(.listed(session.listTools()))
            } catch {
                outcome.offer(.failed("\(error)"))
            }
        }
        let timing = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, timeoutMilliseconds)) * 1_000_000)
            outcome.offer(.timedOut)
        }
        let result = await outcome.wait()
        timing.cancel()
        if case .listed = result {} else { listing.cancel() }
        return result
    }
}
