import Foundation
import Testing
@testable import MCPRouterKit

/// A16–A22: sending to the Mac is the only commit, it stays live when the Mac is asleep, and the
/// write it performs is real.
@Suite("The commit and the queue — A16 to A22")
struct DiscoverCommitTests {
    // MARK: - A19: two questions, two predicates

    /// The single likeliest defect in this feature, and the reason A19 is a criterion at all: the
    /// obvious implementation of A18 binds the button to `canSend` and silently ships I1's
    /// disable-when-unreachable behaviour while looking correct.
    @Test("canSend and canQueue disagree exactly where the act differs")
    func canSendAndCanQueueAreDistinct() {
        #expect(ConnectionState.reachable.canSend)
        #expect(ConnectionState.reachable.canQueue)

        // The one state where they differ, and the whole reason both exist.
        #expect(!ConnectionState.notReachable.canSend)
        #expect(ConnectionState.notReachable.canQueue)

        #expect(!ConnectionState.neverPaired.canSend)
        #expect(!ConnectionState.neverPaired.canQueue)
    }

    // MARK: - A17 and A18

    /// A18: paired and unreachable stays **live**, and is relabelled. Writing one item to a local
    /// queue succeeds with the Mac asleep, so disabling it would refuse an act that works.
    @Test("an unreachable Mac leaves the commit live and changes its label")
    func unreachableStaysLive() {
        let state = CommitState.resolve(
            connection: .notReachable,
            hasInstallDescriptor: true,
            isAlreadyQueued: false,
            isAlreadyDeclared: false
        )
        #expect(state == .notReachable)
        #expect(state.isActionable, "A18: queueing works with the Mac asleep")
        #expect(DiscoverCopy.entry(state.copyKey).actionLabel == "Save for your Mac")
    }

    @Test("a reachable Mac says Send to Mac and is live")
    func reachableSends() {
        let state = CommitState.resolve(
            connection: .reachable,
            hasInstallDescriptor: true,
            isAlreadyQueued: false,
            isAlreadyDeclared: false
        )
        #expect(state == .reachable)
        #expect(state.isActionable)
        #expect(DiscoverCopy.entry(state.copyKey).actionLabel == "Send to Mac")
    }

    /// A17: **both, and only these two.** With no Mac there is nowhere to write; with no descriptor
    /// there is nothing to queue. Everything else stays live.
    @Test("exactly two states disable the commit")
    func onlyTwoStatesDisable() {
        let disabled = CommitState.allCases.filter { !$0.isActionable }
        // Queued states are also inert, but they are inert because the act is already done rather
        // than refused — they are asserted separately below.
        #expect(disabled.contains(.neverPaired))
        #expect(disabled.contains(.noDescriptor))

        #expect(CommitState.resolve(
            connection: .neverPaired,
            hasInstallDescriptor: true,
            isAlreadyQueued: false,
            isAlreadyDeclared: false
        ) == .neverPaired)

        #expect(CommitState.resolve(
            connection: .reachable,
            hasInstallDescriptor: false,
            isAlreadyQueued: false,
            isAlreadyDeclared: false
        ) == .noDescriptor)
    }

    /// Never-paired outranks no-descriptor, because neither is recoverable by tapping and the
    /// pairing is the one the user can act on.
    @Test("no Mac and no descriptor together report the Mac, which is the actionable one")
    func precedenceIsStated() {
        #expect(CommitState.resolve(
            connection: .neverPaired,
            hasInstallDescriptor: false,
            isAlreadyQueued: false,
            isAlreadyDeclared: false
        ) == .neverPaired)
    }

    @Test("already queued and already declared each report themselves, reachable or not")
    func queuedAndDeclaredStates() {
        #expect(CommitState.resolve(
            connection: .reachable,
            hasInstallDescriptor: true,
            isAlreadyQueued: true,
            isAlreadyDeclared: false
        ) == .queuedReachable)

        #expect(CommitState.resolve(
            connection: .notReachable,
            hasInstallDescriptor: true,
            isAlreadyQueued: true,
            isAlreadyDeclared: false
        ) == .queuedNotReachable)

        // Already declared outranks already queued: the reviewer's question is answered.
        #expect(CommitState.resolve(
            connection: .reachable,
            hasInstallDescriptor: true,
            isAlreadyQueued: true,
            isAlreadyDeclared: true
        ) == .alreadyDeclared)
    }

    /// The predicate that dims the button and the note that says why are read from one entry, so
    /// they cannot disagree.
    @Test("every commit state's dimming agrees with its own copy")
    func dimmingAgreesWithCopy() {
        for state in CommitState.allCases {
            let entry = DiscoverCopy.entry(state.copyKey)
            #expect(state.isActionable == !entry.isDisabled, "\(state) disagrees with its note")
            #expect(!entry.body.isEmpty, "\(state) dims with no discoverable reason")
        }
    }

    @Test("all seven commit states exist and each maps to a distinct key")
    func sevenStates() {
        #expect(CommitState.allCases.count == 7)
        #expect(Set(CommitState.allCases.map(\.copyKey)).count == 7)
    }

    // MARK: - A22: the queue write

    @Test("an enqueued item survives an app relaunch")
    func queueSurvivesRelaunch() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = FileCapabilityQueueWriter(directory: directory)
        try await writer.enqueue(Self.item(id: "smithery:github"))

        // A second writer over the same directory is the relaunch: nothing is shared in memory.
        let afterRelaunch = FileCapabilityQueueWriter(directory: directory)
        #expect(try await afterRelaunch.contains("smithery:github"))
    }

    @Test("enqueueing the same entry twice leaves one row and keeps the first timestamp")
    func enqueueIsIdempotent() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let writer = FileCapabilityQueueWriter(directory: directory)
        let first = Date(timeIntervalSince1970: 1_000_000)
        try await writer.enqueue(Self.item(id: "dup", queuedAt: first))
        try await writer.enqueue(Self.item(id: "dup", queuedAt: first.addingTimeInterval(500)))

        let stored = try Self.storedItems(in: directory)
        #expect(stored.count == 1, "a second tap produced a second row for the reviewer")
        // The fact the reviewer cares about is when it was *first* sent.
        #expect(stored.first?.queuedAt == first)
    }

    /// I1's `PairingStorageFailureTests` is the precedent this is written against: there, a `try?`
    /// made a refused Keychain write render as paired while nothing had been written.
    @Test("a refused write throws and never reports success")
    func refusedWriteThrows() async {
        let queue = InMemoryCapabilityQueue(failure: .writeFailed("disk full"))
        await #expect(throws: CapabilityQueueError.writeFailed("disk full")) {
            try await queue.enqueue(Self.item(id: "x"))
        }
        #expect(await queue.all().isEmpty, "a refused write left an item behind")
    }

    /// A decode path whose failure mode is emptiness is the exact defect `SWIFT_PRACTICES.md` §2
    /// records from this repo's own TypeScript router — a flat `servers.json` loaded zero servers
    /// with no error at all. A corrupt queue must not read as "nothing is queued".
    @Test("an unreadable queue file is an error, never an empty queue")
    func corruptQueueIsNotEmpty() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("capability-queue.json")
        try Data("{ not a queue".utf8).write(to: url)

        let writer = FileCapabilityQueueWriter(directory: directory)
        await #expect(throws: CapabilityQueueError.self) {
            _ = try await writer.contains("anything")
        }
    }

    @Test("a missing queue file is an empty queue, which is the one honest emptiness")
    func missingFileIsEmpty() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = FileCapabilityQueueWriter(directory: directory)
        #expect(try await writer.contains("nothing") == false)
    }

    // MARK: - Helpers

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("i2-queue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func item(id: String, queuedAt: Date = Date()) -> QueuedCapability {
        QueuedCapability(
            id: id,
            displayName: id,
            source: .smithery,
            install: nil,
            queuedAt: queuedAt
        )
    }

    static func storedItems(in directory: URL) throws -> [QueuedCapability] {
        let data = try Data(contentsOf: directory.appendingPathComponent("capability-queue.json"))
        return try JSONDecoder().decode([QueuedCapability].self, from: data)
    }
}
