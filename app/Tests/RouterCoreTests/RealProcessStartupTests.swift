import Foundation
import Testing
@testable import RouterCore

/// Startup failures against a **real child process** that never speaks: a command that exits, and
/// one killed by a signal. Split from `RealProcessTests` for length. The same rule holds here, and
/// a fake transport could show neither.
@Suite("Real child processes — startup", .serialized)
struct RealProcessStartupTests {
    /// A command that exists, runs, and exits before it can speak. Before the fix this waited out the
    /// whole startup budget and reported a timeout; the budget here is 5 s, so a bound of 2 s can only
    /// be met by noticing the exit.
    @Test("E0/P11 — a child that exits before initializing fails at once, naming its status")
    func childThatExitsBeforeInitializingFailsAtOnce() async throws {
        let message = try await openAndReadFailure(
            shell: "exit 17", name: "dies", budgetMilliseconds: 30000, maximumSeconds: 10
        )
        #expect(message == "upstream \"dies\" exited with status 17 before initializing")
    }

    @Test("E0/P11a — a child killed by a signal before initializing names the signal")
    func childKilledBeforeInitializingNamesTheSignal() async throws {
        let message = try await openAndReadFailure(
            shell: "kill -9 $$", name: "killed", budgetMilliseconds: 30000, maximumSeconds: 10
        )
        #expect(message == "upstream \"killed\" exited on signal 9 before initializing")
    }

    @Test("E0/P11b — a write to a child that has closed its stdin is an error, not a signal")
    func writeAfterChildClosesStdinIsAnErrorNotASignal() {
        // The router's own write end, with the read end gone as it is once a child has exited. Without
        // the descriptor-level setting this write raises SIGPIPE, which ends the test process — the
        // same signal that would end the router when a child dies during its handshake.
        let pipes = ChildPipes()
        try? pipes.input.fileHandleForReading.close()
        var byte: UInt8 = 0x78
        let written = write(pipes.input.fileHandleForWriting.fileDescriptor, &byte, 1)
        let failure = errno
        #expect(written == -1)
        #expect(failure == EPIPE)
    }

    /// Opens a `/bin/sh -c` upstream expected to fail, and returns the failure's wire text. Fails the
    /// test if the open succeeds, or if it took longer than `maximumSeconds`.
    private func openAndReadFailure(
        shell script: String,
        name: String,
        budgetMilliseconds: Int,
        maximumSeconds: Int
    ) async throws -> String? {
        let config = UpstreamConfig(
            name: name,
            transport: .stdio,
            raw: .object([]),
            idleMs: nil,
            startupTimeoutMs: nil,
            projects: nil,
            warm: nil,
            placard: nil,
            command: "/bin/sh",
            args: ["-c", script],
            env: [],
            cwd: nil,
            url: nil,
            headers: [],
            oauth: nil
        )
        let started = ContinuousClock.now
        var message: String?
        do {
            _ = try await StdioUpstreamTransport().open(config, timeoutMilliseconds: budgetMilliseconds)
            Issue.record("a child that ran \(script) must not open as an upstream")
        } catch let error as PoolError {
            message = error.message
        }
        let elapsed = started.duration(to: .now)
        #expect(
            elapsed < .seconds(maximumSeconds),
            "the failure took \(elapsed); the child had already exited"
        )
        return message
    }
}
