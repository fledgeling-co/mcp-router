import Foundation
import Testing
@testable import RouterCore

/// E0 evidence: every clause here is discharged against a **real child process** — real pipes, real
/// signals, real PATH resolution, a real MCP handshake over the pinned SDK.
///
/// The fake-transport suites prove the pool's state machine and are worth keeping for that. They
/// cannot prove any of this. A double never fills a pipe buffer, never ignores SIGTERM, never
/// survives its parent, and never leaves an orphan behind when a start times out.
@Suite("Real child processes", .serialized)
struct RealProcessTests {
    private func directory() throws -> URL {
        try StubServer.makeDirectory()
    }

    private func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("E0/P1 — a stdio upstream is a real process, and shutdown actually kills it")
    func realChildIsSpawnedAndKilled() async throws {
        let directory = try directory()
        defer { remove(directory) }
        let transport = StdioUpstreamTransport()

        let session = try await transport.open(
            StubServer.config(name: "real", mode: .responsive, directory: directory),
            timeoutMilliseconds: 5000
        )

        let pid = try #require(session.processIdentifier)
        #expect(StubServer.isAlive(pid), "the handshake completed, so there is a live child")
        #expect(pid == StubServer.reportedPidSync(name: "real", directory: directory))

        await session.shutdown()
        #expect(await StubServer.waitUntilGone(pid), "shutdown must reap the child, not just drop it")
    }

    @Test("E0/P1a — the child is launched with the configured argv, cwd and environment")
    func childIsLaunchedAsConfigured() async throws {
        let directory = try directory()
        defer { remove(directory) }
        let workingDirectory = directory.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)

        // `PATH` is deliberately one of the overrides: the reference merges the router's own
        // environment first and lets the server win, and a router that merged the other way would
        // look identical until a server tried to override something that mattered.
        let config = try StubServer.config(
            name: "launched",
            mode: .reports,
            directory: directory,
            extraArguments: ["--flag", "value with spaces"],
            environment: [
                JSStringPair(key: JSString("ROUTER_TEST_TOKEN"), value: JSString("from-config")),
                JSStringPair(
                    key: JSString("PATH"),
                    value: JSString(ProcessInfo.processInfo.environment["PATH"] ?? "")
                )
            ],
            workingDirectory: workingDirectory.path
        )
        let session = try await StdioUpstreamTransport().open(config, timeoutMilliseconds: 8000)
        defer { Task { await session.shutdown() } }

        let launch = try StubServer.launch(name: "launched", directory: directory)
        #expect(
            launch.argv == ["--flag", "value with spaces"],
            "arguments are passed as an array, not a shell string"
        )
        #expect(URL(fileURLWithPath: launch.cwd).resolvingSymlinksInPath().path
            == workingDirectory.resolvingSymlinksInPath().path)
        #expect(launch.env["ROUTER_TEST_TOKEN"] == "from-config", "the server's own env must reach it")
        #expect(launch.env["HOME"] != nil, "the router's environment is inherited, not replaced")
    }

    @Test("E0/P2a — a start that times out leaves no orphan behind")
    func timedOutStartLeavesNoOrphan() async throws {
        let directory = try directory()
        defer { remove(directory) }
        let transport = StdioUpstreamTransport()

        // The pid comes from the child's own file: a failed open returns no session to ask, and the
        // claim under test is precisely about a process whose handle we never received.
        let config = try StubServer.config(name: "slow", mode: .silent, directory: directory)
        let opening = Task { try await transport.open(config, timeoutMilliseconds: 400) }
        let pid = await StubServer.reportedPid(name: "slow", directory: directory)

        await #expect(throws: PoolError.startupTimeout(name: "slow", milliseconds: 400)) {
            _ = try await opening.value
        }
        let child = try #require(pid, "the stub should have recorded its pid before the timeout")
        #expect(await StubServer.waitUntilGone(child), "a throwing open must leave nothing running")
    }

    @Test("E0/P9 — a child that ignores SIGTERM is killed rather than allowed to hold shutdown open")
    func stubbornChildIsKilled() async throws {
        let directory = try directory()
        defer { remove(directory) }
        // A short grace so the escalation is what the test measures, not the wait.
        let transport = StdioUpstreamTransport(terminationGraceNanoseconds: 300_000_000)

        let session = try await transport.open(
            StubServer.config(name: "stubborn", mode: .stubborn, directory: directory),
            timeoutMilliseconds: 5000
        )
        let pid = try #require(session.processIdentifier)
        #expect(StubServer.isAlive(pid))

        let started = ContinuousClock.now
        await session.shutdown()
        let elapsed = started.duration(to: .now)

        #expect(!StubServer.isAlive(pid), "SIGTERM was ignored, so SIGKILL must have followed")
        #expect(elapsed < .seconds(4), "shutdown waited \(elapsed); the grace is meant to bound it")
    }

    @Test("E0 — a server that floods stderr still completes its handshake")
    func chattyChildDoesNotWedge() async throws {
        let directory = try directory()
        defer { remove(directory) }
        let transport = StdioUpstreamTransport()

        // 300 KB of stderr before the first reply. Undrained, the child blocks writing it and the
        // handshake never happens — which would surface as a startup timeout, not as a pipe bug.
        let session = try await transport.open(
            StubServer.config(name: "chatty", mode: .chatty, directory: directory),
            timeoutMilliseconds: 8000
        )
        let pid = try #require(session.processIdentifier)
        #expect(StubServer.isAlive(pid))
        await session.shutdown()
        #expect(await StubServer.waitUntilGone(pid))
    }

    @Test("E0/P1+P3+P6 — the pool spawns a real child on first lease and reaps it when idle")
    func poolSpawnsAndReapsARealChild() async throws {
        let directory = try directory()
        defer { remove(directory) }
        let config = try StubServer.config(
            name: "pooled", mode: .responsive, directory: directory, idleMs: 250
        )
        let pool = UpstreamPool(
            upstreams: [config],
            defaultIdleMilliseconds: 250,
            defaultStartupTimeoutMilliseconds: 5000,
            transporting: StdioUpstreamTransport()
        )

        #expect(await !pool.isLive("pooled"), "nothing is spawned before a call arrives")

        let lease = try await pool.lease("pooled")
        let pid = try #require(await pool.processIdentifiers()["pooled"])
        #expect(StubServer.isAlive(pid))
        #expect(lease.cold, "the call that paid for the start is the cold one")

        await pool.release(lease)
        #expect(await StubServer.waitUntilGone(pid), "the idle window elapsed; the child must be gone")
        #expect(await !pool.isLive("pooled"))
        await pool.shutdown()
    }

    @Test("E0/P8 — a real child that exits on its own is evicted and reopened on the next call")
    func realChildThatExitsIsEvicted() async throws {
        let directory = try directory()
        defer { remove(directory) }
        let trigger = directory.appendingPathComponent("please-exit")
        let config = try StubServer.config(
            name: "quitter",
            mode: .exitsOnTrigger,
            directory: directory,
            trigger: trigger,
            idleMs: 60000
        )
        let pool = UpstreamPool(
            upstreams: [config],
            defaultIdleMilliseconds: 60000,
            defaultStartupTimeoutMilliseconds: 5000,
            transporting: StdioUpstreamTransport()
        )

        let first = try await pool.lease("quitter")
        let firstPid = try #require(await pool.processIdentifiers()["quitter"])
        await pool.release(first)

        FileManager.default.createFile(atPath: trigger.path, contents: nil)
        #expect(await StubServer.waitUntilGone(firstPid))

        // The eviction is driven by the end-watcher, so it is observed rather than assumed.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while await pool.isLive("quitter"), ContinuousClock.now < deadline {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        #expect(await !pool.isLive("quitter"), "the pool must notice a child that died underneath it")

        try? FileManager.default.removeItem(at: trigger)
        let second = try await pool.lease("quitter")
        let secondPid = try #require(await pool.processIdentifiers()["quitter"])
        #expect(secondPid != firstPid, "the next call reopens rather than reusing a dead handle")
        #expect(second.cold, "reopening is a cold start and is reported as one")
        await pool.release(second)
        await pool.shutdown()
        #expect(await StubServer.waitUntilGone(secondPid))
    }

    @Test("E0/P2 — concurrent callers on a cold upstream spawn exactly one real child")
    func concurrentLeasesSpawnOneRealChild() async throws {
        let directory = try directory()
        defer { remove(directory) }
        let config = try StubServer.config(
            name: "shared", mode: .responsive, directory: directory, idleMs: 60000
        )
        let pool = UpstreamPool(
            upstreams: [config],
            defaultIdleMilliseconds: 60000,
            defaultStartupTimeoutMilliseconds: 8000,
            transporting: StdioUpstreamTransport()
        )

        // Five callers arriving while the child is still starting. Without a cohort this spawns five
        // interpreters and keeps one, which a fake transport can count but cannot make expensive.
        let leases = try await withThrowingTaskGroup(of: UpstreamLease.self) { group in
            for _ in 0 ..< 5 {
                group.addTask { try await pool.lease("shared") }
            }
            var collected: [UpstreamLease] = []
            for try await lease in group {
                collected.append(lease)
            }
            return collected
        }

        #expect(leases.count == 5)
        #expect(Set(leases.map(\.handle)).count == 1, "every caller must be given the same upstream")
        // Every member of a cold cohort is labelled cold, and that is parity rather than an
        // oversight: the reference reads `!pool.isLive(name)` before the call at `router.ts:136`,
        // so in Node all N concurrent callers also see a dead upstream and all N are marked cold.
        // Narrowing this to "the one that paid" would read better and diff worse.
        let coldCount = leases.filter(\.cold).count
        #expect(coldCount == leases.count, "matches the reference's pre-call isLive read")

        let pid = try #require(await pool.processIdentifiers()["shared"])
        #expect(StubServer.isAlive(pid))
        for lease in leases {
            await pool.release(lease)
        }
        await pool.shutdown()
        #expect(await StubServer.waitUntilGone(pid))
    }

    @Test("E0/P10 — memory is measured from a live child, and absent for one that is not running")
    func residentMemoryIsMeasuredNotInvented() async throws {
        let directory = try directory()
        defer { remove(directory) }
        let configs = try ["live", "idle"].map {
            try StubServer.config(name: $0, mode: .responsive, directory: directory, idleMs: 60000)
        }
        let pool = UpstreamPool(
            upstreams: configs,
            defaultIdleMilliseconds: 60000,
            defaultStartupTimeoutMilliseconds: 5000,
            transporting: StdioUpstreamTransport()
        )

        let lease = try await pool.lease("live")
        let measured = await pool.residentMb()

        // DESIGN.md forbids displaying a number the router does not observe, so the assertion is
        // that this figure came from `ps` reading a real process — not that it has some value.
        let resident = try #require(measured["live"])
        #expect(resident > 0, "a running Python interpreter has a resident set; \(resident) MB is not it")
        #expect(measured["idle"] == nil, "an upstream that was never started reports nothing at all")

        await pool.release(lease)
        await pool.shutdown()
    }

    @Test("E0/P9 — shutdown reaps every real child it opened")
    func shutdownReapsEveryChild() async throws {
        let directory = try directory()
        defer { remove(directory) }
        let configs = try ["one", "two"].map {
            try StubServer.config(name: $0, mode: .responsive, directory: directory, idleMs: 60000)
        }
        let pool = UpstreamPool(
            upstreams: configs,
            defaultIdleMilliseconds: 60000,
            defaultStartupTimeoutMilliseconds: 5000,
            transporting: StdioUpstreamTransport()
        )

        for name in ["one", "two"] {
            let lease = try await pool.lease(name)
            await pool.release(lease)
        }
        let pids = await Array(pool.processIdentifiers().values)
        #expect(pids.count == 2)

        await pool.shutdown()
        for pid in pids {
            #expect(await StubServer.waitUntilGone(pid), "pid \(pid) outlived the router")
        }
    }
}
