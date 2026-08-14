import Foundation
import Testing
@testable import MCPRouterKit

/// The two persisted sets on this phone, and the one failure they must never present as emptiness.
///
/// `Undecided = results − queued − dismissed` (A7), so a dismissal file that will not decode
/// silently re-populates Undecided with everything the user already turned down — and a queue file
/// that will not decode presents an empty outbox to someone who queued five things. Both are the
/// failure-mode-is-emptiness defect `SWIFT_PRACTICES.md` §2 records from this repo's own TypeScript
/// router, where a flat `servers.json` loaded zero servers with no error at all.
///
/// The two stores are asserted **together**, on the same corrupt bytes, because A9's whole point is
/// that the dismissal set fails the way the queue does. Two suites would let them drift.
@Suite("Persisted decisions: the queue and the dismissal set")
struct DismissalStoreTests {
    /// A fresh directory per test. Not `deinit`-cleaned: a leaked temporary directory is harmless,
    /// and a test that deletes state while an actor still holds it is not.
    static func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("i3-store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func item(
        _ id: String,
        at date: Date = Date(timeIntervalSince1970: 1_000_000)
    ) -> DismissedCapability {
        DismissedCapability(id: id, displayName: id.capitalized, dismissedAt: date)
    }

    // MARK: - A9: the one honest emptiness

    @Test("a missing file is an empty set, which is the only honest emptiness")
    func missingFileIsEmpty() async throws {
        let store = try FileDismissalStore(directory: Self.directory())
        #expect(try await store.all().isEmpty)
    }

    // MARK: - A9 / A17: a present file that will not decode is never an empty set

    @Test("a corrupt dismissal file is unreadable, never an empty set")
    func corruptDismissalFileIsUnreadable() async throws {
        let dir = try Self.directory()
        try Data("this is not JSON".utf8)
            .write(to: dir.appendingPathComponent("dismissed-capabilities.json"))

        let store = FileDismissalStore(directory: dir)

        await #expect(throws: DismissalStoreError.self) {
            _ = try await store.all()
        }
    }

    /// The mirror assertion. Both stores are handed the **same corrupt bytes** and both must refuse
    /// to answer with an empty collection — if one ever degrades to `[]` the two have drifted, and
    /// the one that drifted is the one nobody would think to check.
    @Test("the queue and the dismissal set treat a corrupt file identically")
    func bothStoresFailTheSameWay() async throws {
        let dir = try Self.directory()
        let corrupt = Data("{ not an array".utf8)
        try corrupt.write(to: dir.appendingPathComponent("dismissed-capabilities.json"))
        try corrupt.write(to: dir.appendingPathComponent("capability-queue.json"))

        let dismissals = FileDismissalStore(directory: dir)
        let queue = FileCapabilityQueueWriter(directory: dir)

        var dismissalsThrew = false
        var queueThrew = false
        do { _ = try await dismissals.all() } catch { dismissalsThrew = true }
        do { _ = try await queue.all() } catch { queueThrew = true }

        #expect(dismissalsThrew, "the dismissal set answered a corrupt file without throwing")
        #expect(queueThrew, "the queue answered a corrupt file without throwing")
    }

    /// A well-formed JSON document of the wrong shape is the actual failure a format change
    /// produces — not garbage bytes. It must be as loud.
    @Test("a well-formed document of the wrong shape is still unreadable")
    func wrongShapeIsUnreadable() async throws {
        let dir = try Self.directory()
        try Data(#"{"dismissed":[]}"#.utf8)
            .write(to: dir.appendingPathComponent("dismissed-capabilities.json"))

        let store = FileDismissalStore(directory: dir)
        await #expect(throws: DismissalStoreError.self) {
            _ = try await store.all()
        }
    }

    // MARK: - A9: a dismissal persists, and is reversible from its home

    @Test("a dismissal survives a relaunch")
    func survivesRelaunch() async throws {
        let dir = try Self.directory()

        let first = FileDismissalStore(directory: dir)
        try await first.dismiss(Self.item("official:one"))

        // A second store over the same directory is what a relaunch is.
        let second = FileDismissalStore(directory: dir)
        let items = try await second.all()

        #expect(items.map(\.id) == ["official:one"])
    }

    @Test("a restore removes it, and survives a relaunch too")
    func restoreSurvivesRelaunch() async throws {
        let dir = try Self.directory()

        let first = FileDismissalStore(directory: dir)
        try await first.dismiss(Self.item("official:one"))
        try await first.dismiss(Self.item("official:two"))
        try await first.restore("official:one")

        let second = FileDismissalStore(directory: dir)
        #expect(try await second.all().map(\.id) == ["official:two"])
    }

    /// Dismissing twice must not produce two rows, and the **original** stamp is kept: the fact
    /// worth recording is when the user first turned it down.
    @Test("dismissing twice is idempotent and keeps the first stamp")
    func dismissIsIdempotent() async throws {
        let dir = try Self.directory()
        let store = FileDismissalStore(directory: dir)
        let first = Date(timeIntervalSince1970: 1_000_000)
        let later = Date(timeIntervalSince1970: 2_000_000)

        try await store.dismiss(Self.item("official:one", at: first))
        try await store.dismiss(Self.item("official:one", at: later))

        let items = try await store.all()
        #expect(items.count == 1)
        #expect(items[0].dismissedAt == first, "a second dismissal overwrote the original stamp")
    }

    /// The surface offers restore only on rows that are dismissed, so a mismatch means the set
    /// changed underneath — failing there would surface a fault the user cannot act on.
    @Test("restoring something that was never dismissed is a no-op, not an error")
    func restoreUnknownIsNoOp() async throws {
        let store = try FileDismissalStore(directory: Self.directory())
        try await store.dismiss(Self.item("official:one"))
        try await store.restore("official:nothing")
        #expect(try await store.all().count == 1)
    }

    // MARK: - A14: a refused write is a failure, never a silent success

    @Test("a refused write throws and stores nothing")
    func refusedWriteThrows() async throws {
        let store = InMemoryDismissalStore(failure: .writeFailed("no space"))

        await #expect(throws: DismissalStoreError.self) {
            try await store.dismiss(Self.item("official:one"))
        }
        #expect(try await store.all().isEmpty)
    }

    /// A refused write and an unreadable file are two different faults, and a double that conflates
    /// them cannot express "the write was refused and nothing was stored" — the merged
    /// `InMemoryCapabilityQueue` carries the same two flags for the same reason.
    @Test("the read failure and the write failure are separate faults")
    func readAndWriteFailuresAreSeparate() async throws {
        let readOnly = InMemoryDismissalStore(readFailure: .unreadable("corrupt"))
        await #expect(throws: DismissalStoreError.self) { _ = try await readOnly.all() }
        // The write is not refused, so it must succeed.
        try await readOnly.dismiss(Self.item("official:one"))

        let writeOnly = InMemoryDismissalStore(failure: .writeFailed("refused"))
        #expect(try await writeOnly.all().isEmpty)
    }

    // MARK: - A19: the queue's stored format is unchanged from what I2 shipped

    /// No Mac-side field is added. Adding a status column now would be designing a status
    /// vocabulary against a wire that does not exist.
    @Test("the queue file is still a bare array of queued capabilities")
    func queueFormatIsUnchanged() async throws {
        let dir = try Self.directory()
        let queue = FileCapabilityQueueWriter(directory: dir)
        try await queue.enqueue(QueuedCapability(entry: TriageSpecimens.stdio))

        let data = try Data(contentsOf: dir.appendingPathComponent("capability-queue.json"))
        let json = try JSONSerialization.jsonObject(with: data)

        let array = try #require(json as? [[String: Any]])
        #expect(array.count == 1)
        #expect(array[0]["id"] as? String == TriageSpecimens.stdio.id)
        for forbidden in ["status", "state", "acceptedAt", "seenAt", "sentAt"] {
            #expect(array[0][forbidden] == nil, "a Mac-side field reached the queue format: \(forbidden)")
        }
    }

    /// A19's widening, asserted rather than assumed: the reader has to be able to *fail*, or the
    /// unreadable state A17 calls the most important on the surface is undrivable from a test.
    @Test("the in-memory queue can be made to fail its read")
    func inMemoryQueueCanFailItsRead() async throws {
        let queue = InMemoryCapabilityQueue(readFailure: .unreadable("corrupt"))
        await #expect(throws: CapabilityQueueError.self) {
            _ = try await queue.all()
        }
    }
}
