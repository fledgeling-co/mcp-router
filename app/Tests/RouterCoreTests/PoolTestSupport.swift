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

    init(label: String, processIdentifier: Int32? = nil) {
        self.label = label
        self.processIdentifier = processIdentifier
    }

    var shutdownCount: Int { state.withLock { $0.shutdownCount } }
    var wasShutDown: Bool { shutdownCount > 0 }

    func shutdown() async {
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
    }

    private let state = Mutex(State())

    var opens: Int { state.withLock { $0.opens } }
    var sessions: [FakeSession] { state.withLock { $0.sessions } }

    /// When set, every open parks until `openGate()` is called.
    func setGated(_ value: Bool) {
        state.withLock { $0.gated = value }
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
        let session = FakeSession(label: upstream.name, processIdentifier: upstream.isStdio ? 4242 : nil)
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
