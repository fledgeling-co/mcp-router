import Foundation

/// Reaping, the warm set, reporting and shutdown.
///
/// An extension rather than a second type: this is the same state machine, split only because the
/// whole actor outgrew the file-length limit. Everything here is still actor-isolated.
public extension UpstreamPool {
    // MARK: - Reaping

    internal func cancelReap(_ entry: inout PoolEntry) {
        entry.reap?.task.cancel()
        entry.reap = nil
    }

    internal func armReapIfIdle(name: String) {
        guard var entry = entries[name] else { return }
        armReap(name: name, entry: &entry)
        entries[name] = entry
    }

    internal func armReap(name: String, entry: inout PoolEntry) {
        cancelReap(&entry)
        guard entry.inFlight == 0, entry.pendingWaiters == 0, let handle = entry.handle else { return }
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
    internal func reapIfStillDue(
        name: String,
        epoch: ReapEpoch,
        handle: HandleID,
        deadline: ContinuousClock.Instant
    ) async {
        guard let entry = entries[name],
              entry.reap?.epoch == epoch, // still the installed timer
              entry.handle?.id == handle, // still the same incarnation
              entry.inFlight == 0, // nothing outstanding
              ContinuousClock.now >= deadline // this timer's own deadline really passed
        else { return }
        await reap(name: name, force: false)
    }

    internal func reap(name: String, force: Bool) async {
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
    func warmUp() async {
        let warm = orderedNames.compactMap { upstreams[$0] }.filter { $0.warm == true }
        guard !warm.isEmpty else { return }
        await log?.record(PoolLogEvent.preOpeningWarm(count: warm.count, names: warm.map(\.name)))
        await withTaskGroup(of: Void.self) { group in
            for config in warm {
                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
                        let lease = try await lease(config.name)
                        await release(lease)
                    } catch {
                        await logWarmFailure(config.name, error)
                    }
                }
            }
        }
    }

    internal func logWarmFailure(_ name: String, _ error: Error) async {
        let reason = (error as? PoolError)?.description ?? error.localizedDescription
        await log?.record(PoolLogEvent.warmFailed(server: name, reason: reason))
    }

    // MARK: - Reporting

    /// Servers waiting on a browser authorization, for `/status` to report.
    func pending() -> [PendingAuth] {
        orderedNames.compactMap { pendingAuth[$0] }
    }

    func recordPendingAuth(_ auth: PendingAuth) {
        pendingAuth[auth.server] = auth
    }

    func clearPending(_ server: String) {
        pendingAuth.removeValue(forKey: server)
    }

    /// A snapshot of every upstream's live state, in configuration order.
    ///
    /// `callsServed` and `inFlight` are different questions, and the reference once conflated them:
    /// the control API reported the lifetime counter as `liveCalls`, so an idle server that had
    /// answered three calls an hour ago read as three calls in flight. Only `inFlight` blocks the
    /// reaper, so only `inFlight` is ever presented as work outstanding.
    func status() -> [UpstreamStatus] {
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
    /// The pid behind each live upstream, in configuration order.
    ///
    /// Separate from `status()` because a pid is not a status field: the reference does not report
    /// one, and adding it there would put a number on a surface R4 diffs byte for byte.
    func processIdentifiers() -> [String: Int32] {
        var out: [String: Int32] = [:]
        for name in orderedNames {
            if let pid = entries[name]?.handle?.session.processIdentifier { out[name] = pid }
        }
        return out
    }

    /// One `ps` for every pid rather than one per server: the warm set is a budget the user sets in
    /// memory, so the number behind it has to be measured. An upstream with no local process is
    /// **omitted**, matching the reference — reporting a zero would be reporting a number nobody
    /// measured, which `DESIGN.md` §6 forbids.
    func residentMb() async -> [String: Int] {
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
    /// the orphan this exists to avoid.
    ///
    /// Idempotent in the strong sense: a second caller **awaits the first** rather than returning
    /// early. Returning early would be the more obvious reading of "no-op", and it is wrong here —
    /// this is what a signal handler awaits before the process exits, so a caller that returns
    /// while children are still being terminated is exactly the orphan shutdown exists to prevent.
    /// The flag is set synchronously, before any suspension, so acquisitions are refused from the
    /// first instant regardless of which caller owns the teardown.
    func shutdown() async {
        shuttingDown = true
        if let flight = shutdownFlight {
            await flight.value
            return
        }
        let flight = Task { await performShutdown() }
        shutdownFlight = flight
        await flight.value
    }

    internal func performShutdown() async {
        let names = orderedNames.filter { entries[$0] != nil }

        // Await starts before reaping. `reap` returns immediately when there is no handle yet, so a
        // child being spawned as SIGTERM arrives would otherwise finish starting *after* shutdown
        // resolved — orphaned, with nothing left to close it.
        for name in names {
            guard let flight = entries[name]?.starting else { continue }
            _ = try? await flight.task.value
        }
        // Close concurrently: a serial loop makes shutdown as slow as the sum of every upstream's
        // teardown, and launchd does not wait forever.
        await withTaskGroup(of: Void.self) { group in
            for name in names {
                group.addTask { [weak self] in
                    await self?.reap(name: name, force: true)
                }
            }
        }
    }
}
