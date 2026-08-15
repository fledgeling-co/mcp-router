import Foundation
import Testing
@testable import RouterCore

/// `spec-R1` D3 on the path D3 was written about, plus the create-only `0600` the Swift import
/// writer was missing.
@Suite("Import config writer", .serialized)
struct ImportConfigWriterTests {
    /// `JSON.stringify({port, host, idleMs, mcpServers}, null, 2)` — **captured from node**, not
    /// from `JSStringify`. A pre-image recorded from Swift is the writer agreeing with itself.
    static let referenceBytes = """
    {
      "port": 8879,
      "host": "127.0.0.1",
      "idleMs": 300000,
      "mcpServers": {
        "alpha": {
          "command": "node",
          "args": [
            "x.js"
          ]
        }
      }
    }
    """

    private func scratch() throws -> URL {
        try ImportWriterFixtures.scratch()
    }

    private func write(
        to path: String,
        adopted: [JSONMember]? = nil,
        fileSystem: any FileSystem & FileModeWriting = ImportWriterProbeFileSystem(),
        lockTimeoutMs: Int = 5000
    ) throws {
        try ImportWriterFixtures.write(
            to: path, adopted: adopted, fileSystem: fileSystem, lockTimeoutMs: lockTimeoutMs
        )
    }

    // MARK: - preservation (D3)

    @Test("W1 — an unknown top-level key survives in its original position")
    func unknownTopLevelKeysSurviveInPlace() throws {
        let root = try scratch()
        let path = root.appendingPathComponent("servers.json").path
        try """
        {
          "port": 1,
          "startupTimeoutMs": 45000,
          "host": "0.0.0.0",
          "idleMs": 1,
          "mcpServers": {}
        }
        """.write(toFile: path, atomically: true, encoding: .utf8)

        try write(to: path)

        let parsed = try JSONParser.parse(Data(contentsOf: URL(fileURLWithPath: path)))
        let keys = (parsed.asObjectMembers ?? []).map(\.key.string)
        // Position AND value. Presence alone would pass a rewrite that moved the key to the end,
        // which preserves the setting and changes the bytes of a file the user reads.
        #expect(keys == ["port", "startupTimeoutMs", "host", "idleMs", "mcpServers"])
        let kept = parsed.asObjectMembers?.first { $0.key == JSString("startupTimeoutMs") }?.value
        #expect(kept == .number(45000))
    }

    @Test("W2 — the four keys the reference writes are overwritten")
    func theFourKeysAreOverwritten() throws {
        let root = try scratch()
        let path = root.appendingPathComponent("servers.json").path
        try #"{"port":1,"host":"0.0.0.0","idleMs":1,"mcpServers":{"gone":{}}}"#
            .write(toFile: path, atomically: true, encoding: .utf8)

        try write(to: path)

        let parsed = try JSONParser.parse(Data(contentsOf: URL(fileURLWithPath: path)))
        let members = parsed.asObjectMembers ?? []
        #expect(members.first { $0.key == JSString("port") }?.value == .number(8879))
        #expect(members.first { $0.key == JSString("host") }?.value
            == .string(JSString("127.0.0.1")))
        #expect(members.first { $0.key == JSString("idleMs") }?.value == .number(300_000))
        guard case let .object(servers)? = members
            .first(where: { $0.key == JSString("mcpServers") })?.value
        else { Issue.record("mcpServers is not an object"); return }
        #expect(servers.map(\.key.string) == ["alpha"])
    }

    @Test("W3 — a destination that does not parse is overwritten, not refused")
    func anUnparseableDestinationIsOverwritten() throws {
        let root = try scratch()
        let path = root.appendingPathComponent("servers.json").path
        try "{ truncated".write(toFile: path, atomically: true, encoding: .utf8)

        // The reference overwrites unconditionally. Throwing would wedge the one command whose
        // whole job is to rebuild this file.
        try write(to: path)

        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(text.contains("\"alpha\""))
    }

    // MARK: - bytes

    @Test("W4 — a first write matches the bytes node's JSON.stringify produces")
    func aFirstWriteMatchesTheReferenceBytes() throws {
        let root = try scratch()
        let path = root.appendingPathComponent("servers.json").path

        try write(to: path)

        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(text == Self.referenceBytes)
    }

    @Test("W5 — there is no trailing newline")
    func thereIsNoTrailingNewline() throws {
        let root = try scratch()
        let path = root.appendingPathComponent("servers.json").path
        try write(to: path)
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        // `WatchAdoption` appends "\n" under the WATCHER's rules; copying that here would change
        // bytes `cli-import` compares.
        #expect(data.last == UInt8(ascii: "}"))
    }

    // MARK: - mode

    @Test("W6 — a file that did not exist is created at 0600")
    func aFreshFileIsCreatedAt0600() throws {
        let root = try scratch()
        let path = root.appendingPathComponent("servers.json").path
        try write(to: path)
        #expect(try RealFileSystem().fileMode(atPath: path) == 0o600)
    }

    @Test("W7 — an existing 0644 file keeps 0644")
    func anExisting0644FileStaysAt0644() throws {
        let root = try scratch()
        let path = root.appendingPathComponent("servers.json").path
        try "{}".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)

        try write(to: path)

        // node's `{ mode: 0o600 }` applies on CREATE only. `writeAtomic(.fixed(0o600))` writes a
        // new inode and would narrow this file — every server's env lives in it.
        #expect(try RealFileSystem().fileMode(atPath: path) == 0o644)
    }

    /// The case W6 and W7 together do **not** cover.
    ///
    /// `fileExists ? .fixed(0o644) : .fixed(0o600)` passes both of them while widening a config the
    /// user narrowed. Without this test that implementation ships.
    @Test("W8 — an existing 0600 file keeps 0600")
    func anExisting0600FileStaysAt0600() throws {
        let root = try scratch()
        let path = root.appendingPathComponent("servers.json").path
        try "{}".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)

        try write(to: path)

        #expect(try RealFileSystem().fileMode(atPath: path) == 0o600)
    }

    // MARK: - atomicity

    @Test("W9 — a failed rename leaves the destination exactly as it was")
    func aRenameFailureLeavesTheDestinationUntouched() throws {
        let root = try scratch()
        let path = root.appendingPathComponent("servers.json").path
        let preImage = #"{"port":1,"host":"0.0.0.0","idleMs":1,"mcpServers":{"kept":{}}}"#
        try preImage.write(toFile: path, atomically: true, encoding: .utf8)

        let probe = ImportWriterProbeFileSystem(failMoveItem: true)
        #expect(throws: (any Error).self) { try write(to: path, fileSystem: probe) }

        // Three assertions, because "the destination is unchanged" is ALSO what a writer that threw
        // before doing any I/O produces — identity's cousin, and it would pass a non-atomic writer
        // that simply never ran.
        #expect(probe.moveAttempts == [path])
        let temporary = "\(path).mcpr-tmp-4242"
        #expect(FileManager.default.fileExists(atPath: temporary))
        #expect(try String(contentsOfFile: temporary, encoding: .utf8).contains("\"alpha\""))
        #expect(try String(contentsOfFile: path, encoding: .utf8) == preImage)
    }

    // MARK: - the lock
}
