import Foundation
import Synchronization
import Testing
@testable import RouterCore

/// A session whose ending and shutdown are both observable and controllable.
///
/// State lives in a `Mutex`, so these doubles are genuinely `Sendable` rather than
/// `@unchecked Sendable` — the practices document forbids the latter as a way past a diagnostic,
/// and `NSLock` is unavailable from async contexts anyway.
final class FakeSession: UpstreamSession, Sendable {
    private struct State {
        var shutdownCount = 0
        var ended = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())
    let processIdentifier: Int32?
    let label: String
    /// How long `shutdown()` takes. Zero by default; a test that needs to observe whether a caller
    /// waited for teardown sets it, because an instantaneous close makes "waited" and "did not
    /// wait" indistinguishable.
    let shutdownDelayNanoseconds: UInt64

    init(label: String, processIdentifier: Int32? = nil, shutdownDelayNanoseconds: UInt64 = 0) {
        self.label = label
        self.processIdentifier = processIdentifier
        self.shutdownDelayNanoseconds = shutdownDelayNanoseconds
    }

    var shutdownCount: Int { state.withLock { $0.shutdownCount } }
    var wasShutDown: Bool { shutdownCount > 0 }

    func shutdown() async {
        if shutdownDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: shutdownDelayNanoseconds)
        }
        let waiting = state.withLock { current -> [CheckedContinuation<Void, Never>] in
            current.shutdownCount += 1
            current.ended = true
            let waiters = current.waiters
            current.waiters = []
            return waiters
        }
        // A shut-down session has ended, so anything awaiting its end is resumed rather than left
        // hanging — otherwise a test that closes cleanly would leak a suspended watcher task.
        for continuation in waiting {
            continuation.resume()
        }
    }

    /// The two calling requirements. A double has no upstream to ask, so both refuse — deliberately
    /// rather than returning an empty success, because a fake that answers `{}` would let a relay
    /// test pass while proving the relay never reached an upstream at all.
    func listTools() async throws -> JSONValue {
        throw PoolError.spawnFailed(name: label, reason: "FakeSession does not speak MCP")
    }

    func callTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        throw PoolError.spawnFailed(name: label, reason: "FakeSession does not speak MCP")
    }

    /// Simulate the upstream dying on its own — a crash, an EOF, a dropped session.
    func endOnItsOwn() {
        let waiting = state.withLock { current -> [CheckedContinuation<Void, Never>] in
            current.ended = true
            let waiters = current.waiters
            current.waiters = []
            return waiters
        }
        for continuation in waiting {
            continuation.resume()
        }
    }

    func waitUntilEnded() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyEnded = state.withLock { current -> Bool in
                if current.ended { return true }
                current.waiters.append(continuation)
                return false
            }
            if alreadyEnded { continuation.resume() }
        }
    }
}

/// A transport whose opens can be counted, delayed, failed and released on command.
final class FakeTransport: UpstreamTransporting, Sendable {
    private struct State {
        var opens = 0
        var sessions: [FakeSession] = []
        var gates: [CheckedContinuation<Void, Never>] = []
        var gated = false
        var failNext = false
        var shutdownDelayNanoseconds: UInt64 = 0
    }

    private let state = Mutex(State())

    var opens: Int { state.withLock { $0.opens } }
    var sessions: [FakeSession] { state.withLock { $0.sessions } }

    /// When set, every open parks until `openGate()` is called.
    func setGated(_ value: Bool) {
        state.withLock { $0.gated = value }
    }

    /// Make every session opened from now on take this long to close, so a test can tell a caller
    /// that waited for teardown from one that returned while it was still running.
    func setShutdownDelay(nanoseconds: UInt64) {
        state.withLock { $0.shutdownDelayNanoseconds = nanoseconds }
    }

    /// When set, the next open throws.
    func failNextOpen() {
        state.withLock { $0.failNext = true }
    }

    func open(_ upstream: UpstreamConfig, timeoutMilliseconds: Int) async throws -> any UpstreamSession {
        let (shouldFail, isGated) = state.withLock { current -> (Bool, Bool) in
            current.opens += 1
            let failing = current.failNext
            current.failNext = false
            return (failing, current.gated)
        }

        if shouldFail {
            throw PoolError.startupTimeout(name: upstream.name, milliseconds: timeoutMilliseconds)
        }
        if isGated {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                state.withLock { $0.gates.append(continuation) }
            }
        }
        let delay = state.withLock { $0.shutdownDelayNanoseconds }
        let session = FakeSession(
            label: upstream.name,
            processIdentifier: upstream.isStdio ? 4242 : nil,
            shutdownDelayNanoseconds: delay
        )
        state.withLock { $0.sessions.append(session) }
        return session
    }

    /// Let every parked open proceed.
    ///
    /// All of them, not one: a mutation that removes the pool's cohort join makes three callers
    /// park three separate opens, and a gate that released only the first would deadlock the test
    /// instead of failing it. A mutation gate that hangs proves nothing.
    func openGate() {
        let waiting = state.withLock { current -> [CheckedContinuation<Void, Never>] in
            let gates = current.gates
            current.gates = []
            return gates
        }
        for continuation in waiting {
            continuation.resume()
        }
    }

    /// Wait until an open is parked, so a test never races the thing it is arranging.
    func waitForGatedOpen() async {
        while state.withLock({ $0.gates.isEmpty }) {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

/// Wait until the pool reports a condition, rather than until a chosen number of milliseconds
/// have passed.
///
/// That distinction is the whole of G3. A fixed sleep encodes a guess about scheduler latency made
/// on a quiet machine: `PoolReapingTests`' 150ms wait for a 25ms idle window passed four times
/// running in isolation and failed under whole-suite load. Where the guess turns over is not
/// known — a deliberate reproduction at load average 114, with the test process at the lowest
/// priority, did NOT reproduce it, and the incident that filed the item happened at 548. Widening
/// the sleep only picks a different load average to be correct at. Waiting on the condition needs
/// no such choice: a busy machine makes this slower and never wrong.
///
/// `within` is a deadlock breaker rather than the observation. The events here are actor hops that
/// take microseconds, so ten seconds is four orders of magnitude of headroom, and its expiry is
/// **reported as a failure naming the condition** — a mutation that stops the event happening
/// fails with a reason instead of hanging the suite. It was thirty seconds first, and the mutation
/// gate is what argued it down: killing eviction made the run take 33 seconds to say so.
/// It **throws** rather than recording an issue, because a recorded issue lets execution carry on
/// into assertions whose precondition never held — one timeout then reports as a cascade of
/// secondary failures that did not happen. And the poll is cancellation-aware: swallowing the
/// cancellation would turn the sleep into a no-op and spin this loop until the deadline.
func waitUntil(
    _ what: Comment,
    within seconds: Double = 10,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
    var cancelled = false
    while ContinuousClock.now < deadline {
        if await condition() { return }
        do { try await Task.sleep(nanoseconds: 2_000_000) } catch { cancelled = true; break }
    }
    let why = cancelled ? "the waiting task was cancelled" : "timed out after \(seconds)s"
    try #require(Bool(false), "\(why) waiting for: \(what)", sourceLocation: sourceLocation)
}

/// Await an event the pool owns, under the same deadlock breaker `waitUntil` uses.
///
/// `awaitReap` and `awaitSessionEnded` await a `Task` the pool started, so the only bound on them
/// is the pool's own armed window — and P6 configures that at 600 000 ms, because a default that
/// is effectively never is what makes the per-server override provable. Awaiting one unbounded
/// turns a regression in the reaping path into a run that ends without naming a test: the
/// mutation that reaps at the default window while the arming records the requested one measured
/// **601.184 seconds**, and even then the single issue landed on the residual clock-dependency
/// line rather than on the window claim; killed at 150 seconds it exits 142 with no test name at
/// all. This item's thesis ranks a nameless timeout below a flake, so the awaits get the bound
/// the polls already have, and a regression in this class names an assertion inside the CI bound.
///
/// The wait is **abandoned**, not cancelled. A task group around `await task.value` as it stands
/// would not help: that call on a `Task<_, Never>` has no cancellation check, so the group awaits
/// the loser after `cancelAll()` and the run still takes ten minutes — the bound landing on the
/// wrong side of the await. An observer records the landing instead and this polls that record, so
/// giving up costs one task that finishes by itself later, in a run that has already gone red.
///
/// **A group is not ruled out, only that shape of one**, and the correction is a reviewer's rather
/// than mine: make the WAIT cancellation-aware and a group abandons it properly. `AuthorizationURLBox`
/// in `OAuthFlowStarter.swift` is that construction, written here for this exact hang — a race whose
/// losing child could not be resumed by cancellation ran 91 seconds against a 20-second budget. A
/// continuation resumed by whichever of event or deadline arrives first would also retire the 2ms
/// poll and `D-g3-i` with it. It is `D-g3-k`, deferred rather than dismissed: this poll is measured
/// and the handshake would need its own mutation evidence to be worth more than it.
///
/// Ten seconds is a **smaller** margin here than it is on `waitUntil`, and is stated rather than
/// inherited: the conditions there are actor hops taking microseconds, while the events here
/// include the pool's own 25ms and 30ms windows, so the headroom is 300-400x rather than four
/// orders of magnitude. It is still 66x the 150ms budget that produced this item's original red.
/// Reaching it needs the machine to stretch a 25ms window past ten seconds, which is the total
/// starvation `waitUntil`'s own note describes and not a load a number could be chosen against.
///
/// `event` should **await an outcome rather than do work**. On the timed-out path the observer
/// outlives the test that started it, holding the pool until the arming it is parked on completes;
/// the five call sites here only await, so nothing acts late, and the reap that eventually runs is
/// the pool's own task, which exists whether or not anything is watching it. Put work in the
/// closure and that stops being true. An out-of-family reviewer read the leak as the observer
/// performing pool cleanup during later tests; it does not, and this is what keeps that so.
func awaitEvent(
    _ what: Comment,
    within seconds: Double = 10,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ event: @escaping @Sendable () async -> Void
) async throws {
    let landed = Mutex(false)
    let observer = Task { await event(); landed.withLock { $0 = true } }
    // Cancelling buys nothing on the timed-out path — the observer is parked in `await
    // task.value`, which ignores cancellation — but leaving a task uncancelled on the way out is
    // worse hygiene than saying so, and it does stop the observer if `event` ever gains a check.
    defer { observer.cancel() }
    try await waitUntil(what, within: seconds, sourceLocation: sourceLocation) {
        landed.withLock { $0 }
    }
}

/// A clock the test drives, so an idle window can be asserted rather than slept through.
final class TestClock: RouterClock, Sendable {
    private let now: Mutex<Double>

    init(now: Double = 1_000_000) {
        self.now = Mutex(now)
    }

    var nowMilliseconds: Double { now.withLock { $0 } }

    func advance(_ milliseconds: Double) {
        now.withLock { $0 += milliseconds }
    }
}

func stdioUpstream(
    _ name: String,
    idleMs: Int? = nil,
    warm: Bool? = nil,
    startupTimeoutMs: Int? = nil
) -> UpstreamConfig {
    UpstreamConfig(
        name: name,
        transport: .stdio,
        raw: .object([]),
        idleMs: idleMs,
        startupTimeoutMs: startupTimeoutMs,
        projects: nil,
        warm: warm,
        placard: nil,
        command: "/bin/echo",
        args: [name],
        env: [],
        cwd: nil,
        url: nil,
        headers: [],
        oauth: nil
    )
}

func httpUpstream(_ name: String, transport: ServerTransport = .http) -> UpstreamConfig {
    UpstreamConfig(
        name: name,
        transport: transport,
        raw: .object([]),
        idleMs: nil,
        startupTimeoutMs: nil,
        projects: nil,
        warm: nil,
        placard: nil,
        command: nil,
        args: [],
        env: [],
        cwd: nil,
        url: "https://example.test/mcp",
        headers: [],
        oauth: nil
    )
}

/// A sink that makes one *chosen* log line take real time.
///
/// Logging is a hop to another actor, and an actor hop is a suspension point: anything the pool has
/// not finished before it is not atomic, however synchronous the surrounding code looks. Blocking
/// the sink turns that invisible window into one a test can act inside.
/// Matched on the line's text rather than by position: blocking "the first write" blocks whichever
/// line happens to come first, and a cold start logs a spawn long before anything closes — the
/// window would then open and shut before the code under test ever ran.
final class BlockingSink: LogSink, Sendable {
    private let armed = Mutex<Bool>(true)
    private let marker: String
    private let seconds: Double

    init(matching marker: String, seconds: Double = 0.3) {
        self.marker = marker
        self.seconds = seconds
    }

    func write(_ bytes: Data) throws {
        guard let line = String(bytes: bytes, encoding: .utf8), line.contains(marker) else { return }
        let shouldBlock = armed.withLock { pending -> Bool in
            defer { pending = false }
            return pending
        }
        if shouldBlock { Thread.sleep(forTimeInterval: seconds) }
    }
}
