import Foundation
import Testing
@testable import RouterCore

/// A real MCP server, in the smallest form that is still real: a separate process, its own pipes,
/// newline-delimited JSON-RPC on stdout, and an `initialize` reply the pinned SDK accepts.
///
/// The spec's E0 clause exists because of what a double cannot tell you. A fake session proves the
/// pool's state machine and nothing about descriptors, signals, PATH resolution, pipe buffers or
/// process reaping — and every one of those is somewhere this port can differ from the reference
/// while every unit test stays green.
enum StubServer {
    /// Modes the stub can run in, each standing for a way a real server misbehaves.
    enum Mode: String {
        /// Answers `initialize` and then sits there. The well-behaved case.
        case responsive
        /// Never answers anything. Stands for a server that hangs during startup.
        case silent
        /// Answers, then exits when a trigger file appears — a server that dies under us.
        case exitsOnTrigger = "exits-on-trigger"
        /// Answers, and ignores SIGTERM. Stands for a server that will not shut down politely.
        case stubborn
        /// Writes far more than a pipe buffer to stderr before answering, so a router that does not
        /// drain stderr deadlocks here rather than in production.
        case chatty
    }

    private static let source = """
    import json, os, signal, sys, threading, time

    mode = sys.argv[1]
    pid_path = sys.argv[2]
    trigger = sys.argv[3] if len(sys.argv) > 3 else ""

    with open(pid_path, "w") as handle:
        handle.write(str(os.getpid()))

    if mode == "stubborn":
        signal.signal(signal.SIGTERM, signal.SIG_IGN)

    if mode == "chatty":
        # Comfortably past a 64 KiB pipe buffer: an undrained stderr blocks the write below, and the
        # handshake that follows it never happens.
        sys.stderr.write("noise " * 50000)
        sys.stderr.flush()

    if mode == "exits-on-trigger" and trigger:
        def watch():
            while not os.path.exists(trigger):
                time.sleep(0.02)
            os._exit(0)
        threading.Thread(target=watch, daemon=True).start()

    while True:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        message = json.loads(line)
        if mode == "silent":
            continue
        if message.get("method") == "initialize":
            reply = {
                "jsonrpc": "2.0",
                "id": message["id"],
                "result": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": "stub", "version": "1.0.0"},
                },
            }
            sys.stdout.write(json.dumps(reply) + "\\n")
            sys.stdout.flush()
    """

    /// Materialise the script and return a config that runs it.
    ///
    /// Launched as `python3 <script>` with no directory in the command, so the transport's PATH
    /// resolution is exercised rather than assumed — a config full of bare `npx` commands is the
    /// normal case, not the exotic one.
    static func config(
        name: String,
        mode: Mode,
        directory: URL,
        trigger: URL? = nil,
        idleMs: Int? = nil,
        startupTimeoutMs: Int? = nil
    ) throws -> UpstreamConfig {
        let script = directory.appendingPathComponent("stub-server.py")
        if !FileManager.default.fileExists(atPath: script.path) {
            try source.write(to: script, atomically: true, encoding: .utf8)
        }
        var arguments = [script.path, mode.rawValue, pidFile(name: name, directory: directory).path]
        if let trigger { arguments.append(trigger.path) }
        return UpstreamConfig(
            name: name,
            transport: .stdio,
            raw: .object([]),
            idleMs: idleMs,
            startupTimeoutMs: startupTimeoutMs,
            projects: nil,
            warm: nil,
            placard: nil,
            command: "python3",
            args: arguments,
            env: [],
            cwd: nil,
            url: nil,
            headers: [],
            oauth: nil
        )
    }

    static func pidFile(name: String, directory: URL) -> URL {
        directory.appendingPathComponent("\(name).pid")
    }

    /// The child's own view of its pid, read from the file it writes at startup.
    ///
    /// Needed because a *failed* open returns no session to ask, and "the timeout left no orphan"
    /// is precisely a claim about a process whose handle we never received.
    static func reportedPid(
        name: String,
        directory: URL,
        waitingUpTo seconds: Double = 3
    ) async -> Int32? {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if let pid = reportedPidSync(name: name, directory: directory) { return pid }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return nil
    }

    /// The pid the child recorded, read without waiting.
    static func reportedPidSync(name: String, directory: URL) -> Int32? {
        let path = pidFile(name: name, directory: directory)
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return nil }
        return Int32(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Whether a pid is still a live process this session can signal.
    ///
    /// `kill(pid, 0)` performs the permission and existence check without delivering a signal. It is
    /// the only honest way to ask; a `Process` object reports what it last observed, which is not
    /// the same question.
    static func isAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0
    }

    static func waitUntilGone(_ pid: Int32, seconds: Double = 5) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
        while ContinuousClock.now < deadline {
            if !isAlive(pid) { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return !isAlive(pid)
    }

    /// A directory that is removed when the test ends.
    static func makeDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mcp-router-stub-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
