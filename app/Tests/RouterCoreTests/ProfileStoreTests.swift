import Foundation
import Testing
@testable import RouterCore

/// F8 — ``DiskProfileStore`` against a **real** directory.
///
/// Real rather than the in-memory double, for the reason `ExtensionStoreTests` gives: the property
/// asked for is that a read reports what is on disk, and nothing in memory can stand for that. A
/// scratch root per test, removed afterwards; nothing outside it is touched, which is also the
/// guarantee the store itself makes.
@Suite("F8 — the profile store on disk")
struct ProfileStoreTests {
    private static func scratch() -> String {
        NSTemporaryDirectory() + "mcprouter-f8-" + UUID().uuidString
    }

    private static func store(_ root: String) -> DiskProfileStore {
        DiskProfileStore(root: root, clock: PinnedClock(nowMilliseconds: 1_700_000_000_000))
    }

    private static func names(_ listing: ProfileListing) -> [String] {
        listing.rows.map(\.name)
    }

    /// A1 — write, read, list.
    @Test("P1 a written profile is listed and reads back with its selection")
    func writeThenRead() throws {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = Self.store(root)

        #expect(Self.names(store.list()).isEmpty)
        let record = ProfileRecord(
            name: "frontend", title: "Frontend Dev",
            servers: ["github"], skills: ["design-craft", "ux-craft"], plugins: ["pixel-plugin"]
        )
        guard case let .written(written) = store.write(record) else {
            Issue.record("the write was refused"); return
        }
        #expect(written.selectionCount == 4)
        #expect(Self.names(store.list()) == ["frontend"])
        let row = try #require(store.read(name: "frontend"))
        let read = try #require(row.record)
        #expect(read.title == "Frontend Dev")
        #expect(read.skills == ["design-craft", "ux-craft"])
        #expect(read.marketplaces.isEmpty)
        #expect(row.problem == nil)
    }

    /// A1 — the store nobody has written to is **empty**, not unreadable.
    ///
    /// The distinction the whole listing type exists for. Both values come out of the same call so
    /// a reader cannot get one without the other.
    @Test("P2 an absent profile directory is empty and readable, not a failure")
    func absentDirectoryIsEmpty() {
        let listing = Self.store(Self.scratch()).list()
        #expect(listing.rows.isEmpty)
        #expect(listing.unreadable == nil)
    }

    /// A1 — a profile is a selection somebody edits, so a second write replaces it.
    @Test("P3 writing an existing profile replaces it rather than being refused")
    func writeReplaces() throws {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = Self.store(root)

        _ = store.write(ProfileRecord(name: "audit", skills: ["a"]))
        guard case .written = store.write(ProfileRecord(name: "audit", skills: ["a", "b"])) else {
            Issue.record("the second write was refused"); return
        }
        #expect(Self.names(store.list()) == ["audit"])
        #expect(try #require(store.read(name: "audit")?.record).skills == ["a", "b"])
    }

    /// A1 — a removal is recoverable, and two removals of the same name keep both copies.
    @Test("P4 a removal moves the profile aside and reports where, twice over")
    func removalIsRecoverable() {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = DiskProfileStore(root: root, clock: ProfileSteppingClock(from: 1000))

        _ = store.write(ProfileRecord(name: "audit", skills: ["a"]))
        guard case let .removed(first) = store.remove(name: "audit") else {
            Issue.record("the first removal was refused"); return
        }
        #expect(FileManager.default.fileExists(atPath: first))
        #expect(Self.names(store.list()).isEmpty)

        _ = store.write(ProfileRecord(name: "audit", skills: ["b"]))
        guard case let .removed(second) = store.remove(name: "audit") else {
            Issue.record("the second removal was refused"); return
        }
        #expect(first != second)
        // Both copies survive. A stamp that collided would silently destroy the first, which is
        // exactly what "nothing is deleted" must not mean.
        #expect(FileManager.default.fileExists(atPath: first))
        #expect(FileManager.default.fileExists(atPath: second))
    }

    /// A2 — every refusal is decided before a byte is written.
    ///
    /// Each case asserts the refusal **and** that the store is unchanged and `.staging` holds
    /// nothing, because a refusal that half-wrote would pass a status check on its own.
    @Test(
        "P5 a name or a selected name that escapes the store is refused with nothing written",
        arguments: [
            ("../escape", [String]()),
            (".removed", []),
            ("", []),
            ("ok", ["../../etc/passwd"]),
            ("ok", ["has space"])
        ]
    )
    func refusalsWriteNothing(name: String, skills: [String]) {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = Self.store(root)
        _ = store.write(ProfileRecord(name: "kept", skills: ["fine"]))

        guard case let .refused(refusal) = store.write(
            ProfileRecord(name: name, skills: skills)
        ) else {
            Issue.record("\"\(name)\" with \(skills) was accepted"); return
        }
        #expect(refusal.status == 400)
        #expect(Self.names(store.list()) == ["kept"])
        let staging = (root as NSString).appendingPathComponent(".staging")
        let staged = (try? FileManager.default.contentsOfDirectory(atPath: staging)) ?? []
        #expect(staged.isEmpty)
    }

    /// A2's control: the same call with a well-formed name and selection is **accepted**.
    ///
    /// Without this the refusal test above would pass against a store that refused everything.
    @Test("P6 the control — a well-formed name and selection is accepted")
    func wellFormedIsAccepted() {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        guard case .written = Self.store(root).write(
            ProfileRecord(name: "ok", skills: ["fine-name", "also.fine", "at@marketplace"])
        ) else {
            Issue.record("a well-formed profile was refused"); return
        }
    }

    /// A profile whose file rotted is still **listed**, with its problem stated.
    ///
    /// Dropping it would report a store with a broken profile as a store with one fewer profile,
    /// and the count is the number the route exists to answer.
    @Test("P7 an unparseable profile file is listed with a problem rather than dropped")
    func brokenProfileIsListed() throws {
        let root = Self.scratch()
        defer { try? FileManager.default.removeItem(atPath: root) }
        let store = Self.store(root)
        _ = store.write(ProfileRecord(name: "good", skills: ["a"]))
        try Data("{not json".utf8).write(
            to: URL(fileURLWithPath: (root as NSString).appendingPathComponent("broken.json"))
        )

        let listing = store.list()
        #expect(Self.names(listing) == ["broken", "good"])
        let broken = try #require(listing.rows.first { $0.name == "broken" })
        #expect(broken.record == nil)
        #expect(broken.problem != nil)
        // And the good one is untouched by its neighbour's problem.
        #expect(try #require(listing.rows.first { $0.name == "good" }?.record).skills == ["a"])
    }

    /// A member that is present and is not an array of strings is a refusal, not an empty list.
    @Test("P8 a member of the wrong shape is unreadable rather than read as empty")
    func wrongShapeIsUnreadable() {
        switch ProfileDocument.read(name: "x", text: "{\"skills\": \"design-craft\"}") {
        case .read: Issue.record("a string where an array belongs was read as a selection")
        case let .unreadable(problem): #expect(problem.contains("skills"))
        }
        // The control, so the case above is about the shape and not about the reader refusing
        // everything: the array form of the same member reads.
        switch ProfileDocument.read(name: "x", text: "{\"skills\": [\"design-craft\"]}") {
        case let .read(record): #expect(record.skills == ["design-craft"])
        case let .unreadable(problem): Issue.record("a well-formed member was refused: \(problem)")
        }
    }

    /// The bytes are the encoder's, not Foundation's, and two writes of one record agree.
    @Test("P9 a profile's document has a fixed member order")
    func documentOrderIsFixed() {
        let text = JSStringify.prettyTwoSpace(
            ProfileDocument.value(ProfileRecord(name: "n", servers: ["s"], skills: ["k"]))
        )
        let order = ["name", "title", "servers", "skills", "plugins", "marketplaces"]
        var cursor = text.startIndex
        for key in order {
            guard let found = text.range(of: "\"\(key)\"", range: cursor ..< text.endIndex) else {
                Issue.record("\(key) is missing or out of order"); return
            }
            cursor = found.upperBound
        }
    }
}

/// A clock that answers a different millisecond on every read.
///
/// The suite's pinned clock cannot express P4, whose whole subject is that two removals land at two stamps.
final class ProfileSteppingClock: RouterClock, @unchecked Sendable {
    private let lock = NSLock()
    private var milliseconds: Double

    init(from milliseconds: Double) {
        self.milliseconds = milliseconds
    }

    var nowMilliseconds: Double {
        lock.lock()
        defer { lock.unlock() }
        milliseconds += 1
        return milliseconds
    }
}
