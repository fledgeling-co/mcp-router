import Foundation
import Testing
@testable import RouterCore

/// `install-claude-json` — `docs/install.sh:162-188` reproduced, including the JavaScript
/// truthiness the `|| {}` depends on.
@Suite("Claude staging entry")
struct ClaudeStagingEntryTests {
    private func scratch() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mcp-router-staging-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func parse(_ text: String) throws -> JSONValue {
        try JSONParser.parse(Data(text.utf8))
    }

    private func servers(of value: JSONValue) -> [JSONMember]? {
        guard case let .object(members) = value,
              case let .object(entries)? = members
              .first(where: { $0.key == JSString("mcpServers") })?.value
        else { return nil }
        return entries
    }

    // MARK: - rewritten (pure)

    @Test("S1 — the entry is added to a file that declares no mcpServers")
    func theEntryIsAddedToAFileWithNoMcpServers() throws {
        let out = try ClaudeStagingEntry.rewritten(parse(#"{"projects":{"a":1}}"#), port: 8879)
        let entries = servers(of: out)
        #expect(entries?.map(\.key.string) == ["mcp-router"])
        // Everything else keeps its place: `mcpServers` is appended, `projects` stays first.
        #expect((out.asObjectMembers ?? []).map(\.key.string) == ["projects", "mcpServers"])
    }

    @Test("S2 — a null mcpServers is replaced, because null is falsy")
    func aNullMcpServersBecomesAnObject() throws {
        let out = try ClaudeStagingEntry.rewritten(parse(#"{"mcpServers":null}"#), port: 8879)
        #expect(servers(of: out)?.map(\.key.string) == ["mcp-router"])
    }

    @Test("S3 — 0, false and \"\" are falsy and are replaced too")
    func otherFalsyValuesAreReplaced() throws {
        for literal in ["0", "false", "\"\""] {
            let out = try ClaudeStagingEntry.rewritten(
                parse("{\"mcpServers\":\(literal)}"), port: 8879
            )
            #expect(servers(of: out)?.map(\.key.string) == ["mcp-router"], "for \(literal)")
        }
    }

    /// The input a rule of "any non-object becomes an object" would get wrong.
    ///
    /// `[] || {}` is `[]` in JavaScript — an empty array is truthy. The named property assignment
    /// then dies in `JSON.stringify`, so the file comes back with an empty array and no router
    /// entry at all.
    @Test("S4 — an empty array mcpServers is truthy and survives as an array")
    func anEmptyArrayIsLeftAsAnArray() throws {
        let out = try ClaudeStagingEntry.rewritten(parse(#"{"mcpServers":[]}"#), port: 8879)
        guard case let .object(members) = out else { Issue.record("not an object"); return }
        #expect(members.first { $0.key == JSString("mcpServers") }?.value == .array([]))
    }

    @Test("S5 — a truthy non-object mcpServers is left exactly as it was")
    func aTruthyNonObjectIsLeftAlone() throws {
        let out = try ClaudeStagingEntry.rewritten(parse(#"{"mcpServers":"x"}"#), port: 8879)
        guard case let .object(members) = out else { Issue.record("not an object"); return }
        #expect(members.first { $0.key == JSString("mcpServers") }?.value
            == .string(JSString("x")))
    }

    @Test("S6 — a legacy router entry on the same url is dropped")
    func aLegacyRouterEntryOnTheSameUrlIsDeleted() throws {
        let source = #"""
        {"mcpServers":{"router":{"type":"http","url":"http://127.0.0.1:8879/mcp"},"keep":{}}}
        """#
        let entries = try servers(of: ClaudeStagingEntry.rewritten(parse(source), port: 8879))
        // Two entries on one endpoint would double every tool in the list.
        #expect(entries?.map(\.key.string) == ["keep", "mcp-router"])
    }

    /// The false branch of the conditional delete. A lane that never sees it has not tested it.
    @Test("S7 — a router entry pointing somewhere else is somebody's own server and survives")
    func aLegacyRouterEntryOnAnotherUrlSurvives() throws {
        let source = #"""
        {"mcpServers":{"router":{"type":"http","url":"http://127.0.0.1:9999/mcp"}}}
        """#
        let entries = try servers(of: ClaudeStagingEntry.rewritten(parse(source), port: 8879))
        #expect(entries?.map(\.key.string) == ["router", "mcp-router"])
    }

    @Test("S8 — an existing mcp-router entry is replaced in place, not appended")
    func anExistingEntryIsReplacedInPlace() throws {
        let source = #"""
        {"mcpServers":{"mcp-router":{"type":"http","url":"http://127.0.0.1:1/mcp"},"z":{}}}
        """#
        let entries = try servers(of: ClaudeStagingEntry.rewritten(parse(source), port: 8879))
        #expect(entries?.map(\.key.string) == ["mcp-router", "z"])
        guard case let .object(entry)? = entries?.first?.value else {
            Issue.record("no entry"); return
        }
        #expect(entry.first { $0.key == JSString("url") }?.value
            == .string(JSString("http://127.0.0.1:8879/mcp")))
    }

    @Test("S9 — a non-object root round-trips with no entry, as the property write is a no-op")
    func nonObjectRootsRoundTrip() throws {
        for literal in ["[]", "\"x\"", "42"] {
            let parsed = try parse(literal)
            #expect(ClaudeStagingEntry.rewritten(parsed, port: 8879) == parsed, "for \(literal)")
        }
    }

    // MARK: - apply (filesystem)

    private func apply(at path: String, port: Int = 8879) throws -> ClaudeStagingEntry.Outcome {
        try ClaudeStagingEntry.apply(
            atPath: path, port: port, fileSystem: RealFileSystem(),
            processIdentifier: 4444, now: Date()
        )
    }

    @Test("S10 — the file mode is carried onto the replacement, both ways")
    func theModeIsPreserved() throws {
        for mode in [0o600, 0o644] {
            let root = try scratch()
            let path = root.appendingPathComponent(".claude.json").path
            try #"{"mcpServers":{}}"#.write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: mode], ofItemAtPath: path
            )
            _ = try apply(at: path)
            // A temp file plus rename takes the umask's mode otherwise, so a ~/.claude.json the
            // user keeps at 0600 would come back world-readable.
            #expect(try RealFileSystem().fileMode(atPath: path) == UInt16(mode), "for \(mode)")
        }
    }

    @Test("S11 — a backup is written carrying the pre-image bytes")
    func aBackupCarriesThePreImage() throws {
        let root = try scratch()
        let path = root.appendingPathComponent(".claude.json").path
        let preImage = #"{"mcpServers":{"a":{"command":"x"}}}"#
        try preImage.write(toFile: path, atomically: true, encoding: .utf8)

        guard case let .rewritten(backup, addedEntry) = try apply(at: path) else {
            Issue.record("expected a rewrite"); return
        }
        #expect(addedEntry)
        #expect(try String(contentsOfFile: backup, encoding: .utf8) == preImage)
        // `install.sh:162`'s shape: `date +%Y%m%d-%H%M%S`, local time.
        #expect(backup.hasPrefix("\(path).bak-mcp-router-"))
        let stamp = backup.replacingOccurrences(of: "\(path).bak-mcp-router-", with: "")
        #expect(stamp.count == 15 && stamp.contains("-"))
    }

    @Test("S12 — an absent staging file writes nothing and does not fail")
    func anAbsentFileWritesNothing() throws {
        let root = try scratch()
        let path = root.appendingPathComponent(".claude.json").path
        // install.sh guards with `[[ -f "$CLAUDE_JSON" ]]` and carries on.
        #expect(try apply(at: path) == .noStagingFile)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    /// The reference's order: `cp` at install.sh:162, `JSON.parse` at :169. So an unparseable file
    /// leaves a recovery copy and an untouched original — the copy is a byte-for-byte snapshot, not
    /// content derived from the parse that failed, so there was never anything to withhold.
    @Test("S13 — an unparseable staging file leaves a backup and does not rewrite the original")
    func anUnparseableFileLeavesABackupAndNoRewrite() throws {
        let root = try scratch()
        let path = root.appendingPathComponent(".claude.json").path
        try "{ truncated".write(toFile: path, atomically: true, encoding: .utf8)

        #expect(throws: ClaudeStagingEntry.Problem.self) { _ = try apply(at: path) }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "{ truncated")
        let entries = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        #expect(entries.count == 2)
        let backup = try #require(entries.first { $0 != ".claude.json" })
        #expect(backup.hasPrefix(".claude.json.bak-mcp-router-"))
        #expect(try String(
            contentsOfFile: root.appendingPathComponent(backup).path, encoding: .utf8
        ) == "{ truncated")
        // No temporary left behind either: a rename that never happened must not leave one.
        #expect(!entries.contains { $0.contains(".mcpr-tmp-") })
    }

    /// Same shape as S13, and asserted the same way for the same reason: an implementation that
    /// wrote first and threw afterwards would satisfy a bare `throws` check.
    @Test("S14 — a null document throws and does not rewrite the original")
    func aNullDocumentThrows() throws {
        let root = try scratch()
        let path = root.appendingPathComponent(".claude.json").path
        try "null".write(toFile: path, atomically: true, encoding: .utf8)

        #expect(throws: ClaudeStagingEntry.Problem.self) { _ = try apply(at: path) }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "null")
        let entries = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        #expect(entries.count == 2)
        #expect(!entries.contains { $0.contains(".mcpr-tmp-") })
    }

    /// `[[ -f ]]` is false for a directory; `FileManager.fileExists` is true. Getting that wrong
    /// makes the verb exit non-zero where `install.sh` skips the step and carries on — and under
    /// R4-C's `set -e` that aborts an install the reference completes.
    @Test("S14b — a directory at the staging path is skipped, exactly as [[ -f ]] skips it")
    func aDirectoryAtTheStagingPathIsSkipped() throws {
        let root = try scratch()
        let path = root.appendingPathComponent(".claude.json").path
        try FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true
        )
        #expect(try apply(at: path) == .noStagingFile)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == [".claude.json"])
    }

    /// A non-object root is a no-op for the property write, so nothing may report an entry added.
    @Test("S14c — a non-object root reports that no entry was added")
    func aNonObjectRootReportsNoEntryAdded() throws {
        let root = try scratch()
        let path = root.appendingPathComponent(".claude.json").path
        try "[]".write(toFile: path, atomically: true, encoding: .utf8)
        guard case let .rewritten(_, addedEntry) = try apply(at: path) else {
            Issue.record("expected a rewrite"); return
        }
        #expect(!addedEntry)
    }

    @Test("S15 — the written file carries no trailing newline")
    func thereIsNoTrailingNewline() throws {
        let root = try scratch()
        let path = root.appendingPathComponent(".claude.json").path
        try #"{"mcpServers":{}}"#.write(toFile: path, atomically: true, encoding: .utf8)
        _ = try apply(at: path)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)).last == UInt8(ascii: "}"))
    }

    /// The default port, asserted on the **written file** rather than on the interpolation.
    ///
    /// `#expect(url(port: defaultPort) == "…8879…")` was the first form of this test and it is
    /// identity — the expression agreeing with itself. It could not catch a wrong default, and the
    /// default that actually matters lives in `InstallEntryVerb`'s `?? RouterHome.defaultPort`,
    /// which `swift test` cannot reach. That half is covered by the `install-claude-json` lane's
    /// scenario that runs `install-entry` with **no** `--port` at all.
    @Test("S16 — apply writes the default port's url into the file")
    func theDefaultPortReachesTheWrittenFile() throws {
        let root = try scratch()
        let path = root.appendingPathComponent(".claude.json").path
        try #"{"mcpServers":{}}"#.write(toFile: path, atomically: true, encoding: .utf8)
        _ = try apply(at: path, port: RouterHome.defaultPort)
        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(text.contains("\"url\": \"http://127.0.0.1:8879/mcp\""))
    }
}
