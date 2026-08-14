import Foundation
import MCP
import Synchronization

/// One live stdio upstream: a child process, its pipes, and the SDK client speaking to it.
///
/// Its own file, split from `StdioUpstreamTransport.swift` along the seam that matters here:
/// **opening** an upstream and **being** one are different jobs with different failure modes. The
/// transport's mistakes happen once, at spawn time, and are reported by throwing; this type's happen
/// at any point over a session's whole life, and are answered by shutting down cleanly whatever the
/// child does. Keeping them apart is what makes the shutdown ordering below readable as a unit.
final class StdioUpstreamSession: UpstreamSession, Sendable {
    let processIdentifier: Int32?
    private let name: String
    private let process: Process
    private let pipes: ChildPipes
    private let client: Client
    private let transport: any Transport
    private let tap: ResponseTap
    private let ending: EndSignal
    private let terminationGraceNanoseconds: UInt64
    private let didShutdown = Mutex(false)

    init(
        name: String,
        process: Process,
        pipes: ChildPipes,
        client: Client,
        transport: any Transport,
        tap: ResponseTap,
        ending: EndSignal,
        terminationGraceNanoseconds: UInt64
    ) {
        self.name = name
        self.process = process
        self.pipes = pipes
        self.client = client
        self.transport = transport
        self.tap = tap
        self.ending = ending
        self.terminationGraceNanoseconds = terminationGraceNanoseconds
        processIdentifier = process.processIdentifier
    }

    func waitUntilEnded() async {
        await ending.wait()
    }

    /// `tools/list` and `tools/call`, answered with the upstream's own bytes.
    ///
    /// Both go through the SDK's request machinery — which owns framing, correlation and timeouts —
    /// and then read the response out of the tap rather than from the SDK's decoded value, because
    /// that value has already lost member order. See `UpstreamCalling.swift`.
    func listTools() async throws -> JSONValue {
        try await RawRequest.perform(
            RawListTools.self, client: client, tap: tap, parameters: .object([])
        )
    }

    func callTool(name: String, arguments: JSONValue) async throws -> JSONValue {
        try await RawRequest.perform(
            RawCallTool.self, client: client, tap: tap,
            parameters: .object([
                JSONMember(key: JSString("name"), value: .string(JSString(name))),
                JSONMember(key: JSString("arguments"), value: arguments)
            ])
        )
    }

    /// Close everything this session owns, once.
    ///
    /// The order is the point. Disconnecting first stops the SDK's receive loop reading a
    /// descriptor that is about to close; SIGTERM then gives the child its documented chance to
    /// exit; SIGKILL is what stops a wedged server from holding the router's shutdown open forever;
    /// and the descriptors close last, when nothing is left that could still be reading them.
    func shutdown() async {
        let alreadyDone = didShutdown.withLock { value -> Bool in
            defer { value = true }
            return value
        }
        guard !alreadyDone else { return }

        await client.disconnect()
        if process.isRunning {
            process.terminate()
            await waitForExit()
        }
        pipes.closeAll()
    }

    /// Wait for the child to exit, then kill it if it will not.
    ///
    /// Polled rather than raced against a timer in a task group, for the same reason the handshake
    /// is: a group waits for every child task, so a branch parked on "the process ended" cannot be
    /// abandoned when the process never does — which is precisely the stubborn server this escalation
    /// exists for. `waitUntilExit()` is unusable here too, being a blocking call.
    ///
    /// Both waits are bounded. A shutdown that cannot finish still finishes.
    private func waitForExit() async {
        if await !poll(untilExitedWithin: terminationGraceNanoseconds), process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            _ = await poll(untilExitedWithin: 2_000_000_000)
        }
    }

    private func poll(untilExitedWithin nanoseconds: UInt64) async -> Bool {
        let bounded = Int64(min(nanoseconds, UInt64(Int64.max)))
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(bounded))
        while ContinuousClock.now < deadline {
            if !process.isRunning { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return !process.isRunning
    }
}
