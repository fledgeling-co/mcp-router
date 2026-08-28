import Foundation
import Testing
@testable import RouterCore

/// R30 — the scan, and the settings writer, against a fixture tree and never against the real one.
///
/// Every test here builds its own `~/.claude`-shaped directory under `NSTemporaryDirectory()` and
/// deletes it afterwards. ``ClaudeFixtureTree`` records what the real tree looks like and what was
/// reproduced from it; no path in this file resolves anywhere near `~/.claude`. The apply, undo and
/// manifest halves are in `ExtensionIngestApplyTests.swift`.
@Suite("R30 — scanning what Claude acquired")
struct ExtensionIngestTests {
    @Test("G1 — the scan finds every identifiable entry and names the identity Claude uses")
    func scanFindsCandidates() {
        let bench = IngestBench("scan")
        defer { bench.tearDown() }
        let scan = bench.scan()

        #expect(scan.unreadableRegisters.isEmpty)
        #expect(scan.candidates.map(\.name).sorted() == [
            "claude-code-plugins", "code-review@claude-code-plugins",
            "code-review@fledgeling-plugins", "fledgeling-plugins", "graphify", "mermaid-diagrams"
        ])
        // The whole reason `@` is in a name. Two plugins called `code-review` from two
        // marketplaces both survive; a store keyed on the bare name would hold one.
        let reviews = scan.candidates.filter { $0.name.hasPrefix("code-review") }
        #expect(reviews.count == 2)
        #expect(Set(reviews.compactMap(\.version)) == ["2.1.0", "1.4.2"])
        #expect(reviews.allSatisfy { $0.settingsKey == $0.name })
    }

    @Test("G2 — what cannot be identified is reported and is still on disk afterwards")
    func scanLeavesTheUnidentifiable() {
        let bench = IngestBench("blocked")
        defer { bench.tearDown() }
        let scan = bench.scan()

        #expect(scan.blocked.map { "\($0.name):\($0.reason)" }.sorted() == [
            "half-installed:unreadableDescriptor",
            "studio-proxy@fledgeling-plugins:sourceMissing",
            "swift-lsp@fledgeling-plugins:unreadableDescriptor"
        ])
        // The clause is not "it was reported" — it is "it was left alone". So look at the disk.
        #expect(FileManager.default.fileExists(
            atPath: "\(bench.claude.root)/skills/half-installed/README.md"
        ))
        #expect(FileManager.default.fileExists(
            atPath: "\(bench.claude.root)/plugins/cache/fledgeling-plugins/swift-lsp/1.0.0/README.md"
        ))
    }

    @Test("G3 — a tree touched inside the settle window is not a candidate")
    func scanRefusesAnUnsettledTree() {
        let bench = IngestBench("settle")
        defer { bench.tearDown() }
        // Real `now` rather than the bench's hour ahead: the fixture was written seconds ago, so
        // every entry is inside a 60s window.
        let now = Date().timeIntervalSince1970 * 1000
        let scan = ClaudeExtensionScan.scan(
            tree: bench.claude, store: bench.store, settleMilliseconds: 60000, now: now
        )
        #expect(scan.candidates.isEmpty)
        #expect(scan.blocked.filter { $0.reason == "notSettled" }.count == 6)

        // The presence control for that zero: with the window at nothing, the same tree yields the
        // same six candidates. A scan returning nothing because it was looking in the wrong place
        // would return nothing here too.
        let open = ClaudeExtensionScan.scan(
            tree: bench.claude, store: bench.store, settleMilliseconds: 0, now: now
        )
        #expect(open.candidates.count == 6)
    }

    @Test("G4 — a name the router already holds is refused rather than merged")
    func scanRefusesADuplicate() {
        let bench = IngestBench("duplicate")
        defer { bench.tearDown() }
        _ = bench.store.add(.skills, name: "graphify", files: [ExtensionFile(
            path: "SKILL.md", text: "---\nname: graphify\ndescription: another one\n---\n"
        )])
        let scan = bench.scan()
        #expect(!scan.candidates.contains { $0.name == "graphify" })
        #expect(scan.blocked.contains { $0.name == "graphify" && $0.reason == "alreadyInRouter" })
    }

    @Test("G5 — the scan writes nothing")
    func scanIsReadOnly() {
        let bench = IngestBench("readonly")
        defer { bench.tearDown() }
        let before = ExtensionStamp.measure(bench.claude.root)
        _ = bench.scan()
        #expect(ExtensionStamp.measure(bench.claude.root)?.digest == before?.digest)
        #expect(!FileManager.default.fileExists(atPath: bench.store.root))
    }

    // MARK: - The settings writer, on its own

    @Test("G8 — a settings edit with nothing to remove leaves the file byte-identical")
    func settingsNoOpWritesNothing() throws {
        let bench = IngestBench("noop")
        defer { bench.tearDown() }
        let path = bench.claude.settingsPath
        let before = try Data(contentsOf: URL(fileURLWithPath: path))
        let result = try ClaudeSettingsEdit.remove(
            [ClaudeSettingsEdit.KeyRemoval(container: "enabledPlugins", key: "not-installed@x")],
            to: bench.settingsDestination(), fileSystem: RealFileSystem()
        )
        #expect(!result.wrote)
        #expect(result.absent.count == 1)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)

        // The presence control: the same call with a key that IS there does write, so the
        // byte-equality above is a property of the no-op rather than of a writer that never fires.
        let real = try ClaudeSettingsEdit.remove(
            [ClaudeSettingsEdit.KeyRemoval(
                container: "enabledPlugins", key: "code-review@fledgeling-plugins"
            )],
            to: bench.settingsDestination(), fileSystem: RealFileSystem()
        )
        #expect(real.wrote)
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) != before)
    }

    @Test("G9 — a settings file that is not JSON is not rewritten")
    func settingsRefusesAnUnparsableFile() throws {
        let bench = IngestBench("unparsable")
        defer { bench.tearDown() }
        let path = bench.claude.settingsPath
        ClaudeFixtureTree.write("{ this is not json", to: path)
        #expect(throws: ClaudeSettingsEdit.Failure.self) {
            _ = try ClaudeSettingsEdit.remove(
                [ClaudeSettingsEdit.KeyRemoval(container: "enabledPlugins", key: "a@b")],
                to: bench.settingsDestination(), fileSystem: RealFileSystem()
            )
        }
        #expect(try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            == "{ this is not json")
    }

    @Test("G15 — two keys out of one container come back in their original order")
    func settingsRestoresOrder() throws {
        let bench = IngestBench("order")
        defer { bench.tearDown() }
        let path = bench.claude.settingsPath
        let before = ClaudeFixtureTree.settingsMember("enabledPlugins", at: path)

        // Removed in the order the ingest would remove them, which is NOT the order they sit in.
        // Each index is recorded against an array the previous removal already shortened, so a
        // forward restore puts the second key back in the first one's place.
        let result = try ClaudeSettingsEdit.remove(
            [
                ClaudeSettingsEdit.KeyRemoval(
                    container: "enabledPlugins", key: "code-review@claude-code-plugins"
                ),
                ClaudeSettingsEdit.KeyRemoval(
                    container: "enabledPlugins", key: "code-review@fledgeling-plugins"
                )
            ],
            to: bench.settingsDestination(), fileSystem: RealFileSystem()
        )
        #expect(result.removed.map(\.index) == [1, 0])
        #expect(ClaudeFixtureTree.settingsMember("enabledPlugins", at: path)
            == "{\"swift-lsp@fledgeling-plugins\":true}")

        let restored = try ClaudeSettingsEdit.restore(
            result.removed, to: bench.settingsDestination(), fileSystem: RealFileSystem()
        )
        #expect(restored == 2)
        // Order, not just membership: `settingsMember` compacts the parsed value, which keeps
        // member order, so this comparison fails on a reordering that keeps every key.
        #expect(ClaudeFixtureTree.settingsMember("enabledPlugins", at: path) == before)
    }

    // MARK: - The stamp, which every verify rests on

    @Test("G14 — the stamp changes when a byte does, and not when a read repeats")
    func stampIsAnOracle() {
        let root = NSTemporaryDirectory() + "mcprouter-r30-print-" + UUID().uuidString
        defer { try? FileManager.default.removeItem(atPath: root) }
        ClaudeFixtureTree.skill("alpha", at: root, description: "one", extra: "docs/more.md")
        let directory = "\(root)/skills/alpha"

        let first = ExtensionStamp.measure(directory)
        #expect(first?.files == 2)
        #expect(ExtensionStamp.measure(directory)?.digest == first?.digest)

        // One byte changed with the file's length held constant, so size alone cannot see it.
        ClaudeFixtureTree.write(
            "---\nname: alpha\ndescription: two\n---\n\n# alpha\n", to: "\(directory)/SKILL.md"
        )
        #expect(ExtensionStamp.measure(directory)?.digest != first?.digest)
        #expect(ExtensionStamp.measure("\(root)/skills/nothing-here") == nil)
    }
}
