import Foundation
import Testing
@testable import RouterCore

/// The cross-process half of the import writer: that it takes the config mutation lock at all, and
/// that its **read** happens inside it.
///
/// Split from ``ImportConfigWriterTests`` because these two need a second PROCESS holding a real
/// `flock`, which is an OS behaviour a same-process double would simulate rather than exhibit —
/// the seam ``ConfigMutationLockTests`` already draws for the same reason.
@Suite("Import config writer — the lock", .serialized)
struct ImportConfigWriterLockTests {
    private func scratch() throws -> URL {
        try ImportWriterFixtures.scratch()
    }

    /// Holds the lock in a **separate process**, so the exclusion is real rather than simulated,
    /// and — when `markerFile` is given — copies that file over the config once told to go.
    ///
    /// The marker travels as a **path**, never interpolated into the helper's source. The first
    /// version of this helper pasted a JSON literal into a Swift string and the unescaped quotes
    /// made the helper fail to compile; `ready` was then never written and the wait below spun
    /// forever, hanging the whole suite rather than failing one test. Both halves of that are fixed:
    /// no interpolated payload, and every wait is bounded.
    private func holder(
        lockPath: String, configPath: String, ready: URL, go: URL, markerFile: URL? = nil
    ) throws -> Process {
        let plant = markerFile.map {
            """
            try? FileManager.default.removeItem(atPath: "\(configPath)")
            try? FileManager.default.copyItem(atPath: "\($0.path)", toPath: "\(configPath)")
            """
        } ?? ""
        let source = """
        import Foundation
        let fd = open("\(lockPath)", O_CREAT | O_RDWR, 0o600)
        guard fd >= 0, flock(fd, LOCK_EX) == 0 else { exit(2) }
        FileManager.default.createFile(atPath: "\(ready.path)", contents: Data("1".utf8))
        while !FileManager.default.fileExists(atPath: "\(go.path)") {
            Thread.sleep(forTimeInterval: 0.01)
        }
        \(plant)
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

    /// Bounded, because an unbounded wait on a helper that failed to start is a hung suite rather
    /// than a failed test — measured, not theorised.
    private func waitForReady(_ ready: URL, _ process: Process) -> Bool {
        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: ready.path) { return true }
            if !process.isRunning { return false }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }

    @Test("W10 — a lock held elsewhere refuses the write rather than proceeding")
    func aHeldLockRefusesTheWrite() throws {
        let root = try scratch()
        let path = root.appendingPathComponent("servers.json").path
        let preImage = #"{"mcpServers":{"kept":{}}}"#
        try preImage.write(toFile: path, atomically: true, encoding: .utf8)
        let ready = root.appendingPathComponent("ready")
        let go = root.appendingPathComponent("go")
        let process = try holder(
            lockPath: ConfigMutationLock.lockPath(forConfigAt: path),
            configPath: path, ready: ready, go: go
        )
        defer {
            FileManager.default.createFile(atPath: go.path, contents: Data("1".utf8))
            process.waitUntilExit()
        }
        guard waitForReady(ready, process) else {
            Issue.record("the lock holder never took the lock"); return
        }

        #expect(throws: ConfigMutationLock.LockProblem.self) {
            try ImportWriterFixtures.write(to: path, lockTimeoutMs: 300)
        }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == preImage)
    }

    /// The one that distinguishes read-inside-lock from read-outside-lock.
    ///
    /// The obvious version — hold the lock, plant a key, release, then assert the writer saw it —
    /// passes for **both** implementations, because a writer that reads outside the lock and starts
    /// after the plant also sees it. The distinguishing order is: the writer must already be
    /// **waiting on the lock** when the key is planted.
    ///
    /// The probe's `readSignal` is what makes that observable rather than assumed. A writer that
    /// reads outside the lock signals it within milliseconds; one that reads inside cannot signal
    /// until it has the lock, so the wait below expires — and the expiry is the *expected* path for
    /// a correct implementation, never the one that produces the red.
    @Test("W11 — the read happens inside the lock, so a concurrent write is not clobbered")
    func theReadHappensInsideTheLock() throws {
        let root = try scratch()
        let path = root.appendingPathComponent("servers.json").path
        try #"{"mcpServers":{}}"#.write(toFile: path, atomically: true, encoding: .utf8)
        let ready = root.appendingPathComponent("ready")
        let go = root.appendingPathComponent("go")
        let marker = root.appendingPathComponent("marker.json")
        try #"{"plantedByAnotherProcess":true,"mcpServers":{}}"#
            .write(to: marker, atomically: true, encoding: .utf8)

        let process = try holder(
            lockPath: ConfigMutationLock.lockPath(forConfigAt: path),
            configPath: path, ready: ready, go: go, markerFile: marker
        )
        defer { process.waitUntilExit() }
        guard waitForReady(ready, process) else {
            Issue.record("the lock holder never took the lock"); return
        }

        let probe = ImportWriterProbeFileSystem(failMoveItem: false, signalOnReadOf: path)
        let started = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        // The write's own error is captured, not swallowed. `try?` here would let a writer that
        // takes the lock and then throws leave the holder's plant on disk and pass this test on
        // somebody else's bytes.
        nonisolated(unsafe) var writeError: (any Error)?
        Thread.detachNewThread {
            started.signal()
            do {
                try ImportConfigWriter.write(
                    adopted: ImportWriterFixtures.alpha,
                    port: RouterHome.defaultPort,
                    to: .init(path: path, processIdentifier: 4243, lockTimeoutMs: 60000),
                    fileSystem: probe
                )
            } catch {
                writeError = error
            }
            finished.signal()
        }
        started.wait()
        // Reached to expiry only by a correct implementation; a read-outside-lock writer signals
        // this promptly, and that is the interleaving that produces the failure.
        _ = probe.readSignal.wait(timeout: .now() + 3)

        FileManager.default.createFile(atPath: go.path, contents: Data("1".utf8))
        #expect(finished.wait(timeout: .now() + 60) == .success)

        #expect(writeError == nil)
        let text = try String(contentsOfFile: path, encoding: .utf8)
        // The holder's key — only reachable if the read happened after the lock was acquired.
        #expect(text.contains("plantedByAnotherProcess"))
        // And the writer's OWN bytes, so "the plant survived" cannot stand in for "the writer ran".
        #expect(text.contains("\"alpha\""))
        #expect(text.contains("\"port\": 8879"))
    }
}
