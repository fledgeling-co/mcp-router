import Foundation
import Testing
@testable import RouterCore

/// F8 — reading a harness's skills directory.
///
/// Every root here is built under a scratch directory by this suite. **No test reads a real
/// harness tree**, which is the discipline `div-m22-harnesses` records for `GET /harnesses` and the
/// reason `DiskSkillRoots` takes its home directory as a parameter.
///
/// The state the item exists for — a symlink whose target has been deleted — is one a developer's
/// own `$HOME` produces by accident and never on request. It is produced here on purpose, and the
/// same assertion is watched reporting `linked` first, so it cannot be a constant.
@Suite("F8 — harness skill roots")
struct SkillRootInventoryTests {
    private static func scratch() -> String {
        NSTemporaryDirectory() + "mcprouter-f8-roots-" + UUID().uuidString
    }

    private static func makeDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private static func location(_ path: String) -> SkillRootLocation {
        SkillRootLocation(
            client: .cursor, path: path, provenance: .walked(reading: "built by this test")
        )
    }

    /// A3 — the same call reports `linked` and then `dangling` for the same entry.
    ///
    /// Watched failing in both directions: with the target present the assertion for `dangling`
    /// fails, and with it removed the assertion for `linked` fails. Neither can hold vacuously.
    @Test("S1 a link reads linked while its target exists and dangling once it does not")
    func danglingIsMeasuredNotAssumed() throws {
        let scratch = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        let root = (scratch as NSString).appendingPathComponent("skills")
        let target = (scratch as NSString).appendingPathComponent("real-skill")
        try Self.makeDirectory(root)
        try Self.makeDirectory(target)
        let link = (root as NSString).appendingPathComponent("design-craft")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)

        let before = DiskSkillRoots.read(Self.location(root))
        #expect(before.danglingCount == 0)
        guard case let .linked(resolved) = try #require(before.entry(named: "design-craft")).kind
        else {
            Issue.record("a live link did not read as linked"); return
        }
        #expect(resolved == (target as NSString).standardizingPath)

        try FileManager.default.removeItem(atPath: target)

        let after = DiskSkillRoots.read(Self.location(root))
        #expect(after.danglingCount == 1)
        guard case let .dangling(stillClaims) = try #require(
            after.entry(named: "design-craft")
        ).kind else {
            Issue.record("a broken link did not read as dangling"); return
        }
        // The target is still reported, because a repair has a known destination and an install
        // does not. Reporting a dangling link as absent would offer the wrong fix.
        #expect(stillClaims == (target as NSString).standardizingPath)
        // And it still occupies its name, which is why the projection repairs rather than adds.
        #expect(after.names.contains("design-craft"))
    }

    /// A3 — a relative link is resolved against its own directory, not against the process's cwd.
    @Test("S2 a relative symlink resolves against the directory holding it")
    func relativeLinkResolves() throws {
        let scratch = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        let root = (scratch as NSString).appendingPathComponent("skills")
        try Self.makeDirectory(root)
        try Self.makeDirectory((scratch as NSString).appendingPathComponent("elsewhere"))
        try FileManager.default.createSymbolicLink(
            atPath: (root as NSString).appendingPathComponent("near"),
            withDestinationPath: "../elsewhere"
        )
        let inventory = DiskSkillRoots.read(Self.location(root))
        guard case .linked = try #require(inventory.entry(named: "near")).kind else {
            Issue.record("a relative link to a directory that exists read as dangling"); return
        }
    }

    /// A4 — an absent root and an empty root are different readings from the same call.
    @Test("S3 a root that does not exist is not the same as a root holding nothing")
    func absentIsNotEmpty() throws {
        let scratch = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        let empty = (scratch as NSString).appendingPathComponent("empty")
        try Self.makeDirectory(empty)

        let missing = DiskSkillRoots.read(
            Self.location((scratch as NSString).appendingPathComponent("nowhere"))
        )
        let present = DiskSkillRoots.read(Self.location(empty))
        #expect(missing.exists == false)
        #expect(present.exists == true)
        // Both hold no entries, so `entries.isEmpty` alone cannot tell them apart — which is the
        // whole reason `exists` is on the type.
        #expect(missing.entries.isEmpty)
        #expect(present.entries.isEmpty)
    }

    /// A real directory and a stray file are both reported, and neither is a link.
    @Test("S4 a real directory reads as a directory and a stray file as other")
    func directoriesAndStrays() throws {
        let scratch = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: scratch) }
        let root = (scratch as NSString).appendingPathComponent("skills")
        try Self.makeDirectory((root as NSString).appendingPathComponent("real"))
        try Data("x".utf8).write(
            to: URL(fileURLWithPath: (root as NSString).appendingPathComponent("stray.txt"))
        )
        // A dotted entry is the operating system's litter and is not an entry.
        try Data("x".utf8).write(
            to: URL(fileURLWithPath: (root as NSString).appendingPathComponent(".DS_Store"))
        )

        let inventory = DiskSkillRoots.read(Self.location(root))
        #expect(inventory.names == ["real", "stray.txt"])
        #expect(try #require(inventory.entry(named: "real")).kind == .directory)
        #expect(try #require(inventory.entry(named: "stray.txt")).kind == .other)
        #expect(inventory.danglingCount == 0)
    }

    /// The location table names two roots for Cursor and one shared between Codex and ChatGPT, and
    /// the clients with no root are **derived** from it rather than written down twice.
    @Test("S5 the root table is consistent with the clients it says have none")
    func tableAndAbsencesAgree() {
        let home = "/scratch-home"
        let all = SkillRootLocation.all(homeDirectory: home)
        let cursor = all.filter { $0.client == .cursor }
        #expect(cursor.count == 2)
        #expect(Set(cursor.map(\.identifier)) == ["cursor.linked", "cursor.native"])

        let codex = try? #require(all.first { $0.client == .codexCLI })
        let chatGPT = try? #require(all.first { $0.client == .chatGPTCLI })
        #expect(codex?.path == chatGPT?.path)
        guard case .sharedWith = chatGPT?.provenance else {
            Issue.record("the shared root does not record that it is shared"); return
        }

        let without = Set(SkillRootLocation.clientsWithoutRoot(homeDirectory: home))
        #expect(without == [.claudeDesktop, .grokCLI])
        // Derived rather than declared: no client is both covered and uncovered, and none is
        // neither, so the partition over `MCPClient.allCases` is total.
        let covered = Set(all.map(\.client))
        #expect(covered.isDisjoint(with: without))
        #expect(covered.union(without) == Set(MCPClient.allCases))
    }
}
