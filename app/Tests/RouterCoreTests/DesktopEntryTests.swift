import Foundation
import Testing
@testable import RouterCore

/// R32 — the entry Claude Desktop would actually accept, and the boundary around it.
///
/// The suite that matters most here is the first one. Every other test in this file is about a
/// writer behaving; D1-D5 are about the measurement that made the writer necessary, and they are
/// written so that a future version of Desktop relaxing its schema turns them red rather than
/// leaving a stricter check in place than the world needs.
@Suite("Desktop entry")
struct DesktopEntryTests {
    private func parse(_ text: String) throws -> JSONValue {
        try JSONParser.parse(Data(text.utf8))
    }

    private func scratch() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mcp-router-desktop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private let bridge = DesktopBridge(
        command: "/opt/bridge/mcp-bridge", arguments: ["http://127.0.0.1:8879/mcp"]
    )

    // MARK: - Desktop's schema, as transcribed

    /// The whole reason this item is not a two-line change.
    ///
    /// This is the shape `install-entry` writes into `~/.claude.json` and the shape anybody would
    /// reach for first. Desktop's schema requires `command`, so this entry fails `safeParse`, is
    /// filtered out of the config, and the user is shown a dialog naming it as skipped.
    @Test("D1 — the entry Claude Code takes is one Claude Desktop would skip")
    func theHTTPEntryIsSkippedByDesktop() throws {
        let http = try parse(#"{"type":"http","url":"http://127.0.0.1:8879/mcp"}"#)
        let verdict = DesktopEntry.conformance(of: http)
        #expect(!verdict.isAccepted)
        #expect(verdict.skipped == ["\"command\" is required and is missing"])
    }

    /// zod's default object strips what it does not declare rather than rejecting it, so the two
    /// verdicts are genuinely different and collapsing them would either refuse a working entry or
    /// promise that a stripped member arrives.
    @Test("D2 — url and type beside a command are dropped, not fatal")
    func undeclaredMembersAreDroppedNotFatal() throws {
        let mixed = try parse(#"{"command":"/x","type":"http","url":"http://h/mcp"}"#)
        let verdict = DesktopEntry.conformance(of: mixed)
        #expect(verdict.isAccepted)
        #expect(verdict.dropped == ["type", "url"])
    }

    @Test("D3 — args must be an array of strings, and both ways of failing that are reported")
    func argsMustBeAnArrayOfStrings() throws {
        let notAnArray = try DesktopEntry.conformance(of: parse(#"{"command":"/x","args":"one"}"#))
        #expect(notAnArray.skipped == ["\"args\" is a string, and the schema says array of string"])
        let wrongItem = try DesktopEntry.conformance(of: parse(#"{"command":"/x","args":[1]}"#))
        #expect(wrongItem.skipped == ["\"args\" holds a number, and the schema says array of string"])
    }

    @Test("D4 — env must be a record of strings")
    func envMustBeARecordOfStrings() throws {
        let verdict = try DesktopEntry.conformance(of: parse(#"{"command":"/x","env":{"A":3}}"#))
        #expect(verdict.skipped == ["\"env\".A is a number, and the schema says record of string"])
    }

    @Test("D5 — the entry this product builds is one Desktop accepts, with nothing dropped")
    func theBuiltEntryConforms() {
        let verdict = DesktopEntry.conformance(of: DesktopEntry.entry(bridge: bridge))
        #expect(verdict.isAccepted)
        #expect(verdict.dropped.isEmpty)
    }

    // MARK: - rewriting the document

    /// The file this was measured against is the owner's window state, editor paths and account
    /// preferences with one empty object in it. A writer that rebuilt the document from what it
    /// understood would take all of that away.
    @Test("D6 — every member the router does not own survives, in its original order")
    func unrelatedMembersSurviveInOrder() throws {
        let source = #"""
        {"mcpServers":{},"coworkUserFilesPath":"/u/Documents","preferences":{"menuBarEnabled":false}}
        """#
        let out = try DesktopEntry.rewritten(parse(source), bridge: bridge)
        #expect((out.asObjectMembers ?? []).map(\.key.string)
            == ["mcpServers", "coworkUserFilesPath", "preferences"])
        #expect(out.member("preferences")?.member("menuBarEnabled") == .bool(false))
    }

    @Test("D7 — mcpServers is appended when the document declares none, and other entries are kept")
    func theServersObjectIsCreatedOrExtended() throws {
        let fresh = try DesktopEntry.rewritten(parse(#"{"preferences":{}}"#), bridge: bridge)
        #expect((fresh.asObjectMembers ?? []).map(\.key.string) == ["preferences", "mcpServers"])

        let existing = try DesktopEntry.rewritten(
            parse(#"{"mcpServers":{"other":{"command":"/bin/true"}}}"#), bridge: bridge
        )
        #expect(existing.member("mcpServers")?.asObjectMembers?.map(\.key.string)
            == ["other", "mcp-router"])
    }

    /// The deliberate divergence from ``ClaudeStagingEntry``, which reproduces an installer whose
    /// JavaScript treats these as silent no-ops. This is a command somebody typed, and "nothing
    /// happened, exit 0" is the wrong answer to it.
    @Test("D8 — a root or an mcpServers that is not an object is refused rather than replaced")
    func nonObjectsAreRefused() throws {
        #expect(throws: DesktopEntry.Refusal.rootIsNotAnObject(found: "array")) {
            try DesktopEntry.rewritten(self.parse("[]"), bridge: self.bridge)
        }
        #expect(throws: DesktopEntry.Refusal.serversIsNotAnObject(found: "array")) {
            try DesktopEntry.rewritten(self.parse(#"{"mcpServers":[]}"#), bridge: self.bridge)
        }
    }

    /// Comparing the whole entry rather than the name. A config naming a bridge that has since
    /// moved is stale, and reporting it as up to date is how somebody ends up debugging a Desktop
    /// that fronts nothing.
    @Test("D9 — a stale entry under the same name does not read as up to date")
    func aStaleEntryIsNotCurrent() throws {
        let document = try DesktopEntry.rewritten(parse("{}"), bridge: bridge)
        #expect(DesktopEntry.declaresCurrentEntry(document, bridge: bridge))
        let moved = DesktopBridge(command: "/opt/bridge/mcp-bridge", arguments: ["http://other/mcp"])
        #expect(!DesktopEntry.declaresCurrentEntry(document, bridge: moved))
    }

    // MARK: - the bridge

    /// Absoluteness is checked before executability because the second hides the first: a bare name
    /// that resolves on the developer's PATH passes an executability check taken in a terminal and
    /// then fails inside Desktop, which is launched with no shell in its environment.
    @Test("D10 — a bare command name is refused for being relative, not for being missing")
    func aBareCommandNameIsRefusedAsRelative() {
        let problem = DesktopBridge(command: "mcp-remote", arguments: [])
            .problem(using: RealFileSystem())
        #expect(problem == .bridgeNotAbsolute(command: "mcp-remote"))
    }

    @Test("D11 — an absolute path that is absent, or present and not executable, is refused")
    func anAbsolutePathMustBeExecutable() throws {
        let root = try scratch()
        let missing = root.appendingPathComponent("nope").path
        #expect(DesktopBridge(command: missing, arguments: []).problem(using: RealFileSystem())
            == .bridgeNotExecutable(path: missing))

        let plain = root.appendingPathComponent("plain").path
        try "x".write(toFile: plain, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plain)
        #expect(DesktopBridge(command: plain, arguments: []).problem(using: RealFileSystem())
            == .bridgeNotExecutable(path: plain))

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: plain)
        #expect(DesktopBridge(command: plain, arguments: []).problem(using: RealFileSystem()) == nil)
    }

    // MARK: - the write

    @Test("D12 — the mode is carried onto the replacement, both ways")
    func theModeIsPreserved() throws {
        for mode in [0o600, 0o644] {
            let root = try scratch()
            let path = root.appendingPathComponent("claude_desktop_config.json").path
            try #"{"mcpServers":{}}"#.write(toFile: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
            let applied = try DesktopEntryWriter.apply(
                document: "{}\n", toPath: path, fileSystem: RealFileSystem(),
                processIdentifier: 4444, now: Date()
            )
            #expect(applied.mode == UInt16(mode), "for \(mode)")
            // The measured file is 0600. A temp-plus-rename takes the umask's mode otherwise, so
            // the router would publish the user's local endpoints to every process on the machine.
            #expect(try RealFileSystem().fileMode(atPath: path) == UInt16(mode), "for \(mode)")
        }
    }

    @Test("D13 — the backup carries the pre-image bytes and the file carries the new ones")
    func theBackupCarriesThePreImage() throws {
        let root = try scratch()
        let path = root.appendingPathComponent("claude_desktop_config.json").path
        let preImage = #"{"mcpServers":{}}"#
        try preImage.write(toFile: path, atomically: true, encoding: .utf8)

        let applied = try DesktopEntryWriter.apply(
            document: "{\"a\":1}\n", toPath: path, fileSystem: RealFileSystem(),
            processIdentifier: 4444, now: Date()
        )
        #expect(try String(contentsOfFile: applied.backup, encoding: .utf8) == preImage)
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "{\"a\":1}\n")
        #expect(applied.bytesBefore == preImage.utf8.count)
        #expect(applied.bytesAfter == 8)
    }

    // MARK: - the boundary

    /// The one assertion that carries the item's argument. A located path is a lead; treating it as
    /// a capability is propagate-and-assume, which is the failure the brief exists to name.
    @Test("D14 — a reload path that was located but never driven is not reliable")
    func aLocatedReloadPathIsNotReliable() {
        #expect(!ReloadPath.claudeDesktopConfigChange.isReliable)
        #expect(ReloadPath.claudeDesktopConfigChange.actuation == .humanOnly)
        #expect(!ReloadPath.unknown.isReliable)
        #expect(ReloadPath.unknown.actuation == nil)
        #expect(ReloadPath.exercised(
            mechanism: "m", actuation: .programmatic, artifact: "a", probe: "p", on: "d"
        ).isReliable)
    }

    @Test("D15 — the summary leads with how it was established, not with the verdict")
    func theSummaryNamesItsProvenance() {
        let summary = ReloadPath.claudeDesktopConfigChange.summary
        #expect(summary.contains("NOT exercised"))
        #expect(summary.contains("only a person can drive it"))
        #expect(summary.contains("1.30096.1"))
    }
}

/// The dry run's instrument. It is asserted separately because a diff that is wrong in the
/// direction of showing less is a dry run that hides the change it was printed to reveal.
@Suite("Unified diff")
struct UnifiedDiffTests {
    @Test("U1 — identical texts produce nothing at all, so a caller can say so in its own words")
    func identicalTextsProduceNothing() {
        #expect(UnifiedDiff.between("a\nb\n", "a\nb\n", fromLabel: "x", toLabel: "y").isEmpty)
    }

    @Test("U2 — an insertion is marked, and the surrounding context is carried with it")
    func anInsertionIsMarkedWithContext() {
        let out = UnifiedDiff.between("a\nb\nc\n", "a\nb\nNEW\nc\n", fromLabel: "x", toLabel: "y")
        #expect(out.contains("+NEW"))
        #expect(out.contains(" a"))
        #expect(out.contains("--- x"))
        #expect(out.contains("+++ y"))
    }

    @Test("U3 — a replacement is one removal and one addition, not a silent substitution")
    func aReplacementShowsBothSides() {
        let out = UnifiedDiff.between("a\nold\nc\n", "a\nnew\nc\n", fromLabel: "x", toLabel: "y")
        #expect(out.contains("-old"))
        #expect(out.contains("+new"))
    }

    /// Two changes far apart are two hunks; two changes close together are one. A renderer that got
    /// this wrong would print the whole file for a one-line change, which is a diff nobody reads.
    @Test("U4 — distant changes are separate hunks and near ones are merged")
    func hunksSplitOnDistanceAndMergeOnProximity() {
        let old = (1 ... 30).map(String.init).joined(separator: "\n")
        var far = old.components(separatedBy: "\n")
        far[1] = "X"
        far[28] = "Y"
        let split = UnifiedDiff.between(
            old, far.joined(separator: "\n"), fromLabel: "x", toLabel: "y"
        )
        #expect(split.components(separatedBy: "@@ -").count - 1 == 2)

        var near = old.components(separatedBy: "\n")
        near[10] = "X"
        near[12] = "Y"
        let merged = UnifiedDiff.between(
            old, near.joined(separator: "\n"), fromLabel: "x", toLabel: "y"
        )
        #expect(merged.components(separatedBy: "@@ -").count - 1 == 1)
    }

    /// The hunk header for a pure insertion has a zero-length old range, and the unified format
    /// starts it at the line before. A diff that gets this wrong reads correctly and will not apply.
    @Test("U5 — a pure insertion's old range is zero-length and starts at the preceding line")
    func aPureInsertionHasAZeroLengthOldRange() {
        let out = UnifiedDiff.between("", "a\n", fromLabel: "x", toLabel: "y")
        #expect(out.contains("+a"))
        let header = out.components(separatedBy: "\n").first { $0.hasPrefix("@@") }
        #expect(header != nil)
    }
}
