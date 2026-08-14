import Foundation
@testable import RouterCore

/// A scratch world for the watcher: its own `HOME`, its own router home, and a real MCP child that
/// answers `tools/list`.
///
/// **Real directories, real files, real processes, real `flock`** — X0. The watcher's whole subject
/// is what happens between two processes on one filesystem, and a memory filesystem cannot enter
/// any of the states this item exists to handle: it has no file modes, no advisory locks, and no
/// second process to lose a write to.
enum WatchWorld {
    struct Scratch {
        let root: URL
        let home: URL
        let routerHome: RouterHome
        let paths: WatchPaths

        var claudeJSON: String { paths.claudeJSON }
        var configPath: String { routerHome.configPath }
        var manifestPath: String { routerHome.manifestPath }
        var statePath: String { paths.statePath }
        var logPath: String { paths.logPath }
    }

    static func make(label: String = "scratch-label") throws -> Scratch {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mcp-router-watch-\(UUID().uuidString)")
        let home = root.appendingPathComponent("home")
        let routerRoot = home.appendingPathComponent(".claude/mcp-router")
        try FileManager.default.createDirectory(at: routerRoot, withIntermediateDirectories: true)
        let environment = ["HOME": home.path, "MCPR_LAUNCHD_LABEL": label]
        return Scratch(
            root: root,
            home: home,
            routerHome: RouterHome(environment: environment, homeDirectory: home.path),
            paths: WatchPaths(environment: environment, homeDirectory: home.path)
        )
    }

    static func remove(_ scratch: Scratch) {
        try? FileManager.default.removeItem(at: scratch.root)
    }

    // MARK: - Files

    static func write(_ text: String, to path: String, mode: UInt16? = nil) throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true
        )
        try text.write(toFile: path, atomically: true, encoding: .utf8)
        if let mode {
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: mode)], ofItemAtPath: path
            )
        }
    }

    static func read(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    static func json(_ path: String) -> JSONValue? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONParser.parse(data)
    }

    /// The `mcpServers` names a file declares, in file order.
    static func serverNames(in path: String) -> [String] {
        guard let parsed = json(path) else { return [] }
        return WatchStaging.stagedServers(of: parsed).map(\.key.string)
    }

    // MARK: - A real MCP child

    /// A stdio server that answers `initialize` and `tools/list`, and can be held at the door.
    ///
    /// `gate` is what makes the cross-process tests deterministic rather than a race: the child
    /// announces itself by creating `started`, then waits for `gate` to appear before answering
    /// anything. The test therefore controls exactly how long "indexing" takes, instead of betting
    /// on a `sleep` outrunning a process launch.
    static let childSource = """
    import json, os, sys, time

    pid_path = sys.argv[1]
    started = sys.argv[2] if len(sys.argv) > 2 else ""
    gate = sys.argv[3] if len(sys.argv) > 3 else ""
    tool = sys.argv[4] if len(sys.argv) > 4 else "alpha"

    with open(pid_path, "w") as handle:
        handle.write(str(os.getpid()))
    if started:
        with open(started, "w") as handle:
            handle.write("1")
    if gate:
        while not os.path.exists(gate):
            time.sleep(0.02)

    while True:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        message = json.loads(line)
        method = message.get("method")
        if method == "initialize":
            reply = {"jsonrpc": "2.0", "id": message["id"], "result": {
                "protocolVersion": "2025-06-18",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "watchstub", "version": "1.0.0"}}}
        elif method == "tools/list":
            reply = {"jsonrpc": "2.0", "id": message["id"], "result": {"tools": [
                {"name": tool, "description": "a tool", "inputSchema": {"type": "object"}}]}}
        else:
            continue
        sys.stdout.write(json.dumps(reply) + "\\n")
        sys.stdout.flush()
    """

    /// Materialise the child and return the `~/.claude.json` entry that runs it.
    static func childEntry(
        in scratch: Scratch,
        name: String,
        started: URL? = nil,
        gate: URL? = nil,
        tool: String = "alpha"
    ) throws -> JSONValue {
        let script = scratch.root.appendingPathComponent("watch-child.py")
        if !FileManager.default.fileExists(atPath: script.path) {
            try childSource.write(to: script, atomically: true, encoding: .utf8)
        }
        let pid = scratch.root.appendingPathComponent("\(name).pid")
        return .object([
            JSONMember(key: JSString("command"), value: .string(JSString("python3"))),
            JSONMember(key: JSString("args"), value: .array([
                .string(JSString(script.path)),
                .string(JSString(pid.path)),
                .string(JSString(started?.path ?? "")),
                .string(JSString(gate?.path ?? "")),
                .string(JSString(tool))
            ]))
        ])
    }

    /// A `~/.claude.json` declaring the given entries.
    static func stagingFile(_ entries: [(String, JSONValue)]) -> String {
        let servers = JSONValue.object(entries.map {
            JSONMember(key: JSString($0.0), value: $0.1)
        })
        return JSStringify.prettyTwoSpace(.object([
            JSONMember(key: JSString("numStartups"), value: .number(41)),
            JSONMember(key: JSString("mcpServers"), value: servers)
        ]))
    }

    /// A `servers.json` declaring the given entries.
    static func routerConfig(_ entries: [(String, JSONValue)]) -> String {
        JSStringify.prettyTwoSpace(.object([
            JSONMember(key: JSString("port"), value: .number(8879)),
            JSONMember(key: JSString("host"), value: .string(JSString("127.0.0.1"))),
            JSONMember(key: JSString("idleMs"), value: .number(300_000)),
            JSONMember(key: JSString("mcpServers"), value: .object(entries.map {
                JSONMember(key: JSString($0.0), value: $0.1)
            }))
        ])) + "\n"
    }

    /// Poll until `condition` holds, or give up. A fixed sleep is a bet on scheduler latency; this
    /// is the "becomes true" shape.
    static func waitUntil(
        seconds: Double = 10, _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            usleep(20000)
        }
        return condition()
    }

    /// A runner wired to one scratch world, with the restart captured rather than performed.
    static func runner(
        _ scratch: Scratch,
        kicks: RestartRecorder,
        clock: any RouterClock = SystemClock(),
        lockTimeoutMs: Int = 10000
    ) -> WatchRunner {
        WatchRunner(
            paths: scratch.paths,
            home: scratch.routerHome,
            clock: clock,
            kick: { label in kicks.record(label) },
            lockTimeoutMs: lockTimeoutMs,
            emit: { _ in }
        )
    }
}

/// Captures the restarts a run issues, and can be told to fail them.
///
/// The `launchctl` call is injected in unit tests for one measured reason: on this machine
/// `gg.rhodes.mcp-router` is loaded and serving, so a test that ran the real kickstart would restart
/// the developer's own router (X8a).
final class RestartRecorder: @unchecked Sendable {
    // Guarded by `lock` for every access, which is what makes the unchecked conformance honest —
    // SWIFT_PRACTICES §1 permits exactly this shape and asks for it to be said out loud.
    private let lock = NSLock()
    private var labels: [String] = []
    private var failure: String?

    init(failing: String? = nil) {
        failure = failing
    }

    func record(_ label: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        labels.append(label)
        return failure
    }

    var issued: [String] {
        lock.lock()
        defer { lock.unlock() }
        return labels
    }

    func stopFailing() {
        lock.lock()
        defer { lock.unlock() }
        failure = nil
    }
}
