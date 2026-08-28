import Foundation
import Testing
@testable import RouterCore

/// R28 — ``DiskExtensionStore`` against a **real** directory.
///
/// Real rather than the in-memory double, and the choice is the subject rather than convenience:
/// an entry is a directory tree, `MemoryFileSystem.contentsOfDirectory` lists only the files
/// immediately under a prefix, and its `moveItem` moves one file. A store proven against it would
/// be proven against something that is not a directory tree — and the property this item is asked
/// for is that a `GET` reports what is on **disk**, which nothing in memory can stand for.
@Suite("R28 — the extension store on disk")
struct ExtensionStoreTests {
    /// A scratch root per test, removed afterwards. Nothing outside it is touched, which is also
    /// the guarantee the store itself makes.
    private static func scratch() -> String {
        NSTemporaryDirectory() + "mcprouter-r28-" + UUID().uuidString
    }

    private static func skill(
        _ name: String, description: String = "does a thing"
    ) -> [ExtensionFile] {
        [ExtensionFile(
            path: "SKILL.md",
            text: "---\nname: \(name)\ndescription: \(description)\n---\n\n# \(name)\n"
        )]
    }

    private static func plugin(_ name: String) -> [ExtensionFile] {
        [ExtensionFile(
            path: ".claude-plugin/plugin.json",
            text: "{\"name\":\"\(name)\",\"description\":\"a plugin\"}"
        )]
    }

    private static func marketplace(_ name: String) -> [ExtensionFile] {
        [ExtensionFile(
            path: ".claude-plugin/marketplace.json",
            text: "{\"name\":\"\(name)\",\"owner\":{\"name\":\"someone\"},\"plugins\":[]}"
        )]
    }

    private static func files(_ kind: ExtensionKind, _ name: String) -> [ExtensionFile] {
        switch kind {
        case .skills: skill(name)
        case .plugins: plugin(name)
        case .marketplaces: marketplace(name)
        }
    }

    // MARK: - The round trip, per kind

    @Test("E1 — every kind can be added, listed, read and removed", arguments: ExtensionKind.allCases)
    func roundTrip(kind: ExtensionKind) {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = DiskExtensionStore(root: root, clock: FixedMillisecondClock(1000))

        #expect(store.list(kind).records.isEmpty)
        guard case let .added(record) = store.add(kind, name: "alpha", files: Self.files(kind, "alpha"))
        else {
            Issue.record("adding a well-formed \(kind.singular) was refused")
            return
        }
        #expect(record.name == "alpha")
        #expect(record.title == "alpha")
        #expect(record.problem == nil)
        #expect(record.files == 1)
        #expect(record.bytes > 0)

        let listing = store.list(kind)
        #expect(listing.records.map(\.name) == ["alpha"])
        #expect(listing.unreadable == nil)
        #expect(store.read(kind, name: "alpha")?.title == "alpha")

        guard case let .removed(path) = store.remove(kind, name: "alpha") else {
            Issue.record("removing an entry that exists was refused")
            return
        }
        #expect(store.list(kind).records.isEmpty)
        #expect(store.read(kind, name: "alpha") == nil)
        // Reversible: the bytes are still there, at the path the outcome named.
        let descriptor = (path as NSString).appendingPathComponent(kind.descriptorPath)
        #expect(FileManager.default.fileExists(atPath: descriptor))
    }

    // MARK: - The reading is of the disk

    @Test("E2 — an entry written behind the store's back is listed; one deleted is gone")
    func listingFollowsDisk() throws {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = DiskExtensionStore(root: root, clock: FixedMillisecondClock(1000))
        _ = store.add(.skills, name: "alpha", files: Self.skill("alpha"))

        // Nothing here goes through the store. This is the `GET /servers` lesson applied: the
        // reading is the live state, so a change the router did not make still shows up.
        let manual = root + "/skills/beta"
        try FileManager.default.createDirectory(atPath: manual, withIntermediateDirectories: true)
        try Data("---\nname: beta\ndescription: hand written\n---\n".utf8)
            .write(to: URL(fileURLWithPath: manual + "/SKILL.md"))
        #expect(store.list(.skills).records.map(\.name) == ["alpha", "beta"])
        #expect(store.read(.skills, name: "beta")?.description == "hand written")

        try FileManager.default.removeItem(atPath: root + "/skills/alpha")
        #expect(store.list(.skills).records.map(\.name) == ["beta"])
    }

    @Test("E3 — a descriptor that rots after the add is listed with the problem, not dropped")
    func rottedDescriptorIsStillCounted() throws {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = DiskExtensionStore(root: root, clock: FixedMillisecondClock(1000))
        _ = store.add(.plugins, name: "alpha", files: Self.plugin("alpha"))

        try Data("{ not json".utf8).write(
            to: URL(fileURLWithPath: root + "/plugins/alpha/.claude-plugin/plugin.json")
        )
        let listing = store.list(.plugins)
        // Counted, because the count is the number this route exists to answer, and an entry the
        // router cannot read is still an entry the router is holding.
        #expect(listing.records.count == 1)
        #expect(listing.records[0].title == nil)
        #expect(listing.records[0].problem?.contains("is not valid JSON") == true)
    }

    @Test("E4 — an empty store and an absent one both read as zero, and neither is unreadable")
    func absentStoreIsEmptyRatherThanBroken() {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = DiskExtensionStore(root: root, clock: FixedMillisecondClock(1000))
        for kind in ExtensionKind.allCases {
            #expect(store.list(kind).records.isEmpty)
            #expect(store.list(kind).unreadable == nil)
        }
    }

    // MARK: - Refused rather than half-registered

    @Test("E5 — every malformed add is refused and leaves nothing on disk", arguments: [
        // path escapes, the two shapes that would reach outside the entry
        MalformedAdd("bad", [ExtensionFile(path: "../escape.md", text: "x")], "invalidFilePath"),
        MalformedAdd("bad", [ExtensionFile(path: "/etc/passwd", text: "x")], "invalidFilePath"),
        // a name that is not a name
        MalformedAdd("../evil", [ExtensionFile(path: "SKILL.md", text: "x")], "invalidName"),
        MalformedAdd(".removed", [ExtensionFile(path: "SKILL.md", text: "x")], "invalidName"),
        MalformedAdd("", [ExtensionFile(path: "SKILL.md", text: "x")], "invalidName"),
        // nothing to write
        MalformedAdd("bad", [], "noFiles"),
        // the descriptor is absent, unopened, unclosed, or names something else
        MalformedAdd("bad", [ExtensionFile(path: "README.md", text: "x")], "missingDescriptor"),
        MalformedAdd("bad", [ExtensionFile(path: "SKILL.md", text: "no ---")], "malformedDescriptor"),
        MalformedAdd(
            "bad",
            [ExtensionFile(path: "SKILL.md", text: "---\nname: bad\n")],
            "malformedDescriptor"
        ),
        MalformedAdd(
            "bad",
            [ExtensionFile(path: "SKILL.md", text: "---\ndescription: d\n---\n")],
            "malformedDescriptor"
        ),
        MalformedAdd(
            "bad",
            [ExtensionFile(path: "SKILL.md", text: "---\nname: other\n---\n")],
            "nameMismatch"
        ),
        // one path given twice: the second copy would silently win
        MalformedAdd("bad", [
            ExtensionFile(path: "SKILL.md", text: "---\nname: bad\n---\n"),
            ExtensionFile(path: "SKILL.md", text: "---\nname: bad\n---\n")
        ], "duplicateFilePath")
    ])
    func malformedAddsAreRefusedWhole(argument: MalformedAdd) {
        let (name, files, reason) = (argument.name, argument.files, argument.reason)
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = DiskExtensionStore(root: root, clock: FixedMillisecondClock(1000))

        guard case let .refused(refusal) = store.add(.skills, name: name, files: files) else {
            Issue.record("\"\(name)\" with \(files.count) file(s) was accepted; expected \(reason)")
            return
        }
        #expect(refusal.reason == reason)
        #expect(refusal.status == 400)
        // Half-registered is the failure this ordering exists to prevent: nothing under the kind
        // directory, and nothing left staged either.
        #expect(store.list(.skills).records.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root + "/.staging"))
    }

    @Test("E6 — a second add under one name is 409 and does not overwrite the first")
    func duplicateNameIsRefused() {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = DiskExtensionStore(root: root, clock: FixedMillisecondClock(1000))
        _ = store.add(.skills, name: "alpha", files: Self.skill("alpha", description: "first"))

        guard case let .refused(refusal) = store.add(
            .skills, name: "alpha", files: Self.skill("alpha", description: "second")
        ) else {
            Issue.record("a duplicate name was accepted")
            return
        }
        #expect(refusal.status == 409)
        #expect(refusal.reason == "nameTaken")
        #expect(store.read(.skills, name: "alpha")?.description == "first")
    }

    @Test("E7 — removing something that is not there is 404, and removes nothing")
    func unknownRemovalIsRefused() {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = DiskExtensionStore(root: root, clock: FixedMillisecondClock(1000))
        _ = store.add(.skills, name: "alpha", files: Self.skill("alpha"))

        guard case let .refused(refusal) = store.remove(.skills, name: "ghost") else {
            Issue.record("removing an unknown entry reported a removal")
            return
        }
        #expect(refusal.status == 404)
        #expect(refusal.message == "no skill named \"ghost\"")
        #expect(store.list(.skills).records.count == 1)
    }

    @Test("E8 — two removals of one name keep both copies rather than the second burying the first")
    func removalsDoNotOverwriteEachOther() {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let clock = SteppingMillisecondClock(start: 1000, step: 1000)
        let store = DiskExtensionStore(root: root, clock: clock)

        _ = store.add(.skills, name: "alpha", files: Self.skill("alpha", description: "first"))
        guard case let .removed(first) = store.remove(.skills, name: "alpha") else {
            Issue.record("the first removal was refused"); return
        }
        _ = store.add(.skills, name: "alpha", files: Self.skill("alpha", description: "second"))
        guard case let .removed(second) = store.remove(.skills, name: "alpha") else {
            Issue.record("the second removal was refused"); return
        }
        #expect(first != second)
        #expect(FileManager.default.fileExists(atPath: first + "/SKILL.md"))
        #expect(FileManager.default.fileExists(atPath: second + "/SKILL.md"))
    }
}

/// One malformed add and the slug it must be refused with.
///
/// A named type rather than a three-member tuple, because SwiftLint's `large_tuple` caps a tuple
/// at two — and the cap is right here: the three read as a case rather than as a pair.
struct MalformedAdd: Sendable {
    let name: String
    let files: [ExtensionFile]
    let reason: String

    init(_ name: String, _ files: [ExtensionFile], _ reason: String) {
        self.name = name
        self.files = files
        self.reason = reason
    }
}

/// A clock that never moves, for the tests whose subject is not time.
struct FixedMillisecondClock: RouterClock {
    let value: Double

    init(_ value: Double) {
        self.value = value
    }

    var nowMilliseconds: Double { value }
}

/// A clock that advances one step per read — what a second removal of the same name needs, since
/// the destination is stamped with the millisecond it happened at.
final class SteppingMillisecondClock: RouterClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Double
    private let step: Double

    init(start: Double, step: Double) {
        current = start
        self.step = step
    }

    var nowMilliseconds: Double {
        lock.lock()
        defer { lock.unlock() }
        current += step
        return current
    }
}
