#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    @Suite("M6 — the Inbox board")
    @MainActor
    struct InboxBoardTests {
        static func model(
            _ scenario: FixtureInboxService.Scenario = .paired,
            client: (any ControlAPIClient)? = nil
        ) -> InboxBoardModel {
            InboxBoardModel(
                client: client ?? FixtureControlAPIClient(.populated),
                service: FixtureInboxService(scenario)
            )
        }

        // MARK: - A1 · the board is installed

        /// The assertion this item is actually done against. A board that compiles but is absent
        /// from `installed` still showed the reader a placeholder — and M6 is the item that removed
        /// the placeholder, so the failure mode now is a blank pane rather than an honest one.
        @Test("Inbox is registered, which completes the set")
        func inboxIsInstalled() {
            #expect(BoardRegistry.hasBoard(.inbox))
            #expect(BoardRegistry.installed.contains(.inbox))
            #expect(BoardRegistry.installed == Set(Destination.allCases))
            #expect(BoardRegistry.scaffolded.isEmpty)
        }

        // MARK: - Loading and the states

        @Test("nothing loaded is loading, not empty")
        func loadingIsNotEmpty() {
            let board = Self.model()
            #expect(board.state == .loading)
            #expect(board.rows.isEmpty)
            // And the badge says nothing rather than zero: no observation has been made yet.
            #expect(board.waitingCount == nil)
        }

        @Test("a populated load lists what is waiting, newest first")
        func populatedOrdersByRecency() async {
            let board = Self.model(.paired)
            await board.load()
            #expect(board.rows.count == 2)
            let dates = board.rows.map(\.envelope.queuedAt)
            #expect(dates == dates.sorted(by: >))
        }

        @Test("a read failure with nothing loaded is failed, not empty")
        func failureIsNotEmpty() async {
            let board = Self.model(.failed)
            await board.load()
            #expect(board.state.error != nil)
            #expect(board.state.snapshot == nil)
        }

        /// A previous good reading is kept and labelled rather than discarded: an empty board is a
        /// stronger claim than a stale one, and "nothing is waiting" is exactly the claim this
        /// surface must not make wrongly.
        @Test("a failure after a good read keeps the rows and marks them stale")
        func failureAfterSuccessGoesStale() async {
            let board = InboxBoardModel(
                client: FixtureControlAPIClient(.populated),
                service: FlakyInboxService()
            )
            await board.load()
            #expect(board.rows.count == 1)
            await board.load()
            if case let .stale(snapshot, _) = board.state {
                #expect(snapshot.items.count == 1)
            } else {
                Issue.record("expected a stale state, got \(board.state)")
            }
            #expect(board.rows.count == 1, "a stale reading still lists")
        }

        // MARK: - A18 · the badge

        /// **The badge and the list are the same observation**, which is what stops them disagreeing.
        ///
        /// Asserted *after a disposition*, deliberately: the two are trivially equal on a freshly
        /// loaded board, so a badge wired to the loaded snapshot rather than to the rendered rows
        /// would pass every assertion made before anyone acted. Declining is the moment they can
        /// diverge, and this is the assertion that catches it.
        @Test("the badge counts the rows the board renders, including after a disposition")
        func badgeTracksRenderedRows() async throws {
            let board = Self.model(.paired)
            await board.load()
            #expect(board.waitingCount == board.rows.count)
            #expect(board.waitingCount == 2)

            try board.decline(#require(board.rows.first))
            #expect(board.rows.count == 1)
            #expect(board.waitingCount == 1, "the badge still counts what is on screen")

            try board.decline(#require(board.rows.first))
            // Zero renders no badge at all, matching every other destination.
            #expect(board.rows.isEmpty)
            #expect(board.waitingCount == nil)
        }

        @Test("an empty inbox has no badge, and an unpaired one has none either")
        func emptyAndUnpairedCarryNoBadge() async {
            let empty = Self.model(.pairedEmpty)
            await empty.load()
            #expect(empty.waitingCount == nil)

            let unpaired = Self.model(.none)
            await unpaired.load()
            #expect(unpaired.waitingCount == nil)
            #expect(unpaired.pairedDeviceName == nil)
        }

        // MARK: - A13 · the boundary

        /// **Accepting is the only path that installs, and it calls `add` exactly once.**
        ///
        /// Counted on a recording client rather than inferred from the row disappearing: a local
        /// mutation looks identical to an install from the outside, which is precisely the thing
        /// worth being sure about on the one surface where a remote device's request becomes code
        /// that runs. `force` is asserted false — `force: true` adopts an existing declaration, so a
        /// queued row could otherwise replace the command line of a server the user already trusts.
        @Test("accepting calls add once with force false, and nothing else calls it at all")
        func acceptInstallsExactlyOnce() async throws {
            let recorder = RecordingControlAPIClient(wrapping: FixtureControlAPIClient(.populated))
            let board = Self.model(.paired, client: recorder)
            await board.load()

            // Loading and rendering call it zero times.
            #expect(recorder.calls.add == 0)
            _ = board.rows.map(\.title)
            #expect(recorder.calls.add == 0)

            // Declining calls it zero times: it is a local decision about something that never ran.
            let declined = try #require(board.rows.last)
            board.decline(declined)
            #expect(recorder.calls.add == 0)

            let item = try #require(board.rows.first { !$0.isPartial })
            let acceptable = try #require(AcceptableInboxItem(item))
            await board.accept(acceptable)

            #expect(recorder.calls.add == 1)
            #expect(recorder.calls.addForced == 0, "a queued item may never adopt an existing server")
            #expect(recorder.calls.remove == 0)
        }

        /// A13's other half: nothing in the read path installs.
        @Test("an unresolved item has no path to the installer")
        func partialCannotBeAccepted() async throws {
            let board = Self.model(.partial)
            await board.load()
            let partials = board.rows.filter(\.isPartial)
            let unresolved = try #require(partials.first)
            #expect(AcceptableInboxItem(unresolved) == nil)
        }

        // MARK: - A14 · undo

        @Test("declining is reversible and reported")
        func declineIsUndoable() async throws {
            let board = Self.model(.paired)
            await board.load()
            let item = try #require(board.rows.first)

            board.decline(item)
            #expect(board.rows.count == 1)
            #expect(board.undoLabel() == InboxCopy.declined(item.title))

            board.undoLastDisposition()
            #expect(board.rows.count == 2)
            #expect(board.undoLabel() == nil, "one slot, and it is spent")
        }

        @Test("accepting is reported and its row returns on undo")
        func acceptIsReported() async throws {
            let board = Self.model(.paired)
            await board.load()
            let item = try #require(board.rows.first { !$0.isPartial })
            try await board.accept(#require(AcceptableInboxItem(item)))

            #expect(board.undoLabel() == InboxCopy.accepted(item.title))
            #expect(!board.rows.contains { $0.id == item.id })
            board.undoLastDisposition()
            #expect(board.rows.contains { $0.id == item.id })
        }

        /// One slot, not a stack: a deeper history would promise a record this surface does not keep.
        @Test("only the most recent disposition can be undone")
        func undoIsSingleSlot() async throws {
            let board = Self.model(.paired)
            await board.load()
            let first = try #require(board.rows.first)
            let second = try #require(board.rows.last)

            board.decline(first)
            board.decline(second)
            board.undoLastDisposition()

            #expect(board.rows.contains { $0.id == second.id })
            #expect(!board.rows.contains { $0.id == first.id }, "the older one stays dispositioned")
            #expect(board.undoLabel() == nil)
        }

        // MARK: - Keyboard

        /// `Return` opens the review sheet and never installs. A list row that installs is the
        /// one-click path from a remote request to code running, which the queue exists to refuse.
        @Test("Return opens review rather than accepting")
        func returnOpensReview() async throws {
            let recorder = RecordingControlAPIClient(wrapping: FixtureControlAPIClient(.populated))
            let board = Self.model(.paired, client: recorder)
            await board.load()

            #expect(board.commitDefaultAction() == false, "nothing selected, so the key is unhandled")
            board.selection = try #require(board.rows.first).id
            #expect(board.commitDefaultAction())
            #expect(board.sheetItemID == board.selection)
            #expect(recorder.calls.add == 0)
        }

        @Test("Esc dismisses the pairing sheet, then the review sheet, then the selection")
        func escapeUnwindsOneLayerAtATime() async throws {
            let board = Self.model(.paired)
            await board.load()
            board.selection = try #require(board.rows.first).id
            _ = board.commitDefaultAction()
            board.pairing.open()

            board.escape()
            #expect(!board.pairing.isOpen)
            #expect(board.sheetItemID != nil, "only one layer per press")

            board.escape()
            #expect(board.sheetItemID == nil)
            #expect(board.selection != nil)

            board.escape()
            #expect(board.selection == nil)
        }

        @Test("arrow keys report whether they had anywhere to move")
        func selectionMovementReportsItself() async {
            let empty = Self.model(.pairedEmpty)
            await empty.load()
            #expect(empty.moveSelection(by: 1) == false, "an empty board leaves the key unhandled")

            let board = Self.model(.paired)
            await board.load()
            #expect(board.moveSelection(by: 1))
            #expect(board.selection != nil)
        }

        // MARK: - Copy

        @Test("the subtitle never claims a pairing the build does not have")
        func subtitleComesFromState() {
            #expect(InboxCopy.subtitle(waiting: 0, device: nil) == "Nothing waiting · no phone paired")
            #expect(
                InboxCopy.subtitle(waiting: 0, device: "Luke's iPhone")
                    == "Nothing waiting · paired with Luke's iPhone"
            )
            #expect(
                InboxCopy.subtitle(waiting: 2, device: "Luke's iPhone") == "2 waiting from Luke's iPhone"
            )
        }
    }

    /// Succeeds once, then fails — for the stale path, which needs two different answers from one
    /// service and so cannot come from a fixture scenario.
    private final class FlakyInboxService: InboxService, @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0

        func snapshot() async throws(InboxServiceError) -> InboxSnapshot {
            let first = lock.withLock {
                calls += 1
                return calls == 1
            }
            guard first else { throw .unreadable(detail: "the queue file could not be read") }
            // Built here rather than borrowed from the fixture's internals: this double needs one
            // row and two different answers, and reaching into another type's private shape to get
            // it would couple this test to a detail it is not about.
            let envelope = InboxEnvelope(
                version: 1,
                id: "stale-1",
                entryID: "authored:local-notes",
                displayName: "Local notes",
                queuedAt: Date(timeIntervalSince1970: 1_755_000_000),
                deviceName: FixtureInboxService.fixtureDevice
            )
            return InboxSnapshot(
                items: [InboxItem(envelope: envelope, resolved: nil)],
                pairedDeviceName: FixtureInboxService.fixtureDevice
            )
        }

        func availability() -> PairingAvailability {
            .noEndpoint
        }
    }
#endif
