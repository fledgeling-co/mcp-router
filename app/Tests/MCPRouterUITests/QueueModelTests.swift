#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// The Queue's two writes, and the claims the surface makes about them.
    ///
    /// Both of these were found by the Phase D critic against code that compiled, passed lint and
    /// had a green suite. They are the same defect wearing two hats: **a control that names an act
    /// it does not perform**, and **a banner that reports an act that was refused**.
    @MainActor
    @Suite("Queue model")
    struct QueueModelTests {
        static func item(
            _ id: String,
            at date: Date = Date(timeIntervalSince1970: 1_000_000)
        ) -> QueuedCapability {
            QueuedCapability(
                id: id,
                displayName: id.capitalized,
                source: .official,
                install: nil,
                queuedAt: date
            )
        }

        // MARK: - A10 / A19: the Undo button performs the act it names

        /// **The defect M6 recorded, repeating.** `clearUndo()` was `undo = nil` — so the button
        /// labelled "Undo", rendered in the accent colour on a 44pt target, dismissed the message
        /// saying the row had been removed and left it removed. A user who taps Undo and watches the
        /// banner disappear believes the row is back.
        @Test("undo puts the removed item back in the queue")
        func undoRestoresTheItem() async throws {
            let queue = InMemoryCapabilityQueue()
            try await queue.enqueue(Self.item("official:linear"))
            try await queue.enqueue(Self.item("official:weather"))

            let model = QueueModel(queue: queue)
            await model.load()
            #expect(try await queue.all().count == 2)

            await model.remove(Self.item("official:linear"))
            #expect(try await queue.all().map(\.id) == ["official:weather"])
            #expect(model.undo?.id == "official:linear")

            await model.undoLast()

            let ids = try await queue.all().map(\.id).sorted()
            #expect(ids == ["official:linear", "official:weather"], "undo did not restore the row")
            #expect(model.undo == nil, "the undo offer outlived the act")
        }

        /// `enqueue` is idempotent on `id` and the item we kept carries the original stamp, so an
        /// undo restores the row the user was looking at rather than a fresh one stamped now.
        @Test("undo keeps the original queuedAt rather than restamping")
        func undoKeepsTheOriginalStamp() async throws {
            let queued = Date(timeIntervalSince1970: 1_000_000)
            let queue = InMemoryCapabilityQueue()
            try await queue.enqueue(Self.item("official:linear", at: queued))

            let model = QueueModel(queue: queue)
            await model.load()
            await model.remove(Self.item("official:linear", at: queued))
            await model.undoLast()

            let restored = try #require(try await queue.all().first)
            #expect(restored.queuedAt == queued, "undo restamped the row it restored")
        }

        // MARK: - A14: a refused write is reported, on the one surface that writes

        /// `QueueSurfaceState.writeRefused`, its copy and its render arm all existed. Nothing ever
        /// set the flag, so all three were unreachable — and `try?` meant a refused removal still
        /// rendered "Linear removed from the queue" above a list that still contained Linear. Two
        /// contradictory claims on screen, the true one quieter.
        @Test("a refused removal reports the failure and offers no undo")
        func refusedRemovalIsSurfaced() async {
            let queue = InMemoryCapabilityQueue(failure: .writeFailed("read-only volume"))
            let model = QueueModel(queue: queue)
            await model.load()

            await model.remove(Self.item("official:linear"))

            #expect(model.lastWriteFailed, "a refused removal was recorded as a success")
            #expect(model.undo == nil, "undo was offered for a removal that never happened")
            guard case .writeRefused = model.state else {
                Issue.record("a refused removal did not reach .writeRefused: \(model.state)")
                return
            }
        }

        /// A successful write after a refused one clears the banner: a stale failure is its own
        /// false claim.
        @Test("a successful removal clears a previous failure")
        func successClearsThePreviousFailure() async throws {
            let queue = InMemoryCapabilityQueue()
            try await queue.enqueue(Self.item("official:linear"))

            let model = QueueModel(queue: queue)
            await model.load()
            model.lastWriteFailed = true

            await model.remove(Self.item("official:linear"))
            #expect(!model.lastWriteFailed, "a successful write left the failure banner up")
        }

        // MARK: - A17: an unreadable queue is never an empty queue

        @Test("an unreadable queue is its own state")
        func unreadableIsNotEmpty() async {
            let queue = InMemoryCapabilityQueue(readFailure: .unreadable("corrupt"))
            let model = QueueModel(queue: queue)
            await model.load()

            #expect(model.state == .unreadable)
            #expect(model.state != .empty)
            #expect(model.state.copyKey == .state(.unreadable))
        }

        /// A missing file is an honest empty queue — the one place emptiness is the right answer.
        @Test("an empty queue is empty, not unreadable")
        func emptyIsEmpty() async {
            let model = QueueModel(queue: InMemoryCapabilityQueue())
            await model.load()
            #expect(model.state == .empty)
        }
    }
#endif
