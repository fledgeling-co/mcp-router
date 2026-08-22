#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// **The acceptance line.** The brief asks that *"every row of the gate table has a test naming
    /// the sheet it presents"*, and this is where that is answered — at the board-model seam, by
    /// invoking the action and observing which sheet opened.
    ///
    /// It is deliberately not in `SheetGateTests`, which lives beside the table in `MCPRouterKit`.
    /// That suite proves the table is complete and internally consistent, and a table asserted only
    /// against itself would pass at full green while a button called `remove(name)` directly. The
    /// question worth asking is whether pressing the thing opens the gate, and only a model can be
    /// asked that.
    ///
    /// Rows whose gate is not a sheet are asserted for what they *are* instead: the reversible one
    /// opens nothing, and the two with no host say who owns them.
    @MainActor
    @Suite("The gate table, routed through")
    struct SheetGateRoutingTests {
        // MARK: - Accept held schema changes → quarantine

        @Test("accepting held changes opens the sheet the gate names, on the server it names")
        func acceptHeldChangesOpensQuarantine() async {
            let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
            let board = ServersBoardModel(client: FixtureControlAPIClient(.populated), tracker: tracker)

            #expect(board.sheet == nil)
            board.request(.acceptHeldChanges, subject: "mobbin")

            #expect(board.sheet == .heldChange(server: "mobbin"))
            #expect(SheetGate.gate(for: .acceptHeldChanges) == .sheet(.quarantine))
            #expect(RouterSheet.servers(board.sheet ?? .addServer).kind == .quarantine)
        }

        // MARK: - Remove an installed capability → confirm-remove, on both its hosts

        @Test("removing a server from Servers opens confirm-remove")
        func removeFromServersOpensConfirmRemove() async {
            let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
            let board = ServersBoardModel(client: FixtureControlAPIClient(.populated), tracker: tracker)

            board.request(.removeInstalledCapability, subject: "ai-elements")

            #expect(board.sheet == .removeServer(server: "ai-elements"))
            #expect(SheetGate.gate(for: .removeInstalledCapability) == .sheet(.confirmRemove))
            #expect(RouterSheet.servers(board.sheet ?? .addServer).kind == .confirmRemove)
        }

        @Test("removing a capability from Cleanup opens confirm-remove too — one kind, two hosts")
        func removeFromCleanupOpensConfirmRemove() async {
            let board = CleanupBoardModel(client: FixtureControlAPIClient(.populated))

            board.request(.removeInstalledCapability, subject: "ai-elements")

            #expect(board.sheet == .removeCandidate(name: "ai-elements"))
            #expect(RouterSheet.cleanup(board.sheet ?? .resetHistory).kind == .confirmRemove)
        }

        // MARK: - Approve a phone-queued install → queued-detail

        @Test("approving a queued install opens queued-detail, never installs from the row")
        func approveQueuedInstallOpensQueuedDetail() async {
            let board = InboxBoardModel(
                client: FixtureControlAPIClient(.populated),
                service: FixtureInboxService(.paired)
            )
            await board.load()
            guard let first = board.rows.first else {
                Issue.record("the populated inbox fixture produced no rows, so nothing could be opened")
                return
            }

            #expect(board.review(itemID: first.id))

            #expect(board.sheet == .queuedItem(id: first.id))
            #expect(SheetGate.gate(for: .approveQueuedInstall) == .sheet(.queuedDetail))
            #expect(SheetGate.radius(for: .approveQueuedInstall) == .executableCodeOnThisMac)
        }

        // MARK: - Reset the call history → reset-history, on both its hosts

        @Test("resetting the call history opens its sheet from Cleanup")
        func resetHistoryFromCleanup() async {
            let board = CleanupBoardModel(client: FixtureControlAPIClient(.populated))
            board.request(.resetCallHistory)
            #expect(board.sheet == .resetHistory)
        }

        @Test("resetting the call history opens its sheet from Activity")
        func resetHistoryFromActivity() async {
            let model = ActivityModel(
                client: FixtureControlAPIClient(.populated),
                source: nil,
                clock: { Date(timeIntervalSince1970: 0) }
            )
            model.request(.resetCallHistory)
            #expect(model.sheet == .resetHistory)
        }

        // MARK: - The rows whose gate is not a sheet

        @Test("the reversible action opens nothing — undo over confirm, not a dialog")
        func tripBreakerOpensNothing() async {
            let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
            let board = ServersBoardModel(client: FixtureControlAPIClient(.populated), tracker: tracker)

            #expect(board.request(.tripBreakerOrWake, subject: "mobbin") == nil)
            #expect(board.sheet == nil, "a reversible action gained friction; DESIGN.md §9")
        }

        @Test("an open sheet survives a request whose gate is not a sheet")
        func ungatedRequestDoesNotCloseAnOpenSheet() async {
            let tracker = ServerStateTracker(client: FixtureControlAPIClient(.populated))
            let board = ServersBoardModel(client: FixtureControlAPIClient(.populated), tracker: tracker)

            board.request(.acceptHeldChanges, subject: "mobbin")
            board.request(.tripBreakerOrWake, subject: "mobbin")

            #expect(
                board.sheet == .heldChange(server: "mobbin"),
                "an ungated action shut a sheet the user had opened"
            )
        }

        @Test("the two rows with no host in this build name who owns them")
        func unhostedRowsNameTheirOwner() {
            #expect(SheetGate.availability(for: .reconcileHarnessConfig) == .owned("M22"))
            #expect(SheetGate.gate(for: .reconcileHarnessConfig) == .sheet(.reconcile))
            #expect(SheetGate.availability(for: .stopRouter) == .owned("M20"))
            #expect(SheetGate.gate(for: .stopRouter) == .menuItem(accelerator: nil))
        }

        // MARK: - The sheet a board can hold

        @Test("Discover's official sheet opens without a row, because it is a definition")
        func officialMarkNeedsNoSubject() async {
            let board = DiscoverBoardModel(client: FixtureControlAPIClient(.populated))

            board.sheet = .officialMark

            #expect(board.sheet == .officialMark)
            #expect(board.sheetEntryID == nil, "the definition sheet claimed a row it is not about")
            #expect(RouterSheet.discover(.officialMark).kind == .official)
        }

        @Test("closing a Discover sheet clears both the mark and the entry, so neither leaks")
        func closingDiscoverClearsBoth() async {
            let board = DiscoverBoardModel(client: FixtureControlAPIClient(.populated))

            board.sheet = .registryEntry(id: "github")
            #expect(board.sheetEntryID == "github")
            board.sheet = nil
            #expect(board.sheetEntryID == nil)
            #expect(board.sheet == nil)
        }

        @Test("closing the pairing sheet stops the ticker rather than only clearing a flag")
        func closingPairingStopsTheTicker() async {
            let board = InboxBoardModel(
                client: FixtureControlAPIClient(.populated),
                service: FixtureInboxService(.paired)
            )

            board.sheet = .pairPhone
            #expect(board.sheet == .pairPhone)
            #expect(board.pairing.isOpen)

            board.sheet = nil

            #expect(board.sheet == nil)
            #expect(!board.pairing.isOpen, "the session stayed open, so its five-minute code kept ticking")
        }
    }
#endif
