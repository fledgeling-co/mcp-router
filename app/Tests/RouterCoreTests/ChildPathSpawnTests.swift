import Foundation
import Testing
@testable import RouterCore

/// R6's red-green proof, against a real child process.
///
/// The fixture is an executable that exists in exactly one place: a `bin` directory inside a
/// dot-directory of a scratch home. Nothing else on the PATH can resolve it, which is the shape of
/// the reported defect — `claude`, `codex`, `cursor-agent` and `agy` in `~/.local/bin`, `grok` in
/// `~/.grok/bin`, and a launchd PATH that names none of them.
@Suite("R6 — a command reachable only through a discovered directory", .serialized)
struct ChildPathSpawnTests {
    /// A launchd PATH, as `docs/install.sh` writes it: no directory under the user's home.
    private static let launchdPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

    private struct Fixture {
        let home: URL
        let workspace: URL
        let commandName: String
        let binDirectory: URL
    }

    /// A scratch home whose `.fixture/bin` holds a wrapper that runs the stub MCP server.
    ///
    /// The wrapper calls `python3` by absolute path so that what is being proved is the resolution
    /// of the *wrapper*, not a second PATH lookup inside it.
    private func makeFixture() throws -> Fixture {
        let root = try StubServer.makeDirectory()
        let home = root.appendingPathComponent("home")
        let binDirectory = home.appendingPathComponent(".fixture/bin")
        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        let python = try #require(
            StdioUpstreamTransport.resolve("python3"),
            "python3 must be resolvable for the stub server to run at all"
        )
        let commandName = "mcpr-r6-fixture"
        let wrapper = binDirectory.appendingPathComponent(commandName)
        try "#!/bin/sh\nexec \(python) \"$@\"\n".write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: wrapper.path
        )
        return Fixture(home: home, workspace: root, commandName: commandName, binDirectory: binDirectory)
    }

    private func config(_ fixture: Fixture, name: String) throws -> UpstreamConfig {
        let base = try StubServer.config(name: name, mode: .reports, directory: fixture.workspace)
        return UpstreamConfig(
            name: base.name,
            transport: base.transport,
            raw: base.raw,
            idleMs: base.idleMs,
            startupTimeoutMs: base.startupTimeoutMs,
            projects: base.projects,
            warm: base.warm,
            placard: base.placard,
            command: fixture.commandName,
            args: base.args,
            env: base.env,
            cwd: base.cwd,
            url: base.url,
            headers: base.headers,
            oauth: base.oauth
        )
    }

    @Test("A4 — the same command is unresolvable under launchd's PATH and resolvable under the augmented one")
    func redThenGreen() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.workspace) }

        let launchd = ["HOME": fixture.home.path, "PATH": Self.launchdPath]

        // Red: what the router did before this change — resolve against its own environment.
        #expect(
            StdioUpstreamTransport.resolve(fixture.commandName, environment: launchd) == nil,
            "the fixture must be unreachable through launchd's PATH, or the test proves nothing"
        )

        // Green: the environment the child is now given.
        let augmented = ChildPath.augmentedEnvironment(launchd)
        #expect(
            StdioUpstreamTransport.resolve(fixture.commandName, environment: augmented)
                == fixture.binDirectory.appendingPathComponent(fixture.commandName).path
        )
    }

    @Test(
        "A3, A5 — launchd's PATH names the failure; a router that discovers the directory starts the child"
    )
    func spawnsThroughADiscoveredDirectory() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.workspace) }

        // A home the probe reports nothing for stands in for the pre-change router: same command,
        // same launchd PATH, no discovery.
        let blind = StdioUpstreamTransport(
            environment: ["HOME": fixture.home.path, "PATH": Self.launchdPath],
            probe: NoDirectories()
        )
        await #expect(throws: PoolError.commandNotFound(
            name: "blind",
            command: fixture.commandName,
            searchedPath: Self.launchdPath
        )) {
            try await blind.open(config(fixture, name: "blind"), timeoutMilliseconds: 8000)
        }

        let seeing = StdioUpstreamTransport(
            environment: ["HOME": fixture.home.path, "PATH": Self.launchdPath]
        )
        let session = try await seeing.open(config(fixture, name: "seeing"), timeoutMilliseconds: 8000)
        defer { Task { await session.shutdown() } }

        let launch = try StubServer.launch(name: "seeing", directory: fixture.workspace)
        let childPath = try #require(launch.env["PATH"])
        #expect(childPath.hasPrefix(Self.launchdPath), "launchd's entries keep their place at the front")
        #expect(childPath.split(separator: ":").map(String.init)
            .contains(fixture.binDirectory.path))
    }
}

/// A probe that finds nothing, standing in for the router before R6.
private struct NoDirectories: DirectoryProbing {
    func entries(ofDirectoryAt path: String) -> [String] {
        []
    }

    func isDirectory(atPath path: String) -> Bool {
        false
    }
}
