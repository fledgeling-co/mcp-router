import Foundation
import Testing
@testable import RouterCore

/// The cross-process half of the three `manifest.json` writers — R19.
///
/// `servers.json` has had ``ConfigMutationLock`` since R2-W and `manifest.json` had nothing, so a
/// row written between another path's read and its save was erased with no delete statement
/// anywhere in the code path. Each test here drives one of the three writers with the lock **held
/// by a second process**, which is what makes the exclusion real rather than simulated — the seam
/// `ConfigMutationLockTests` and `ImportConfigWriterLockTests` already draw for the config file.
///
/// Every one of them is a W11: not "the lock is taken" but "the READ is inside it". The distinction
/// is the whole item. A writer that locks only its save still clobbers, because the object it saves
/// was read before the other process wrote.
///
/// `.serialized`, because each test parks a real thread on a real lock and the pool is finite.
@Suite("The manifest mutation lock", .serialized)
struct ManifestMutationLockTests {
    // MARK: - the fixture

    private func scratch() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mcp-router-manifestlock-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Holds the lock in a **separate process**, then plants `markerFile` over the manifest once
    /// told to go.
    ///
    /// Lifted from `ImportConfigWriterLockTests.holder` rather than shared with it: that one writes
    /// its helper source into its own scratch directory and is private to its suite, and a shared
    /// version would have to take both suites' paths as parameters to earn its keep. The rules that
    /// matter are copied with it — the marker travels as a path and is never interpolated into the
    /// helper's source, and every wait below is bounded, because a helper that fails to compile
    /// otherwise hangs the suite rather than failing one test.
    private func holder(
        lockPath: String, manifestPath: String, ready: URL, go: URL, markerFile: URL
    ) throws -> Process {
        let source = """
        import Foundation
        let fd = open("\(lockPath)", O_CREAT | O_RDWR, 0o600)
        guard fd >= 0, flock(fd, LOCK_EX) == 0 else { exit(2) }
        FileManager.default.createFile(atPath: "\(ready.path)", contents: Data("1".utf8))
        while !FileManager.default.fileExists(atPath: "\(go.path)") {
            Thread.sleep(forTimeInterval: 0.01)
        }
        try? FileManager.default.removeItem(atPath: "\(manifestPath)")
        try? FileManager.default.copyItem(atPath: "\(markerFile.path)", toPath: "\(manifestPath)")
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

    private func waitForReady(_ ready: URL, _ process: Process) -> Bool {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: ready.path) { return true }
            if !process.isRunning { return false }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    /// One entry, spelled the way `manifest.json` spells one.
    private func manifestText(_ entries: [String]) -> String {
        "{\"version\": 1,\"servers\": {\(entries.joined(separator: ","))}}"
    }

    private func rows(at path: String) throws -> [String] {
        let manifest = ManifestIO.load(path: path, fileSystem: RealFileSystem()).manifest
        return manifest.serverEntries.map(\.name.string).sorted()
    }

    /// The whole arrangement, minus which writer runs and what it should have written.
    ///
    /// `run` is started while the holder still has the lock, so a writer that reads outside it reads
    /// the PRE-plant bytes. `readSignal` is what makes that observable rather than assumed: a
    /// read-outside-lock writer signals within milliseconds, and a correct one cannot signal until
    /// it holds the lock — so the wait below expiring is the *expected* path, never the red.
    private func withHeldLock(
        seed: String,
        planted: String,
        run: @escaping @Sendable (String, ImportWriterProbeFileSystem) -> Void
    ) throws -> String {
        let root = try scratch()
        let path = root.appendingPathComponent("manifest.json").path
        try seed.write(toFile: path, atomically: true, encoding: .utf8)

        let ready = root.appendingPathComponent("ready")
        let go = root.appendingPathComponent("go")
        let marker = root.appendingPathComponent("planted.json")
        try planted.write(to: marker, atomically: true, encoding: .utf8)

        let process = try holder(
            lockPath: ConfigMutationLock.lockPath(forConfigAt: path),
            manifestPath: path, ready: ready, go: go, markerFile: marker
        )
        defer {
            FileManager.default.createFile(atPath: go.path, contents: Data("1".utf8))
            process.waitUntilExit()
        }
        guard waitForReady(ready, process) else {
            Issue.record("the lock holder never took the lock")
            return path
        }

        let probe = ImportWriterProbeFileSystem(signalOnReadOf: path)
        let started = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            started.signal()
            run(path, probe)
            finished.signal()
        }
        started.wait()
        _ = probe.readSignal.wait(timeout: .now() + 3)

        FileManager.default.createFile(atPath: go.path, contents: Data("1".utf8))
        #expect(finished.wait(timeout: .now() + 60) == .success, "the writer never finished")
        return path
    }

    // MARK: - the three writers

    @Test("W11/approve — the promoted surface is the one the other process just wrote")
    func approveReadsInsideTheLock() throws {
        // The seeded and planted pending surfaces differ, so "which bytes did approve promote" is
        // answerable from the result rather than only from which rows survive.
        let seeded = manifestText([
            #""kept":{"tools":[],"digest":"d0","builtAt":"t0","#
                + #""pending":{"tools":[{"name":"stale"}],"digest":"d1","seenAt":"s0"}}"#
        ])
        let planted = manifestText([
            #""kept":{"tools":[],"digest":"d0","builtAt":"t0","#
                + #""pending":{"tools":[{"name":"a"},{"name":"b"}],"digest":"d2","seenAt":"s1"}}"#,
            #""planted":{"tools":[],"digest":"dp","builtAt":"tp"}"#
        ])
        nonisolated(unsafe) var status = 0
        nonisolated(unsafe) var body = ""
        let path = try withHeldLock(seed: seeded, planted: planted) { path, probe in
            // `approve` is async only for its log line; the semaphore parks THIS detached thread,
            // never a cooperative one, because the Task it waits on does no blocking work of its
            // own once the synchronous body has returned.
            let done = DispatchSemaphore(value: 0)
            Task {
                let answer = await AuthRoutes.approve(
                    server: JSString("kept"), manifestPath: path,
                    fileSystem: probe, nowMilliseconds: 1_700_000_000_000,
                    // Longer than the daemon's own 2000 ms default, which the holder outlasts here
                    // by design: this test is about WHERE the read happens, and the timeout is
                    // `aHeldLockRefusesTheWrite`'s subject rather than this one's.
                    lockTimeoutMs: 60000
                )
                status = answer.status
                body = JSStringify.compact(answer.body)
                done.signal()
            }
            done.wait()
        }

        #expect(status == 200)
        #expect(body == #"{"server":"kept","approved":2}"#, "the PLANTED pending surface, not the seeded one")
        #expect(try rows(at: path) == ["kept", "planted"], "the other process's row survived the promotion")
        let promoted = ManifestIO.load(path: path, fileSystem: RealFileSystem())
            .manifest.entry(named: "kept")
        #expect(promoted?.tools.map { $0.name?.string } == ["a", "b"])
        #expect(promoted?.pending == nil)
    }

    @Test("W11/index — a re-indexed row merges into the manifest the other process just wrote")
    func manifestIndexerReadsInsideTheLock() throws {
        let planted = manifestText([#""planted":{"tools":[],"digest":"dp","builtAt":"tp"}"#])
        nonisolated(unsafe) var cached = false
        let path = try withHeldLock(seed: manifestText([]), planted: planted) { path, probe in
            let done = DispatchSemaphore(value: 0)
            Task {
                let outcome = await ManifestIndexer(
                    startupTimeoutMs: 2000,
                    transporting: LockTestListingTransport(),
                    manifestPath: path,
                    fileSystem: probe,
                    lockTimeoutMs: 60000
                ).index(stdioUpstream("fixture"))
                cached = outcome.cached
                done.signal()
            }
            done.wait()
        }

        #expect(cached, "the row reached disk")
        #expect(try rows(at: path) == ["fixture", "planted"])
    }

    @Test("W11/watch — an adopted row merges into the manifest the other process just wrote")
    func watchIndexerReadsInsideTheLock() throws {
        let planted = manifestText([#""planted":{"tools":[],"digest":"dp","builtAt":"tp"}"#])
        nonisolated(unsafe) var built: [String] = []
        let path = try withHeldLock(seed: manifestText([]), planted: planted) { path, probe in
            let done = DispatchSemaphore(value: 0)
            Task {
                let report = await WatchIndexer(
                    manifestPath: path,
                    startupTimeoutMs: 2000,
                    transporting: LockTestListingTransport(),
                    fileSystem: probe,
                    lockTimeoutMs: 60000
                ).index([stdioUpstream("fixture")])
                built = report.built
                done.signal()
            }
            done.wait()
        }

        #expect(built == ["fixture (1 tools)"])
        #expect(try rows(at: path) == ["fixture", "planted"])
    }
}

/// An upstream that answers `tools/list` with one tool and nothing else.
///
/// A second copy of `ManifestIndexerWriteFailureTests`'s private one, because that suite's is
/// private to it and both this file and that one would have to change together if it moved. One
/// tool, named, because the bookkeeping compares a DIGEST of the surface.
private struct LockTestListingTransport: UpstreamTransporting, Sendable {
    func open(
        _ upstream: UpstreamConfig, timeoutMilliseconds: Int
    ) async throws -> any UpstreamSession {
        LockTestListingSession()
    }
}

private final class LockTestListingSession: UpstreamSession, @unchecked Sendable {
    let processIdentifier: Int32? = 4242

    func waitUntilEnded() async {
        try? await Task.sleep(nanoseconds: 60_000_000_000)
    }

    func shutdown() async {}

    func listTools() async throws -> JSONValue {
        .object([
            JSONMember(key: "tools", value: .array([
                .object([
                    JSONMember(key: "name", value: .string(JSString("echo"))),
                    JSONMember(key: "description", value: .string("returns its argument"))
                ])
            ]))
        ])
    }

    func callTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        .object([])
    }
}
