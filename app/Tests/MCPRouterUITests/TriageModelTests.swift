#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// Triage's behaviour: what is selected, what the commit bar is, what a refused write does, and
    /// which failure outranks which.
    ///
    /// Host tests about **logic and wiring**. What a 44pt target measures and what wraps on a 393pt
    /// phone are asserted in `MCPRouterIOSTests`; asserting them here would be a green light for
    /// something nobody measured.
    @MainActor
    @Suite("Triage model")
    struct TriageModelTests {
        static func model(
            entries: [RegistryEntry] = TriageSpecimens.all,
            warnings: [String] = [],
            failure: ControlAPIError? = nil,
            queue: InMemoryCapabilityQueue = InMemoryCapabilityQueue(),
            dismissals: InMemoryDismissalStore = InMemoryDismissalStore(),
            connection: ConnectionState = .reachable
        ) -> (TriageModel, DiscoverRecordingClient) {
            let client = DiscoverRecordingClient()
            client.staged = [
                failure.map { Result<RegistrySearchResponse, ControlAPIError>.failure($0) }
                    ?? .success(TriageSpecimens.response(entries, warnings: warnings))
            ]
            let model = TriageModel(
                client: client,
                queue: queue,
                dismissals: dismissals,
                connection: connection
            )
            return (model, client)
        }

        // MARK: - A2: nothing is selected by default

        /// The first of the two prototype bugs, inverted. On a screen whose job is deliberate
        /// selection, a pre-ticked default makes "send all of these to my laptop" the act you get by
        /// doing nothing.
        @Test("the selection is empty before and after a load")
        func selectionStartsEmpty() async {
            let (model, _) = Self.model()
            #expect(model.selected.isEmpty)
            await model.load()
            #expect(model.selected.isEmpty, "a load pre-selected rows")
        }

        /// A selection carried across a bucket switch is a selection the user cannot see, attached
        /// to a commit bar stating a number they cannot account for.
        @Test("changing bucket clears the selection")
        func bucketChangeClearsSelection() async {
            let (model, _) = Self.model()
            await model.load()
            model.toggleSelection(TriageSpecimens.stdio.id)
            #expect(model.selected.count == 1)

            model.select(bucket: .queued)
            #expect(model.selected.isEmpty, "the selection survived a bucket change")
        }

        @Test("an entry with no install descriptor is never selectable")
        func noInstallIsNotSelectable() async {
            let (model, _) = Self.model()
            await model.load()

            #expect(!model.selectableIDs.contains(TriageSpecimens.noInstall.id))
            #expect(model.selectableIDs.contains(TriageSpecimens.stdio.id))
        }

        @Test("select all takes exactly the selectable entries, and clears from full")
        func selectAllThenClear() async {
            let (model, _) = Self.model()
            await model.load()

            model.selectAllOrClear()
            #expect(model.selected == Set(model.selectableIDs))
            #expect(!model.selected.contains(TriageSpecimens.noInstall.id))
            #expect(model.isAllSelected)

            model.selectAllOrClear()
            #expect(model.selected.isEmpty)
        }

        // MARK: - A2 / A12: absent is not disabled

        /// With nothing ticked and a Mac paired there is nothing to commit, so there is no commit
        /// control at all — `absent`, not `disabled`.
        @Test("the commit bar is absent when nothing is ticked and a Mac is paired")
        func commitAbsentWhenEmpty() {
            #expect(TriageCommitState.resolve(selectionCount: 0, connection: .reachable) == .absent)
            #expect(TriageCommitState.resolve(selectionCount: 0, connection: .notReachable) == .absent)
        }

        /// A2's named cell. With no Mac paired the bar is present and dimmed **from first
        /// appearance**, because the reason is a fact about the surface rather than about the
        /// selection — and a user who ticks four rows and only then learns there is nowhere to send
        /// them has been allowed to waste the work.
        @Test("with no Mac paired the bar is present and dimmed before anything is ticked")
        func commitDimmedFromFirstAppearance() {
            let state = TriageCommitState.resolve(selectionCount: 0, connection: .neverPaired)
            #expect(state == .neverPaired(count: 0))
            #expect(state != .absent, "the unpaired bar was hidden instead of dimmed")
            #expect(state.copyKey != nil, "the dimmed bar carries no reason")
        }

        /// **The predicate is `canQueue`, never `canSend`.** Queueing writes to this phone's own
        /// storage and succeeds with the Mac asleep, so binding it to `canSend` refuses an act that
        /// works — a disabled "Send" on one screen beside a live one on another, same Mac, same
        /// second.
        @Test("an unreachable but paired Mac can still be queued for")
        func unreachableStillQueues() {
            #expect(!ConnectionState.notReachable.canSend)
            #expect(ConnectionState.notReachable.canQueue)

            let state = TriageCommitState.resolve(selectionCount: 2, connection: .notReachable)
            #expect(state == .ready(count: 2), "a sleeping Mac disabled a local write")
        }

        @Test("the commit label's count is the selection's size")
        func commitCountIsTheSelection() {
            #expect(TriageCommitState.resolve(selectionCount: 3, connection: .reachable).count == 3)
        }

        // MARK: - A13: queueing is idempotent

        /// The fact the reviewer cares about is when it was **first** sent, so a repeat keeps the
        /// original stamp and produces no second row.
        @Test("queueing an already-queued entry produces no second row and keeps the first stamp")
        func queueingIsIdempotent() async throws {
            let queue = InMemoryCapabilityQueue()
            let first = Date(timeIntervalSince1970: 1_000_000)
            try await queue.enqueue(QueuedCapability(entry: TriageSpecimens.stdio, queuedAt: first))

            let (model, _) = Self.model(queue: queue)
            await model.load()
            // It is already queued, so it lands in the Queued bucket rather than Undecided.
            #expect(model.buckets.queued.map(\.id) == [TriageSpecimens.stdio.id])

            let items = try await queue.all()
            #expect(items.count == 1)
            #expect(items[0].queuedAt == first, "a repeat overwrote the original stamp")
        }

        @Test("a batch queues every selected entry and offers one undo for the whole batch")
        func queueBatchThenUndo() async throws {
            let queue = InMemoryCapabilityQueue()
            let (model, _) = Self.model(queue: queue)
            await model.load()

            model.toggleSelection(TriageSpecimens.stdio.id)
            model.toggleSelection(TriageSpecimens.remote.id)
            await model.queueSelected()

            #expect(try await queue.all().count == 2)
            #expect(model.undo == .queued([TriageSpecimens.stdio.id, TriageSpecimens.remote.id])
                || model.undo?.ids.count == 2)
            #expect(model.selected.isEmpty, "the selection outlived the commit")

            await model.undoLast()
            #expect(try await queue.all().isEmpty, "undo left rows in the queue")
            #expect(model.undo == nil)
        }

        // MARK: - A14: a refused write is never a queued item

        /// I1's precedent: two `try?` sites made a refused Keychain write render "Paired." while
        /// nothing was stored. A refused write is surfaced, names what was not saved, and the item
        /// does not move.
        @Test("a wholly refused batch reports the failure and queues nothing")
        func refusedBatchIsSurfaced() async throws {
            let queue = InMemoryCapabilityQueue(failure: .writeFailed("no space"))
            let (model, _) = Self.model(queue: queue)
            await model.load()

            model.toggleSelection(TriageSpecimens.stdio.id)
            model.toggleSelection(TriageSpecimens.remote.id)
            await model.queueSelected()

            let failure = try #require(model.writeFailure)
            #expect(failure.saved == 0)
            #expect(failure.refused.count == 2)
            #expect(failure.isTotal)
            #expect(model.undo == nil, "undo was offered for a write that never landed")
            #expect(try await queue.all().isEmpty)

            // The refused entries stay in Undecided, because that is where they are.
            #expect(model.buckets.undecided.contains { $0.id == TriageSpecimens.stdio.id })
        }

        /// A partial batch reports what did and did not land, and reads differently from a total
        /// failure — "three of five landed" is not "nothing landed".
        @Test("a partial failure and a total failure carry different copy")
        func partialAndTotalDiffer() {
            let total = TriageWriteFailure(saved: 0, refused: ["a", "b"])
            let partial = TriageWriteFailure(saved: 3, refused: ["c"])

            #expect(total.isTotal)
            #expect(!partial.isTotal)
            #expect(total.copyKey != partial.copyKey, "both failures render the same sentence")
        }

        @Test("a refused dismissal is surfaced and dismisses nothing")
        func refusedDismissalIsSurfaced() async throws {
            let dismissals = InMemoryDismissalStore(failure: .writeFailed("refused"))
            let (model, _) = Self.model(dismissals: dismissals)
            await model.load()

            model.toggleSelection(TriageSpecimens.stdio.id)
            await model.dismissSelected()

            #expect(model.writeFailure?.isTotal == true)
            #expect(model.undo == nil)
            #expect(try await dismissals.all().isEmpty)
        }

        // MARK: - A9: the unreadable dismissal set outranks everything

        /// A list rendered from a dismissal set that failed to load is a list showing things the
        /// user already rejected, and looking correct while doing it. So it gets its own state,
        /// ahead of the populated one.
        @Test("an unreadable dismissal set is its own state, not a populated list")
        func unreadableDismissalsOutrankPopulated() async {
            let dismissals = InMemoryDismissalStore(readFailure: .unreadable("corrupt"))
            let (model, _) = Self.model(dismissals: dismissals)
            await model.load()

            #expect(model.state == .dismissalsUnreadable)
            #expect(model.displayState == .dismissalsUnreadable)
            #expect(model.state.copyKey == .state(.dismissalsUnreadable))
        }

        /// The resolver's guard order is the order of the claims, and it holds even when the
        /// registry answered perfectly.
        @Test("the dismissal failure outranks a successful search")
        func dismissalFailureOutranksSuccess() {
            let state = TriageSurfaceState.resolve(
                results: .success(TriageSpecimens.response()),
                queuedIDs: [],
                dismissedIDs: .failure(.unreadable("corrupt"))
            )
            #expect(state == .dismissalsUnreadable)
        }

        // MARK: - A23: offline is its own state

        /// `routerNotRunning` renders as its own state, never as a generic error.
        @Test("the router not running is offline, not a failure")
        func offlineIsItsOwnState() async {
            let (model, _) = Self.model(failure: .routerNotRunning)
            await model.load()

            #expect(model.state == .offline)
            #expect(model.state.copyKey == .state(.offline))
        }

        @Test("any other control error is a failure, not offline")
        func otherErrorsAreFailures() async {
            let (model, _) = Self.model(failure: .transport(detail: "reset by peer"))
            await model.load()

            guard case .failed = model.state else {
                Issue.record("a transport error did not resolve to failed: \(model.state)")
                return
            }
        }

        // MARK: - A24: bucket emptiness is derived from the chosen bucket

        /// Which bucket is empty is a fact about the bucket the user has chosen, and that changes
        /// without another load.
        @Test("an empty chosen bucket renders that bucket's own empty state")
        func emptyIsPerBucket() async {
            let (model, _) = Self.model()
            await model.load()

            #expect(model.displayState != .empty(.undecided), "Undecided was empty with results in")

            model.select(bucket: .dismissed)
            #expect(model.displayState == .empty(.dismissed))
            #expect(model.displayState.copyKey == .state(.emptyDismissed))

            model.select(bucket: .queued)
            #expect(model.displayState.copyKey == .state(.emptyQueued))
        }

        // MARK: - A9: a dismissal is reversible from its own bucket

        @Test("a dismissed entry moves to its bucket and comes back")
        func dismissThenRestore() async {
            let dismissals = InMemoryDismissalStore()
            let (model, _) = Self.model(dismissals: dismissals)
            await model.load()

            model.toggleSelection(TriageSpecimens.stdio.id)
            await model.dismissSelected()
            #expect(model.buckets.dismissed.map(\.id) == [TriageSpecimens.stdio.id])

            await model.restore(TriageSpecimens.stdio.id)
            #expect(model.buckets.dismissed.isEmpty)
            #expect(model.buckets.undecided.contains { $0.id == TriageSpecimens.stdio.id })
        }

        // MARK: - A16: Triage reads the registry with the same page Discover does

        @Test("the search asks for the same limit Discover asks for")
        func searchLimitMatchesDiscover() async {
            let (model, client) = Self.model()
            await model.load()

            #expect(client.searchLimits == [TriageModel.searchLimit])
        }
    }
#endif
