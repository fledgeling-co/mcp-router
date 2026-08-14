import Foundation
import Testing
@testable import RouterCore

/// W10's protocol, proven where it actually has to hold: **between processes**, on a real
/// filesystem, with real `flock`.
///
/// A single-process test cannot see any of this. The failure this guards against is one process
/// writing a stale object over another process's write, and every one of the mechanisms that stops
/// it — the sidecar inode, the kernel releasing a lock on exit, the descriptor not leaking to a
/// child — is an OS behaviour rather than a Swift one.
@Suite("Config mutation lock", .serialized)
struct ConfigMutationLockTests {
    private func scratch() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mcp-router-lock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Runs a helper `swift` process that takes the lock and holds it, so the exclusion under test
    /// is genuinely cross-process. Returns the process, already started.
    private func holder(
        lockPath: String, holdSeconds: Double, ready: URL
    ) throws -> Process {
        let source = """
        import Foundation
        let fd = open("\(lockPath)", O_CREAT | O_RDWR, 0o600)
        guard fd >= 0, flock(fd, LOCK_EX) == 0 else { exit(2) }
        FileManager.default.createFile(atPath: "\(ready.path)", contents: Data("1".utf8))
        Thread.sleep(forTimeInterval: \(holdSeconds))
        exit(0)
        """
        let file = ready.deletingLastPathComponent().appendingPathComponent("holder.swift")
        try source.write(to: file, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    @Test("L1 — two lock holders never overlap")
    func lockSerialises() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("servers.json").path

        // Real threads rather than tasks. `withExclusiveLock` blocks the thread it runs on while it
        // waits, so eight tasks on the cooperative pool would be competing for pool threads as well
        // as for the lock — measuring the executor, not the lock.
        //
        // A counter rather than a sleep: overlap is what is being detected, so the assertion has to
        // be about simultaneity, not about duration.
        let inside = Counter()
        let done = DispatchGroup()
        for _ in 0 ..< 8 {
            done.enter()
            Thread.detachNewThread {
                defer { done.leave() }
                try? ConfigMutationLock.withExclusiveLock(forConfigAt: config, timeoutMs: 20000) {
                    inside.enter()
                    usleep(3000)
                    inside.leave()
                }
            }
        }
        #expect(done.wait(timeout: .now() + 60) == .success)
        #expect(inside.maximumConcurrent == 1, "the lock admitted two holders at once")
        // Concurrent callers in one process must WAIT, not be rejected as re-entrant: the daemon
        // can have two control handlers PATCHing at once, and failing one of them would be the
        // lock breaking the thing it protects.
        #expect(inside.entries == 8, "a concurrent same-process caller was refused, not queued")
    }

    @Test("L2/X4 — a held lock fails the second acquire inside the bound")
    func boundedWait() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("servers.json").path
        let ready = directory.appendingPathComponent("ready")

        let process = try holder(
            lockPath: ConfigMutationLock.lockPath(forConfigAt: config),
            holdSeconds: 6, ready: ready
        )
        defer { process.terminate() }
        #expect(
            WatchWorld.waitUntil(seconds: 60) {
                FileManager.default.fileExists(atPath: ready.path)
            },
            "the helper never took the lock"
        )

        let started = Date()
        var thrown: Error?
        do {
            try ConfigMutationLock.withExclusiveLock(forConfigAt: config, timeoutMs: 400) {}
        } catch {
            thrown = error
        }
        let elapsed = Date().timeIntervalSince(started)
        #expect(
            thrown as? ConfigMutationLock.LockProblem
                == .notAcquired(path: config, timeoutMs: 400)
        )
        // The bound is the claim. A wait that overruns it would block a launchd job.
        #expect(elapsed < 3, "waited \(elapsed)s against a 400ms bound")
    }

    @Test("L3 — MUTATION: locking servers.json itself excludes nothing across a rename")
    func lockingTheConfigItselfIsNotALock() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("servers.json").path
        FileManager.default.createFile(atPath: config, contents: Data("{}".utf8))

        // The red case, written out rather than described: a lock taken on the config's own inode.
        let first = open(config, O_RDWR)
        #expect(first >= 0)
        #expect(flock(first, LOCK_EX | LOCK_NB) == 0)

        // A writer commits by rename, which puts a NEW inode at that path.
        let temporary = "\(config).tmp"
        FileManager.default.createFile(atPath: temporary, contents: Data("{\"a\":1}".utf8))
        #expect(rename(temporary, config) == 0)

        // A second writer opening the path now gets the new inode — and takes the "exclusive" lock
        // while the first still holds its own. Two writers, no exclusion.
        let second = open(config, O_RDWR)
        #expect(second >= 0)
        #expect(
            flock(second, LOCK_EX | LOCK_NB) == 0,
            "if this fails the premise is wrong and the sidecar is unnecessary"
        )
        close(first)
        close(second)

        // Green: the sidecar is never renamed, so the same sequence excludes correctly.
        let sidecar = ConfigMutationLock.lockPath(forConfigAt: config)
        let holdOne = open(sidecar, O_CREAT | O_RDWR, 0o600)
        #expect(flock(holdOne, LOCK_EX | LOCK_NB) == 0)
        let temporaryTwo = "\(config).tmp2"
        FileManager.default.createFile(atPath: temporaryTwo, contents: Data("{\"b\":2}".utf8))
        #expect(rename(temporaryTwo, config) == 0)
        let holdTwo = open(sidecar, O_CREAT | O_RDWR, 0o600)
        #expect(
            flock(holdTwo, LOCK_EX | LOCK_NB) != 0,
            "the sidecar must still exclude after the config has been replaced"
        )
        close(holdOne)
        close(holdTwo)
    }

    @Test("L4/X4 — a killed holder does not block the next acquire")
    func killedHolderReleases() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("servers.json").path
        let ready = directory.appendingPathComponent("ready")

        let process = try holder(
            lockPath: ConfigMutationLock.lockPath(forConfigAt: config),
            holdSeconds: 120, ready: ready
        )
        #expect(
            WatchWorld.waitUntil(seconds: 60) {
                FileManager.default.fileExists(atPath: ready.path)
            },
            "the helper never took the lock"
        )
        // SIGKILL: no unwinding, no `defer`, nothing but the kernel closing the descriptor.
        kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()

        var acquired = false
        try ConfigMutationLock.withExclusiveLock(forConfigAt: config, timeoutMs: 5000) {
            acquired = true
        }
        #expect(acquired, "a lock file left by a killed process must not deadlock the next run")
    }

    @Test("L6/X2b — a nested acquire throws at once instead of stalling")
    func reentrantAcquireThrows() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("servers.json").path

        let started = Date()
        var inner: Error?
        try ConfigMutationLock.withExclusiveLock(forConfigAt: config, timeoutMs: 8000) {
            do {
                try ConfigMutationLock.withExclusiveLock(forConfigAt: config, timeoutMs: 8000) {}
            } catch {
                inner = error
            }
        }
        let elapsed = Date().timeIntervalSince(started)
        #expect(inner as? ConfigMutationLock.LockProblem == .reentrant(path: config))
        // The elapsed assertion is the point: without the guard this would spin the full 8s and
        // then report that *another process* holds the file, which is a false statement about a bug
        // in this one.
        #expect(elapsed < 2, "a nested acquire stalled for \(elapsed)s")
    }

    @Test("L5 — the lock changed nothing about what ConfigEdit.edit writes")
    func configEditIsUnchanged() throws {
        let directory = try scratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("servers.json").path
        try WatchWorld.write(
            """
            {
              "port": 8879,
              "startupTimeoutMs": 42,
              "mcpServers": {}
            }
            """,
            to: config
        )

        try ConfigEdit.edit(path: config, fileSystem: RealFileSystem()) { servers in
            servers.append(JSONMember(key: JSString("added"), value: .object([
                JSONMember(key: JSString("command"), value: .string(JSString("true")))
            ])))
        }

        let written = WatchWorld.read(config)
        #expect(written.contains("\"startupTimeoutMs\": 42"), "an unrelated key was dropped")
        #expect(!written.hasSuffix("\n"), "the control API's writer emits no trailing newline")
        #expect(WatchWorld.serverNames(in: config) == ["added"])

        // And the refusal still refuses.
        let flat = directory.appendingPathComponent("flat.json").path
        try WatchWorld.write(#"{"probe": {"command": "true"}}"#, to: flat)
        #expect(throws: ConfigEdit.Problem.unrecognisedShape(path: flat)) {
            try ConfigEdit.edit(path: flat, fileSystem: RealFileSystem()) { _ in }
        }
    }
}

/// Counts concurrent occupants of a critical section.
final class Counter: @unchecked Sendable {
    // Every field is read and written under `lock`, which is what makes the unchecked conformance
    // honest rather than a way past a diagnostic (SWIFT_PRACTICES §1).
    private let lock = NSLock()
    private var current = 0
    private var peak = 0
    private var total = 0

    func enter() {
        lock.lock()
        defer { lock.unlock() }
        current += 1
        total += 1
        peak = max(peak, current)
    }

    func leave() {
        lock.lock()
        defer { lock.unlock() }
        current -= 1
    }

    var maximumConcurrent: Int {
        lock.lock()
        defer { lock.unlock() }
        return peak
    }

    var entries: Int {
        lock.lock()
        defer { lock.unlock() }
        return total
    }
}
