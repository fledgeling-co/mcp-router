import Foundation
import MCP
import Synchronization
import System

/// Opens a stdio upstream for real: a child process, its pipes wired to the pinned SDK's
/// `StdioTransport`, and an MCP handshake completed inside the startup budget.
///
/// Divergence D1 is why this file exists. The Swift SDK spawns nothing — `StdioTransport` takes two
/// file descriptors and assumes something else owns whatever is on the other end of them, where the
/// TypeScript SDK's `StdioClientTransport` spawns the child itself. Everything between "a command
/// line in `~/.claude.json`" and "a descriptor pair" is therefore ours, including the parts that are
/// easy to forget: draining stderr, honouring `cwd`, and killing a child that ignores SIGTERM.
public struct StdioUpstreamTransport: UpstreamTransporting {
    private let log: RouterLog?
    private let clientName: String
    private let clientVersion: String
    /// How long a child gets to exit on SIGTERM before it is killed. A daemon under launchd cannot
    /// wait indefinitely for a wedged server, and a child that outlives the router is an orphan.
    private let terminationGraceNanoseconds: UInt64

    public init(
        log: RouterLog? = nil,
        clientName: String = "mcp-router",
        clientVersion: String = "0.1.0",
        terminationGraceNanoseconds: UInt64 = 2_000_000_000
    ) {
        self.log = log
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.terminationGraceNanoseconds = terminationGraceNanoseconds
    }

    public func open(
        _ upstream: UpstreamConfig,
        timeoutMilliseconds: Int
    ) async throws -> any UpstreamSession {
        guard upstream.isStdio else {
            throw PoolError.spawnFailed(name: upstream.name, reason: "not a stdio upstream")
        }
        guard let command = upstream.command, !command.isEmpty else {
            throw PoolError.spawnFailed(name: upstream.name, reason: "no command configured")
        }

        // Resolved before anything is spawned, so a command that does not exist fails **now** with
        // the reference's own message rather than sixty seconds later with a timeout.
        //
        // The cause is `/usr/bin/env`, which the spawn below uses on purpose to keep the PATH
        // semantics the reference has. `env` itself always exists, so `Process.run()` succeeds, the
        // child then exits immediately, and the handshake sits there until the startup budget runs
        // out. Measured: `mcp-router import` reported `upstream "broken" did not initialize within
        // 60000ms` where the reference reported `spawn /nonexistent/... ENOENT` in milliseconds.
        guard Self.resolve(command) != nil else {
            throw PoolError.spawnFailed(name: upstream.name, reason: "spawn \(command) ENOENT")
        }

        let pipes = ChildPipes()
        let process = Process()
        // `/usr/bin/env` rather than the command as an executable path: the reference spawns through
        // a PATH search, so a config saying `npx` has to keep working. Setting `executableURL` to a
        // bare name instead would fail for every upstream that is not an absolute path.
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + upstream.args
        process.environment = mergedEnvironment(upstream)
        if let cwd = upstream.cwd, !cwd.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }
        process.standardInput = pipes.input
        process.standardOutput = pipes.output
        process.standardError = pipes.error

        let ending = EndSignal()
        process.terminationHandler = { _ in ending.fire() }

        do {
            try process.run()
        } catch {
            pipes.closeAll()
            throw PoolError.spawnFailed(name: upstream.name, reason: "\(error)")
        }

        drainStandardError(of: pipes, named: upstream.name)

        // Wrapped in a `TappingTransport` so the raw bytes of every response survive the SDK's
        // decode. `MCP.Value`'s object case is an unordered dictionary, so a `tools/call` result
        // read back through the SDK has already lost the member order the relay has to reproduce.
        let tap = ResponseTap()
        let transport = TappingTransport(
            wrapping: StdioTransport(
                input: FileDescriptor(rawValue: pipes.output.fileHandleForReading.fileDescriptor),
                output: FileDescriptor(rawValue: pipes.input.fileHandleForWriting.fileDescriptor)
            ),
            tap: tap
        )
        let client = Client(name: clientName, version: clientVersion)
        let session = StdioUpstreamSession(
            name: upstream.name,
            process: process,
            pipes: pipes,
            client: client,
            transport: transport,
            tap: tap,
            ending: ending,
            terminationGraceNanoseconds: terminationGraceNanoseconds
        )

        let outcome = await handshake(
            client: client,
            transport: transport,
            timeoutMilliseconds: timeoutMilliseconds
        )
        switch outcome {
        case .succeeded:
            return session
        case .timedOut:
            // A throwing open must leave nothing behind, so the half-open child is closed here
            // rather than left for a reaper that will never be told it exists.
            await session.shutdown()
            throw PoolError.startupTimeout(name: upstream.name, milliseconds: timeoutMilliseconds)
        case let .failed(reason):
            await session.shutdown()
            throw PoolError.spawnFailed(name: upstream.name, reason: reason)
        }
    }

    /// Where a command lands, if anywhere: an absolute or relative path as given, otherwise the
    /// first executable match on `PATH`. This is the lookup `/usr/bin/env` is about to perform, done
    /// early so its failure can be reported as the reference reports it.
    static func resolve(_ command: String, environment: [String: String]? = nil) -> String? {
        let fileManager = FileManager.default
        if command.contains("/") {
            return fileManager.isExecutableFile(atPath: command) ? command : nil
        }
        let path = (environment ?? ProcessInfo.processInfo.environment)["PATH"] ?? ""
        for directory in path.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = (String(directory) as NSString).appendingPathComponent(command)
            if fileManager.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }

    /// The router's own environment first, then the server's overrides — the reference's order, and
    /// it matters: a server that sets `PATH` must win over ours, not be silently ignored.
    private func mergedEnvironment(_ upstream: UpstreamConfig) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        for pair in upstream.env {
            environment[pair.key.string] = pair.value.string
        }
        return environment
    }

    /// Read the child's stderr continuously.
    ///
    /// Not optional housekeeping: a pipe nobody reads fills, and a server that writes a chatty
    /// startup banner then blocks forever on its own stderr looks exactly like a server that hangs
    /// during initialization. The reference drains it for the same reason.
    private func drainStandardError(of pipes: ChildPipes, named name: String) {
        let log = log
        pipes.error.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let text = String(bytes: data, encoding: .utf8)
            else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            Task { await log?.record(PoolLogEvent.childStderr(server: name, text: trimmed)) }
        }
    }

    enum Handshake {
        case succeeded
        case timedOut
        case failed(String)
    }

    /// Race the MCP handshake against the startup budget.
    ///
    /// `connect` performs `initialize` itself, so this one call is the whole handshake.
    ///
    /// Deliberately **not** a task group, and this cost a deadlock to learn: a group does not return
    /// until every child task has finished, so racing an uncancellable await against a timer inside
    /// one produces a race that can only be won by the branch you were trying to escape. A silent
    /// server leaves `connect` awaiting a reply that never comes, cancellation does not reach it,
    /// and the group waits forever — the exact hang the timeout exists to prevent.
    ///
    /// So the winner is published to a box and the loser is simply abandoned. Nothing awaits the
    /// stuck task; the teardown that follows a timeout kills the child and closes the descriptors,
    /// which is what actually unblocks it.
    private func handshake(
        client: Client,
        transport: any Transport,
        timeoutMilliseconds: Int
    ) async -> Handshake {
        let outcome = FirstOutcome()
        let connecting = Task {
            do {
                _ = try await client.connect(transport: transport)
                outcome.offer(.succeeded)
            } catch {
                outcome.offer(.failed("\(error)"))
            }
        }
        let timing = Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, timeoutMilliseconds)) * 1_000_000)
            outcome.offer(.timedOut)
        }

        let result = await outcome.wait()
        timing.cancel()
        if case .succeeded = result {} else { connecting.cancel() }
        return result
    }
}

/// The first of several racing answers, with the losers abandoned rather than awaited.
///
/// One writer wins; every later offer is dropped. `wait()` resumes exactly once.
final class FirstOutcome: Sendable {
    private struct State {
        var value: StdioUpstreamTransport.Handshake?
        var waiter: Waiter?
    }

    private let state = Mutex(State())

    typealias Waiter = CheckedContinuation<StdioUpstreamTransport.Handshake, Never>

    func offer(_ value: StdioUpstreamTransport.Handshake) {
        let waiter = state.withLock { current -> Waiter? in
            guard current.value == nil else { return nil }
            current.value = value
            defer { current.waiter = nil }
            return current.waiter
        }
        waiter?.resume(returning: value)
    }

    func wait() async -> StdioUpstreamTransport.Handshake {
        await withCheckedContinuation { (continuation: Waiter) in
            let ready = state.withLock { current -> StdioUpstreamTransport.Handshake? in
                if let value = current.value { return value }
                current.waiter = continuation
                return nil
            }
            if let ready { continuation.resume(returning: ready) }
        }
    }
}

/// The three pipes a child owns, closed exactly once.
final class ChildPipes: Sendable {
    let input = Pipe()
    let output = Pipe()
    let error = Pipe()
    private let closed = Mutex(false)

    func closeAll() {
        let alreadyClosed = closed.withLock { value -> Bool in
            defer { value = true }
            return value
        }
        guard !alreadyClosed else { return }
        error.fileHandleForReading.readabilityHandler = nil
        // `try?` throughout: the SDK's transport closes the two descriptors it was handed when it
        // disconnects, so a second close is expected and is not an error worth surfacing.
        for handle in [
            input.fileHandleForWriting, input.fileHandleForReading,
            output.fileHandleForReading, output.fileHandleForWriting,
            error.fileHandleForReading, error.fileHandleForWriting
        ] {
            try? handle.close()
        }
    }
}

/// A one-shot "the child exited" signal, awaited by any number of callers.
final class EndSignal: Sendable {
    private struct State {
        var fired = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    func fire() {
        let waiting = state.withLock { current -> [CheckedContinuation<Void, Never>] in
            current.fired = true
            let waiters = current.waiters
            current.waiters = []
            return waiters
        }
        for continuation in waiting {
            continuation.resume()
        }
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alreadyFired = state.withLock { current -> Bool in
                if current.fired { return true }
                current.waiters.append(continuation)
                return false
            }
            // Resumed outside the lock: resuming a continuation can run arbitrary code, and running
            // it while holding this mutex is how a deadlock gets built.
            if alreadyFired { continuation.resume() }
        }
    }
}

/// One live stdio upstream: a child process, its pipes, and the SDK client speaking to it.
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
