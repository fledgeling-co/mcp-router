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
/// running in isolation and failed under whole-suite load, and this repository has since been
/// observed at a load average where it would have failed every time. Widening the sleep only moves
/// the threshold onto the next machine. Waiting on the condition removes it — a busy machine makes
/// this slower and never wrong.
///
/// `within` is a deadlock breaker rather than the observation. It is three orders of magnitude
/// above the events these tests wait on, and its expiry is **reported as a failure naming the
/// condition**, so a mutation that stops the event happening at all fails with a reason instead of
/// hanging the suite.
func waitUntil(
    _ what: Comment,
    within seconds: Double = 30,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @Sendable () async -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    Issue.record("timed out after \(seconds)s waiting for: \(what)", sourceLocation: sourceLocation)
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
