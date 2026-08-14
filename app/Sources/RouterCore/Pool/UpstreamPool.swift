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
    private var upstreams: [String: UpstreamConfig]
    private let orderedNames: [String]
    private let defaultIdleMs: Int
    private let defaultStartupTimeoutMs: Int
    private let transporting: any UpstreamTransporting
    private let clock: any RouterClock
    private let log: RouterLog?

    private var entries: [String: PoolEntry] = [:]
    private var pendingAuth: [String: PendingAuth] = [:]
    private var shuttingDown = false

    private var startIDs = IdentitySequence()
    private var handleIDs = IdentitySequence()
    private var epochIDs = IdentitySequence()
    private var leaseIDs = IdentitySequence()

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
        self.orderedNames = upstreams.map(\.name)
        self.upstreams = Dictionary(uniqueKeysWithValues: upstreams.map { ($0.name, $0) })
        self.defaultIdleMs = defaultIdleMilliseconds
        self.defaultStartupTimeoutMs = defaultStartupTimeoutMilliseconds
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
        let handle = try await acquire(name: name, config: config)

        // Everything from here to the return is synchronous, so no reap, close or shutdown can
        // interleave: this is the critical section the "atomic lease" claim is actually about.
        guard !shuttingDown else {
            throw PoolError.shuttingDown
        }
        var entry = entries[name] ?? PoolEntry()
        guard entry.handle?.id == handle.id else {
            // The handle we acquired was replaced while we were suspended. Refuse rather than lease
            // a handle the pool no longer owns.
            throw PoolError.superseded(name)
        }
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

    /// Whether this upstream is live right now — used to label a call as a cold start.
    public func isLive(_ name: String) -> Bool { entries[name]?.handle != nil }

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
        let transporting = self.transporting
        let started = clock.nowMilliseconds

        let task = Task<PoolHandle, Error> { [weak self] in
            guard let self else { throw PoolError.shuttingDown }
            let session: any UpstreamSession
            do {
                session = try await transporting.open(config, timeoutMilliseconds: timeoutMs)
            } catch {
                await self.startFailed(name: name, attempt: attempt)
                throw error
            }
            return try await self.commit(name: name, attempt: attempt, session: session, startedAt: started)
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

        armReapIfIdle(name: name)
        return handle
    }

    /// An upstream that went away on its own. Identity-checked: a close from one incarnation must
    /// not evict its replacement.
    func sessionEnded(name: String, handle: HandleID) async {
        guard var entry = entries[name], entry.handle?.id == handle else { return }
        await log?.record(PoolLogEvent.closedItself(server: name))
        cancelReap(&entry)
        entry.handle = nil
        entry.inFlight = 0
        entry.activeLeases.removeAll()
        entries[name] = entry
    }

    // MARK: - Reaping

    private func cancelReap(_ entry: inout PoolEntry) {
        entry.reap?.task.cancel()
        entry.reap = nil
    }

    private func armReapIfIdle(name: String) {
        guard var entry = entries[name] else { return }
        armReap(name: name, entry: &entry)
        entries[name] = entry
    }

    private func armReap(name: String, entry: inout PoolEntry) {
        cancelReap(&entry)
        guard entry.inFlight == 0, let handle = entry.handle else { return }
        guard let config = upstreams[name] else { return }

        // A warm server is one the user has committed to paying for. Reaping it would undo the only
        // thing it was kept open to buy.
        if config.warm == true { return }

        let idleMs = config.idleMs ?? defaultIdleMs
        if idleMs <= 0 { return } // 0 disables reaping for this server

        let epoch = ReapEpoch(epochIDs.take())
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(idleMs))
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(idleMs) * 1_000_000)
            await self?.reapIfStillDue(name: name, epoch: epoch, handle: handle.id, deadline: deadline)
        }
        entry.reap = ReapTimer(epoch: epoch, deadline: deadline, task: task)
    }

    /// The woken timer's four-part check.
    ///
    /// Cancellation in Swift is cooperative, so a cancelled sleeping task can still wake and run
    /// here. `clearTimeout` guarantees a JavaScript timer never fires again; nothing guarantees that
    /// in Swift, so the guarantee is rebuilt out of comparisons.
    ///
    /// Each clause states **its own** invariant, and the deadline compared is the woken task's own
    /// rather than whichever timer happens to be installed now. An earlier version compared against
    /// `entry.reap`'s deadline, which quietly made the epoch check redundant — the mutation gate
    /// caught it: removing the epoch left the test green, because a stale waker was being rejected
    /// by a deadline belonging to a timer it had nothing to do with. Two checks, one of which can
    /// never fail, is one check and a decoration.
    func reapIfStillDue(
        name: String,
        epoch: ReapEpoch,
        handle: HandleID,
        deadline: ContinuousClock.Instant
    ) async {
        guard let entry = entries[name],
              entry.reap?.epoch == epoch,          // still the installed timer
              entry.handle?.id == handle,          // still the same incarnation
              entry.inFlight == 0,                 // nothing outstanding
              ContinuousClock.now >= deadline      // this timer's own deadline really passed
        else { return }
        await reap(name: name, force: false)
    }

    private func reap(name: String, force: Bool) async {
        guard var entry = entries[name], let handle = entry.handle else { return }
        if !force, entry.inFlight > 0 { return }

        entry.handle = nil
        cancelReap(&entry)
        entry.inFlight = 0
        entry.activeLeases.removeAll()
        entries[name] = entry

        // Cancel the watcher *before* closing, so our own deliberate close is not reported back as
        // the upstream dying on its own.
        handle.endWatcher?.cancel()

        let aliveMs = clock.nowMilliseconds - handle.startedAtMilliseconds
        let kind: PoolLogEvent.Kind = (upstreams[name]?.isStdio ?? true) ? .child : .connection
        await log?.record(PoolLogEvent.closingIdle(
            server: name,
            kind: kind,
            calls: handle.acquisitions,
            aliveSeconds: jsRound(aliveMs / 1000)
        ))
        await handle.session.shutdown()
    }

    // MARK: - Warm set

    /// Open every server marked warm, concurrently.
    ///
    /// Failures are logged and swallowed: a warm server that will not start is a problem to report,
    /// never a reason the router does not come up.
    public func warmUp() async {
        let warm = orderedNames.compactMap { upstreams[$0] }.filter { $0.warm == true }
        guard !warm.isEmpty else { return }
        await log?.record(PoolLogEvent.preOpeningWarm(count: warm.count, names: warm.map(\.name)))
        await withTaskGroup(of: Void.self) { group in
            for config in warm {
                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
                        let lease = try await self.lease(config.name)
                        await self.release(lease)
                    } catch {
                        await self.logWarmFailure(config.name, error)
                    }
                }
            }
        }
    }

    private func logWarmFailure(_ name: String, _ error: Error) async {
        let reason = (error as? PoolError)?.description ?? error.localizedDescription
        await log?.record(PoolLogEvent.warmFailed(server: name, reason: reason))
    }

    // MARK: - Reporting

    /// Servers waiting on a browser authorization, for `/status` to report.
    public func pending() -> [PendingAuth] {
        orderedNames.compactMap { pendingAuth[$0] }
    }

    public func recordPendingAuth(_ auth: PendingAuth) {
        pendingAuth[auth.server] = auth
    }

    public func clearPending(_ server: String) {
        pendingAuth.removeValue(forKey: server)
    }

    /// A snapshot of every upstream's live state, in configuration order.
    ///
    /// `callsServed` and `inFlight` are different questions, and the reference once conflated them:
    /// the control API reported the lifetime counter as `liveCalls`, so an idle server that had
    /// answered three calls an hour ago read as three calls in flight. Only `inFlight` blocks the
    /// reaper, so only `inFlight` is ever presented as work outstanding.
    public func status() -> [UpstreamStatus] {
        orderedNames.compactMap { name -> UpstreamStatus? in
            guard let config = upstreams[name] else { return nil }
            let transport = config.transport.rawValue
            let entry = entries[name]
            if let handle = entry?.handle {
                return UpstreamStatus(
                    name: name,
                    transport: transport,
                    state: "running",
                    callsServed: handle.acquisitions,
                    inFlight: entry?.inFlight ?? 0,
                    idleSec: jsRound((clock.nowMilliseconds - handle.lastUsedAtMilliseconds) / 1000)
                )
            }
            if entry?.starting != nil {
                return UpstreamStatus(
                    name: name, transport: transport, state: "starting",
                    callsServed: 0, inFlight: entry?.inFlight ?? 0, idleSec: 0
                )
            }
            return UpstreamStatus(
                name: name, transport: transport, state: "idle",
                callsServed: 0, inFlight: 0, idleSec: 0
            )
        }
    }

    /// Resident size of each live stdio child, in MB.
    ///
    /// One `ps` for every pid rather than one per server: the warm set is a budget the user sets in
    /// memory, so the number behind it has to be measured. An upstream with no local process is
    /// **omitted**, matching the reference — reporting a zero would be reporting a number nobody
    /// measured, which `DESIGN.md` §6 forbids.
    public func residentMb() async -> [String: Int] {
        var pids: [(String, Int32)] = []
        for name in orderedNames {
            if let pid = entries[name]?.handle?.session.processIdentifier { pids.append((name, pid)) }
        }
        guard !pids.isEmpty else { return [:] }
        let byPid = await ProcessResident.residentKilobytes(pids.map(\.1))
        var out: [String: Int] = [:]
        for (name, pid) in pids {
            out[name] = byPid[pid].map { Int((Double($0) / 1024).rounded()) } ?? 0
        }
        return out
    }

    // MARK: - Shutdown

    /// Refuse new acquisitions, await every start in flight, cancel every timer, then force-reap
    /// everything — including entries with calls outstanding, because leaving a child open there is
    /// the orphan this exists to avoid. Idempotent.
    public func shutdown() async {
        shuttingDown = true
        let names = orderedNames.filter { entries[$0] != nil }

        // Await starts before reaping. `reap` returns immediately when there is no handle yet, so a
        // child being spawned as SIGTERM arrives would otherwise finish starting *after* shutdown
        // resolved — orphaned, with nothing left to close it.
        for name in names {
            guard let flight = entries[name]?.starting else { continue }
            _ = try? await flight.task.value
        }
        for name in names {
            await reap(name: name, force: true)
        }
    }
}

/// JavaScript's `Math.round`: half rounds toward +∞, which differs from Swift's `rounded()`
/// (half away from zero) for negative halves. Durations here are non-negative, but the router's
/// status fields are diffed against the reference byte for byte, so the semantics are matched
/// rather than assumed equivalent.
func jsRound(_ value: Double) -> Int {
    Int((value + 0.5).rounded(.down))
}
