import Foundation
import Testing
@testable import RouterCore

/// W10 — the clause this item is a child spec for.
///
/// The watcher, the daemon's control API and the Mac app all write `servers.json`. The daemon's
/// read-modify-write is microseconds; the watcher's spans **seconds**, because it spawns and indexes
/// a child in the middle. An adoption that read the file before indexing and wrote it afterwards
/// erases every PATCH that landed in between.
///
/// **None of this is visible in a single-process test**, which is why these use a real second
/// process, a real `flock`, and a real child held at the door so the window is deterministic rather
/// than raced.
@Suite("Config watcher, across processes", .serialized)
struct WatchCrossProcessTests {
    /// A foreign writer: takes the sidecar lock the way any participant must, adds one server, and
    /// commits by rename. Deliberately **not** written through `ConfigEdit` — a test that used our
    /// own writer would prove the two halves of one implementation agree, not that the protocol is
    /// one an independent process can join.
    private static let patcher = """
    import fcntl, json, os, sys, time

    config, ready, name = sys.argv[1], sys.argv[2], sys.argv[3]
    lock = config + ".lock"
    fd = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
    fcntl.flock(fd, fcntl.LOCK_EX)
    with open(config) as handle:
        data = json.load(handle)
    data.setdefault("mcpServers", {})[name] = {"command": "true", "args": []}
    tmp = config + ".patch-tmp"
    with open(tmp, "w") as handle:
        json.dump(data, handle, indent=2)
    os.rename(tmp, config)
    fcntl.flock(fd, fcntl.LOCK_UN)
    os.close(fd)
    with open(ready, "w") as handle:
        handle.write("1")
    """

    private func patch(
        _ scratch: WatchWorld.Scratch, named name: String, ready: URL
    ) throws -> Process {
        let script = scratch.root.appendingPathComponent("patcher.py")
        if !FileManager.default.fileExists(atPath: script.path) {
            try Self.patcher.write(to: script, atomically: true, encoding: .utf8)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, scratch.configPath, ready.path, name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    @Test("A1/W10 — a concurrent PATCH survives an adoption that is mid-index")
    func concurrentPatchSurvivesAdoption() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let started = scratch.root.appendingPathComponent("started")
        let gate = scratch.root.appendingPathComponent("gate")
        let ready = scratch.root.appendingPathComponent("patched")
        let entry = try WatchWorld.childEntry(
            in: scratch, name: "probe", started: started, gate: gate
        )
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)

        // The other process runs while the child is held at the door, which is the window the
        // reference leaves open. Waiting on the child's own announcement rather than sleeping is
        // what makes this a test rather than a coin flip.
        let interference = Task.detached { [self] in
            _ = WatchWorld.waitUntil(seconds: 30) {
                FileManager.default.fileExists(atPath: started.path)
            }
            let process = try patch(scratch, named: "patched", ready: ready)
            process.waitUntilExit()
            // A10/X3 — the patch completing here is itself the proof that the watcher is NOT
            // holding the lock across indexing.
            FileManager.default.createFile(atPath: gate.path, contents: Data("1".utf8))
        }

        try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()
        try await interference.value

        #expect(
            FileManager.default.fileExists(atPath: ready.path),
            "the other process never completed its write while indexing was in flight (X3)"
        )
        let names = WatchWorld.serverNames(in: scratch.configPath).sorted()
        #expect(
            names == ["patched", "probe"],
            "servers.json holds \(names) — a concurrent PATCH was erased by the adoption"
        )
    }

    @Test("A2 — MUTATION: writing back a pre-index snapshot loses the concurrent PATCH")
    func preIndexSnapshotLosesThePatch() throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let ready = scratch.root.appendingPathComponent("patched")
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)

        // The reference's algorithm, written out: read the whole object, spend time indexing, then
        // write that object back. Nothing here is the watcher's code — this is the defect being
        // demonstrated, so that the green above means something.
        let snapshot = try JSONParser.parse(
            RealFileSystem().readFile(atPath: scratch.configPath)
        )

        let process = try patch(scratch, named: "patched", ready: ready)
        process.waitUntilExit()
        #expect(WatchWorld.serverNames(in: scratch.configPath) == ["patched"])

        // "Indexing finished"; write the snapshot back with our own addition.
        var root = try #require(snapshot.asObjectMembers)
        let adopted = JSONValue.object([
            JSONMember(key: JSString("probe"), value: .object([
                JSONMember(key: JSString("command"), value: .string(JSString("true")))
            ]))
        ])
        if let index = root.firstIndex(where: { $0.key == JSString("mcpServers") }) {
            root[index] = JSONMember(key: JSString("mcpServers"), value: adopted)
        }
        try WatchWorld.write(
            JSStringify.prettyTwoSpace(.object(root)) + "\n", to: scratch.configPath
        )

        #expect(
            WatchWorld.serverNames(in: scratch.configPath) == ["probe"],
            "the mutation did not reproduce the lost update, so A1's green proves nothing"
        )
    }

    @Test("X4b/C2 — an approval written to manifest.json mid-index is not erased")
    func concurrentManifestApprovalSurvives() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let started = scratch.root.appendingPathComponent("started")
        let gate = scratch.root.appendingPathComponent("gate")
        let entry = try WatchWorld.childEntry(
            in: scratch, name: "probe", started: started, gate: gate
        )
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)
        try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)

        // A manifest that already holds another server, as it would on any real machine.
        var seed = Manifest.empty
        seed.setEntry("other", CachedServer(members: [
            JSONMember(key: JSString("hash"), value: .string(JSString("seed"))),
            JSONMember(key: JSString("tools"), value: .array([]))
        ]))
        try ManifestIO.save(seed, toPath: scratch.manifestPath, fileSystem: RealFileSystem())

        // The Mac app approves a held change on `other` while `probe` is being indexed. The
        // reference loads the manifest before indexing and saves it afterwards, so this write is
        // erased by the save that follows it (`watch.ts:212,253`).
        let approver = Task.detached {
            _ = WatchWorld.waitUntil(seconds: 30) {
                FileManager.default.fileExists(atPath: started.path)
            }
            var manifest = ManifestIO.load(
                path: scratch.manifestPath, fileSystem: RealFileSystem()
            ).manifest
            manifest.setEntry("other", CachedServer(members: [
                JSONMember(key: JSString("hash"), value: .string(JSString("seed"))),
                JSONMember(key: JSString("approvedByTheUser"), value: .bool(true)),
                JSONMember(key: JSString("tools"), value: .array([]))
            ]))
            try ManifestIO.save(
                manifest, toPath: scratch.manifestPath, fileSystem: RealFileSystem()
            )
            FileManager.default.createFile(atPath: gate.path, contents: Data("1".utf8))
        }

        try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()
        try await approver.value

        let after = ManifestIO.load(
            path: scratch.manifestPath, fileSystem: RealFileSystem()
        ).manifest
        #expect(
            after.entry(named: "other")?.member("approvedByTheUser")?.isTruthy == true,
            "the approval was erased by the watcher's own manifest write"
        )
        #expect(after.entry(named: "probe") != nil, "and the newly indexed entry is still there")
    }

    @Test("W-D9 — a PATCH that deletes the server being adopted is re-applied by the merge")
    func sameNameDeletionIsReversed() async throws {
        let scratch = try WatchWorld.make()
        defer { WatchWorld.remove(scratch) }
        let started = scratch.root.appendingPathComponent("started")
        let gate = scratch.root.appendingPathComponent("gate")
        let entry = try WatchWorld.childEntry(
            in: scratch, name: "probe", started: started, gate: gate
        )
        try WatchWorld.write(WatchWorld.stagingFile([("probe", entry)]), to: scratch.claudeJSON)
        // `probe` is already in the router's list, and the other process removes it mid-adoption.
        try WatchWorld.write(WatchWorld.routerConfig([("probe", entry)]), to: scratch.configPath)

        let deleter = Task.detached {
            _ = WatchWorld.waitUntil(seconds: 30) {
                FileManager.default.fileExists(atPath: started.path)
            }
            try WatchWorld.write(WatchWorld.routerConfig([]), to: scratch.configPath)
            FileManager.default.createFile(atPath: gate.path, contents: Data("1".utf8))
        }

        try await WatchWorld.runner(scratch, kicks: RestartRecorder()).run()
        try await deleter.value

        // Declared behaviour, not an accident: the lock serialises writes, it cannot arbitrate
        // intent, and the staged entry is fresh user intent too. See W-D9 in spec-R2W.md. This
        // assertion exists so the behaviour is defined rather than discovered by a user.
        #expect(WatchWorld.serverNames(in: scratch.configPath) == ["probe"])
    }
}
