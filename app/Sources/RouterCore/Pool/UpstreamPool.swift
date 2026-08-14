import Foundation

/// A lease on a live upstream.
///
/// Acquisition and in-flight accounting are **one** actor-isolated operation, not two. Returning a
/// handle and letting the caller increment separately leaves a scheduling window between the two
/// actor hops in which the reaper can win and close the upstream the caller is about to use — a
/// window JavaScript does not have, because nothing interleaves between two synchronous statements.
///
/// The token carries the handle it was issued against, so a late release cannot decrement a
/// replacement's count.
public struct UpstreamLease: Sendable {
    public let server: String
    let id: LeaseID
    let handle: HandleID
    let session: any UpstreamSession
    /// True when this lease is what started the upstream — read before the call, because afterwards
    /// the upstream is live either way.
    public let cold: Bool
}

/// Owns the lifecycle of every upstream.
///
/// For stdio that is the whole point of the router: nothing is spawned until a tool on that server
/// is actually called, and each child is closed once it has been idle past its window, so a session
/// that never touches a server never pays for it.
///
/// For HTTP there is no process to save — that transport already multiplexes. What pooling buys
/// there is the connection: one initialize handshake and one token exchange serve every session
/// instead of one per window.
public actor UpstreamPool {
    // Not `private`: the reaping, warm-set, reporting and shutdown half of this actor lives in
    // `UpstreamPoolReaping.swift`, and Swift's `private` is file-scoped. Everything here is still
    // actor-isolated, which is the protection that actually matters.
    var upstreams: [String: UpstreamConfig]
    let orderedNames: [String]
    let defaultIdleMs: Int
    let defaultStartupTimeoutMs: Int
    let transporting: any UpstreamTransporting
    let clock: any RouterClock
    let log: RouterLog?

    var entries: [String: PoolEntry] = [:]
    var pendingAuth: [String: PendingAuth] = [:]
    var shuttingDown = false
    /// The one in-flight shutdown, awaited by every later caller so shutdown is a real barrier.
    var shutdownFlight: Task<Void, Never>?

    var startIDs = IdentitySequence()
    var handleIDs = IdentitySequence()
    var epochIDs = IdentitySequence()
    var leaseIDs = IdentitySequence()

    public init(
        upstreams: [UpstreamConfig],
        defaultIdleMilliseconds: Int,
        defaultStartupTimeoutMilliseconds: Int,
        transporting: any UpstreamTransporting,
        clock: any RouterClock = SystemClock(),
        log: RouterLog? = nil
    ) {
        // Configuration order is preserved deliberately: `status()` reports in this order, and the
        // reference iterates its own map in insertion order. A dictionary's order would make the
        // status payload differ run to run, which R4 would read as a difference.
        orderedNames = upstreams.map(\.name)
        self.upstreams = Dictionary(uniqueKeysWithValues: upstreams.map { ($0.name, $0) })
        defaultIdleMs = defaultIdleMilliseconds
        defaultStartupTimeoutMs = defaultStartupTimeoutMilliseconds
        self.transporting = transporting
        self.clock = clock
        self.log = log
    }

    // MARK: - Leasing

    /// Acquire an upstream and mark a call outstanding on it, atomically.
    public func lease(_ name: String) async throws -> UpstreamLease {
        guard !shuttingDown else { throw PoolError.shuttingDown }
        guard let config = upstreams[name] else { throw PoolError.unknownUpstream(name) }
        if config.transport == .sse { throw PoolError.legacySSEUnsupported(name) }

        let wasLive = entries[name]?.handle != nil

        // Register as a waiter *before* suspending. Installing a handle arms the idle timer with
        // nothing in flight, so on a short idle window the reaper could legitimately pass all four
        // of its checks and close the upstream in the gap between the start completing and this
        // caller's lease being recorded — the cold call would then fail on a child that had just
        // been spawned for it.
        var reserving = entries[name] ?? PoolEntry()
        reserving.pendingWaiters += 1
        entries[name] = reserving

        let handle: PoolHandle
        do {
            handle = try await acquire(name: name, config: config)
        } catch {
            releaseWaiter(name)
            throw error
        }

        // Everything from here to the return is synchronous, so no reap, close or shutdown can
        // interleave: this is the critical section the "atomic lease" claim is actually about.
        guard !shuttingDown else {
            releaseWaiter(name)
            throw PoolError.shuttingDown
        }
        var entry = entries[name] ?? PoolEntry()
        guard entry.handle?.id == handle.id else {
            // The handle we acquired was replaced while we were suspended. Refuse rather than lease
            // a handle the pool no longer owns.
            releaseWaiter(name)
            throw PoolError.superseded(name)
        }
        entry.pendingWaiters = max(0, entry.pendingWaiters - 1)
        let lease = LeaseID(leaseIDs.take())
        entry.activeLeases.insert(lease)
        entry.inFlight += 1
        cancelReap(&entry)
        entries[name] = entry

        return UpstreamLease(
            server: name,
            id: lease,
            handle: handle.id,
            session: handle.session,
            cold: !wasLive
        )
    }

    /// Release a lease. Exactly once: a repeated or copied release is ignored.
    public func release(_ lease: UpstreamLease) {
        guard var entry = entries[lease.server] else { return }
        guard entry.activeLeases.remove(lease.id) != nil else { return }
        entry.inFlight = max(0, entry.inFlight - 1)

        // Re-arm from completion, so the idle window measures time since the last call *ended*
        // rather than since it started. Without this a call that runs longer than the idle window
        // has its own child closed underneath it — not hypothetical, since a research run is
        // documented at 4 to 60 minutes and a sandboxed agent call takes a 900-second timeout.
        if entry.inFlight == 0, entry.handle?.id == lease.handle {
            armReap(name: lease.server, entry: &entry)
        }
        entries[lease.server] = entry
    }

    /// Drop a waiter reservation on a path that will not become a lease.
    func releaseWaiter(_ name: String) {
        guard var entry = entries[name] else { return }
        entry.pendingWaiters = max(0, entry.pendingWaiters - 1)
        entries[name] = entry
        if entry.inFlight == 0, entry.pendingWaiters == 0, entry.handle != nil {
            armReapIfIdle(name: name)
        }
    }

    /// Whether this upstream is live right now — used to label a call as a cold start.
    public func isLive(_ name: String) -> Bool {
        entries[name]?.handle != nil
    }

    /// The ids currently installed, so a test can hand back a *stale* one and prove the identity
    /// guards reject it. Exercising those guards through timing alone is racy by construction —
    /// the whole point of a guard is that the window it closes is hard to hit on purpose.
    func currentIdentities(_ name: String) -> (handle: HandleID?, epoch: ReapEpoch?) {
        (entries[name]?.handle?.id, entries[name]?.reap?.epoch)
    }

    // MARK: - Acquisition

    private func acquire(name: String, config: UpstreamConfig) async throws -> PoolHandle {
        var entry = entries[name] ?? PoolEntry()

        if var handle = entry.handle {
            // A hot acquire counts, and touches the idle clock.
            handle.acquisitions += 1
            handle.lastUsedAtMilliseconds = clock.nowMilliseconds
            entry.handle = handle
            armReap(name: name, entry: &entry)
            entries[name] = entry
            return handle
        }

        // Join a cohort already in flight. Every waiter awaits the *same* task, and that task is
        // what installs the handle — so a waiter cannot resume before the install has happened.
        // Reading the entry after awaiting instead would be a race: the continuations of a finished
        // task resume in an unspecified order, so a waiter could look before the starter wrote.
        if let flight = entry.starting {
            return try await flight.task.value
        }

        let attempt = StartAttemptID(startIDs.take())
        let timeoutMs = config.startupTimeoutMs ?? defaultStartupTimeoutMs
        let transporting = transporting
        let started = clock.nowMilliseconds

        let task = Task<PoolHandle, Error> { [weak self] in
            guard let self else { throw PoolError.shuttingDown }
            let session: any UpstreamSession
            do {
                session = try await transporting.open(config, timeoutMilliseconds: timeoutMs)
            } catch {
                await startFailed(name: name, attempt: attempt)
                throw error
            }
            return try await commit(name: name, attempt: attempt, session: session, startedAt: started)
        }
        entry.starting = StartFlight(attempt: attempt, task: task)
        entries[name] = entry

        await log?.record(config.isStdio
            ? PoolLogEvent.spawning(server: name, command: config.command ?? "", args: config.args)
            : PoolLogEvent.connecting(
                server: name, transport: config.transport.rawValue, url: config.url ?? ""
            ))

        return try await task.value
    }

    /// Clear a failed attempt, but only if it is still the current one — a retry may already have
    /// replaced it, and clearing that would strand the retry's waiters.
    private func startFailed(name: String, attempt: StartAttemptID) {
        guard var entry = entries[name], entry.starting?.attempt == attempt else { return }
        entry.starting = nil
        entries[name] = entry
    }

    /// Install a completed start — or, if it has been superseded, **close it**.
    ///
    /// This is the one the plan gate caught. A late success owns a live child; declining to install
    /// it does not close it, and shutdown cannot force-reap a handle it never saw. On this platform
    /// stdin EOF is not reliable liveness for an MCP server, so that child persists indefinitely.
    private func commit(
        name: String,
        attempt: StartAttemptID,
        session: any UpstreamSession,
        startedAt: Double
    ) async throws -> PoolHandle {
        var entry = entries[name] ?? PoolEntry()

        guard !shuttingDown, entry.starting?.attempt == attempt else {
            if entry.starting?.attempt == attempt { entry.starting = nil }
            entries[name] = entry
            await session.shutdown()
            throw shuttingDown ? PoolError.shuttingDown : PoolError.superseded(name)
        }

        let id = HandleID(handleIDs.take())
        let now = clock.nowMilliseconds
        let watcher = Task { [weak self] in
            await session.waitUntilEnded()
            await self?.sessionEnded(name: name, handle: id)
        }
        let handle = PoolHandle(
            id: id,
            session: session,
            startedAtMilliseconds: startedAt,
            lastUsedAtMilliseconds: now,
            acquisitions: 1,
            endWatcher: watcher
        )
        entry.handle = handle
        entry.starting = nil
        entries[name] = entry
        pendingAuth.removeValue(forKey: name)

        // The reference logs this the moment the handshake completes, and R2 declared the event and
        // never fired it — which nothing noticed, because no process ran the pool. It is the second
        // of the reference's three startup lines and `parity-log.sh` diffs the sequence, so a
        // missing line is a missing row rather than a missing nicety.
        await log?.record(PoolLogEvent.ready(server: name, milliseconds: jsRound(now - startedAt)))

        armReapIfIdle(name: name)
        return handle
    }

    /// An upstream that went away on its own. Identity-checked: a close from one incarnation must
    /// not evict its replacement.
    ///
    /// Ending and closing are different things, and conflating them leaks a process. "Ended" is the
    /// session telling us its receive stream finished; on stdio that is EOF on the child's stdout,
    /// which says nothing about whether the child exited — a server that closes stdout, or wedges
    /// after writing its last frame, is still running. D1 records that closing a Swift transport
    /// does not kill the child, so evicting the handle without shutting the session down strands
    /// the client, the transport, both parent descriptors and the process itself, with nothing left
    /// holding a reference that could reap it later.
    func sessionEnded(name: String, handle: HandleID) async {
        guard var entry = entries[name], let live = entry.handle, live.id == handle else { return }

        // Evict first, and without suspending. `entry` is a *copy*; a suspension here lets another
        // task install a replacement handle, which this stale copy would then erase on write-back —
        // and lets a lease taken during the gap be handed the session we are about to close.
        cancelReap(&entry)
        entry.handle = nil
        entry.inFlight = 0
        entry.activeLeases.removeAll()
        entries[name] = entry

        // Release what we still hold. Idempotent, and the watcher that brought us here has already
        // finished, so this cannot re-enter.
        await live.session.shutdown()
        await log?.record(PoolLogEvent.closedItself(server: name))
    }
}

/// JavaScript's `Math.round`: half rounds toward +∞, which differs from Swift's `rounded()`
/// (half away from zero) for negative halves. Durations here are non-negative, but the router's
/// status fields are diffed against the reference byte for byte, so the semantics are matched
/// rather than assumed equivalent.
func jsRound(_ value: Double) -> Int {
    Int((value + 0.5).rounded(.down))
}
