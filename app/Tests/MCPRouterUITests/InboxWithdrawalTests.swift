#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// A17's other half: the withdrawal that happens **at** the disposition rather than at the next
    /// read.
    ///
    /// An `extension` of `InboxArrivalTests` rather than a suite of its own, and that is the whole
    /// reason this file exists in this shape. `InboxArrivalTests.swift` is at its 400-line budget, so
    /// the clause had to go somewhere else — and the last time a suite was split on this branch, nine
    /// mutation filters went on naming the suite the clauses had left and measured nothing for two
    /// commits. A test declared in an extension keeps the suite's own name in its identifier, so
    /// `--filter InboxArrivalTests` still reaches it and no filter anywhere needs re-aiming.
    extension InboxArrivalTests {
        /// **The commanded withdrawal, asserted with no read after the disposition.**
        ///
        /// The derived reconcile in `announceArrivals` produces the same withdrawal on the next
        /// `load()`, which is why `withdrawalIsSweptOnTheNextRead` cannot see this call at all: delete
        /// `withdrawBanner(for:)` from `record` and that clause stays green, because the poll cleans
        /// up after it two seconds later. The spec says *the moment* (`spec-I6.md` §"Withdrawal"), and
        /// a two-second window in which a banner still offers `Decline` for a gone item is the race
        /// the sentence exists to close.
        ///
        /// So the load is deliberately absent here. What is awaited is the model's own withdrawal
        /// task — `pendingWithdrawal` is stored rather than detached precisely so this clause can
        /// join it instead of sleeping, which would make the assertion a timing guess.
        @Test("a disposition withdraws its own banner before any further read")
        func withdrawalIsCommandedAtTheDisposition() async throws {
            let notifier = RecordingArrivalNotifier()
            let both = try [Self.item(id: "q-1", secondsAgo: 300, resolved: true),
                            Self.item(id: "q-2", secondsAgo: 60, resolved: true)]
            let (board, client) = Self.board(
                [.success(Self.snapshot(both))],
                notifier: notifier
            )
            await board.load()
            #expect(notifier.withdrawals.isEmpty)

            board.decline(itemID: "q-1")
            // No `load()`. This is the whole point of the clause.
            await board.pendingWithdrawal?.value

            let withdrawn = try #require(
                notifier.withdrawals.last,
                "the disposition withdrew nothing — the banner survives until the next poll"
            )
            #expect(withdrawn.contains("q-1"))
            #expect(!withdrawn.contains("q-2"), "a live item's banner was withdrawn")
            // The multi-item banner says "N items are waiting", and one press makes that false.
            #expect(withdrawn.contains(InboxAnnouncement.manyIdentifier))
            // Withdrawing is not declaring: the same press must reach the router with nothing.
            #expect(client.calls.add == 0)
        }

        /// The same rule for an **accept**, which takes a different path into `record`.
        ///
        /// Worth its own clause rather than a second case in the one above: accepting is the branch
        /// that talks to the router, so it is the branch where a later edit is most likely to return
        /// early and skip the withdrawal — leaving a banner offering `Review` for a server that is
        /// already installed.
        @Test("an accept withdraws its banner too, on the press rather than on the poll")
        func acceptWithdrawsItsOwnBanner() async throws {
            let notifier = RecordingArrivalNotifier()
            let items = try [Self.item(id: "q-1", secondsAgo: 300, resolved: true)]
            let (board, _) = Self.board([.success(Self.snapshot(items))], notifier: notifier)
            await board.load()

            let item = try #require(board.rows.first { $0.id == "q-1" })
            let acceptable = try #require(AcceptableInboxItem(item))
            await board.accept(acceptable)
            await board.pendingWithdrawal?.value

            let withdrawn = try #require(
                notifier.withdrawals.last,
                "an accepted item's banner survives until the next poll"
            )
            #expect(withdrawn.contains("q-1"))
        }
    }
#endif
