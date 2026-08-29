import Foundation
import Synchronization
import Testing
@testable import RouterCore

/// A session that answers `tools/list` — or refuses, or never answers at all.
///
/// `FakeSession` in `PoolTestSupport` deliberately throws from `listTools`, so that a relay test
/// cannot pass while never reaching an upstream. A probe suite needs the success path, so it
/// carries its own double rather than weakening the shared one.
final class AnsweringSession: UpstreamSession, Sendable {
    enum Behaviour: Sendable {
        case answers(tools: Int)
        case refuses(String)
        /// Parks until cancelled — the wedged upstream the probe budget exists for.
        case hangs
    }

    let processIdentifier: Int32? = nil
    private let behaviour: Behaviour
    private let calls = Mutex(0)

    init(_ behaviour: Behaviour) {
        self.behaviour = behaviour
    }

    var listCalls: Int { calls.withLock { $0 } }

    func listTools() async throws -> JSONValue {
        calls.withLock { $0 += 1 }
        switch behaviour {
        case let .answers(tools):
            let entries = (0 ..< tools).map { index -> JSONValue in
                .object([JSONMember(key: "name", value: .string(JSString("t\(index)")))])
            }
            return .object([JSONMember(key: "tools", value: .array(entries))])
        case let .refuses(reason):
            throw PoolError.spawnFailed(name: "probe", reason: reason)
        case .hangs:
            // Cancellable, so the abandoned loser of the race really ends rather than leaking a
            // parked task into the rest of the suite.
            try await Task.sleep(nanoseconds: 30_000_000_000)
            return .object([])
        }
    }

    func callTool(name _: String, arguments _: JSONValue) async throws -> JSONValue {
        throw PoolError.spawnFailed(name: "probe", reason: "not used by the health probe")
    }

    func shutdown() async {}

    func waitUntilEnded() async {
        try? await Task.sleep(nanoseconds: 30_000_000_000)
    }
}

/// Opens one ``AnsweringSession`` per upstream, and counts the opens.
final class AnsweringTransport: UpstreamTransporting, Sendable {
    private struct State {
        var opens = 0
        var sessions: [AnsweringSession] = []
    }

    private let state = Mutex(State())
    private let behaviour: AnsweringSession.Behaviour

    init(_ behaviour: AnsweringSession.Behaviour) {
        self.behaviour = behaviour
    }

    var opens: Int { state.withLock { $0.opens } }
    var sessions: [AnsweringSession] { state.withLock { $0.sessions } }

    func open(_: UpstreamConfig, timeoutMilliseconds _: Int) async throws -> any UpstreamSession {
        let session = AnsweringSession(behaviour)
        state.withLock {
            $0.opens += 1
            $0.sessions.append(session)
        }
        return session
    }
}

/// R27 — ``PoolUpstreamProbe`` against a real ``UpstreamPool``.
///
/// This is the production probe, not a stub: the same object the daemon hands the monitor. What it
/// cannot establish is the effect at the far end — that a stdio upstream really becomes a child
/// process — because the transport here is a double. That claim belongs to
/// `planning/test-campaign/bin/witness-health-probe.sh`, which drives the daemon's own socket and
/// reads the spawn out of the child's own `getppid()`.
@Suite("R27 pool-backed probe")
struct UpstreamHealthProbeTests {
    private static func pool(
        _ transport: AnsweringTransport, idleMs: Int = 600_000
    ) -> UpstreamPool {
        UpstreamPool(
            upstreams: [stdioUpstream("s1")],
            defaultIdleMilliseconds: idleMs,
            defaultStartupTimeoutMilliseconds: 5000,
            transporting: transport
        )
    }

    @Test("H25 — a probe of a cold upstream opens it, asks for its tools, and counts them")
    func probeOpensAndLists() async throws {
        let transport = AnsweringTransport(.answers(tools: 3))
        let pool = Self.pool(transport)
        let probe = PoolUpstreamProbe(pool: pool)

        #expect(await pool.isLive("s1") == false)
        let outcome = await probe.probe("s1", timeoutMilliseconds: 5000)
        guard case let .ok(_, tools) = outcome else {
            Issue.record("expected an ok outcome, got \(outcome)")
            return
        }
        #expect(tools == 3)
        #expect(transport.opens == 1)
        #expect(try #require(transport.sessions.first).listCalls == 1)
        await pool.shutdown()
    }

    @Test("H26 — the lease is released, so a probe does not pin the upstream open")
    func probeReleasesItsLease() async {
        let transport = AnsweringTransport(.answers(tools: 1))
        let pool = Self.pool(transport)
        _ = await PoolUpstreamProbe(pool: pool).probe("s1", timeoutMilliseconds: 5000)

        // A probe that leaked its lease would leave `inFlight` at 1 forever, and the reaper would
        // never close the child — a health check that keeps every server it visits alive is the
        // failure this whole design is arranged around.
        let row = await pool.status().first { $0.name == "s1" }
        #expect(row?.inFlight == 0)
        await pool.shutdown()
    }

    @Test("H27 — an upstream that will not answer is a timeout, bounded by the policy")
    func wedgedUpstreamTimesOut() async {
        let transport = AnsweringTransport(.hangs)
        let pool = Self.pool(transport)

        let outcome = await PoolUpstreamProbe(pool: pool).probe("s1", timeoutMilliseconds: 60)
        guard case let .timedOut(afterMs) = outcome else {
            Issue.record("expected a timeout, got \(outcome)")
            return
        }
        #expect(afterMs == 60)
        await pool.shutdown()
    }

    @Test("H28 — an upstream that errors is `failed` with its own words, not a timeout")
    func refusalIsReportedVerbatim() async {
        let transport = AnsweringTransport(.refuses("upstream said no"))
        let pool = Self.pool(transport)

        let outcome = await PoolUpstreamProbe(pool: pool).probe("s1", timeoutMilliseconds: 5000)
        guard case let .failed(reason) = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        // "the child never started" and "the child answered too slowly" are different things to
        // act on, so the two never collapse into one word here.
        #expect(reason.contains("upstream said no"))
        await pool.shutdown()
    }

    @Test("H29 — an unknown upstream is a failure carrying the pool's own reason")
    func unknownUpstreamFails() async {
        let pool = Self.pool(AnsweringTransport(.answers(tools: 1)))
        let outcome = await PoolUpstreamProbe(pool: pool).probe("ghost", timeoutMilliseconds: 5000)
        guard case let .failed(reason) = outcome else {
            Issue.record("expected a failure, got \(outcome)")
            return
        }
        #expect(reason.contains("ghost"))
        await pool.shutdown()
    }

    @Test("H30 — `isLive` reports the pool's own answer rather than a cached guess")
    func isLiveTracksThePool() async {
        let transport = AnsweringTransport(.answers(tools: 1))
        let pool = Self.pool(transport)
        let probe = PoolUpstreamProbe(pool: pool)

        #expect(await probe.isLive("s1") == false)
        _ = await probe.probe("s1", timeoutMilliseconds: 5000)
        #expect(await probe.isLive("s1"))
        await pool.shutdown()
        #expect(await probe.isLive("s1") == false)
    }
}
