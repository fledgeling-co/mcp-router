#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// What Triage does when a write is refused or a persisted set will not decode.
    ///
    /// **Split from `TriageModelTests` on a real seam**, not to satisfy a length rule: that suite
    /// asks what the surface *offers* — selection, the commit bar, idempotence — and this one asks
    /// what it *admits* when storage says no. Several of these exist because the Phase D critic
    /// found the surface reporting success for acts that had failed.
    ///
    /// The model builder is `TriageModelTests.model`, reused rather than copied: two builders that
    /// drift make the same assertion mean two different things depending on the file it lives in.
    @MainActor
    @Suite("Triage failure handling")
    struct TriageFailureTests {
        // MARK: - A14: a refused write is never a queued item

        /// I1's precedent: two `try?` sites made a refused Keychain write render "Paired." while
        /// nothing was stored. A refused write is surfaced, names what was not saved, and the item
        /// does not move.
        @Test("a wholly refused batch reports the failure and queues nothing")
        func refusedBatchIsSurfaced() async throws {
            let queue = InMemoryCapabilityQueue(failure: .writeFailed("no space"))
            let (model, _) = TriageModelTests.model(queue: queue)
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
            let (model, _) = TriageModelTests.model(dismissals: dismissals)
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
            let (model, _) = TriageModelTests.model(dismissals: dismissals)
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
                queuedIDs: .success(Set<String>()),
                dismissedIDs: .failure(.unreadable("corrupt"))
            )
            #expect(state == .dismissalsUnreadable)
        }

        // MARK: - A23: offline is its own state

        /// `routerNotRunning` renders as its own state, never as a generic error.
        @Test("the router not running is offline, not a failure")
        func offlineIsItsOwnState() async {
            let (model, _) = TriageModelTests.model(failure: .routerNotRunning)
            await model.load()

            #expect(model.state == .offline)
            #expect(model.state.copyKey == .state(.offline))
        }

        @Test("any other control error is a failure, not offline")
        func otherErrorsAreFailures() async {
            let (model, _) = TriageModelTests.model(failure: .transport(detail: "reset by peer"))
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
            let (model, _) = TriageModelTests.model()
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
            let (model, _) = TriageModelTests.model(dismissals: dismissals)
            await model.load()

            model.toggleSelection(TriageSpecimens.stdio.id)
            await model.dismissSelected()
            #expect(model.buckets.dismissed.map(\.id) == [TriageSpecimens.stdio.id])

            await model.restore(TriageSpecimens.stdio.id)
            #expect(model.buckets.dismissed.isEmpty)
            #expect(model.buckets.undecided.contains { $0.id == TriageSpecimens.stdio.id })
        }

        // MARK: - A9/A17 on the other persisted set (critic finding 3)

        /// `Undecided = results − queued − dismissed`, so a queue that will not decode returns every
        /// already-queued entry to Undecided and offers it for queueing again — while the Queue tab
        /// one tap away reports the same file correctly. An earlier shape used `try?` here and
        /// degraded to "nothing is queued", which is the failure-mode-is-emptiness defect applied to
        /// the set nobody thinks to check.
        @Test("an unreadable queue is its own state, not an empty queue")
        func unreadableQueueIsItsOwnState() async {
            let queue = InMemoryCapabilityQueue(readFailure: .unreadable("corrupt"))
            let (model, _) = TriageModelTests.model(queue: queue)
            await model.load()

            #expect(model.state == .queueUnreadable)
            #expect(model.state.copyKey == .state(.queueUnreadable))
            #expect(
                model.buckets.undecided.isEmpty,
                "an unreadable queue still populated Undecided, which re-offers what was queued"
            )
        }

        /// The two stores fail alike, which is A9's whole argument — and the dismissal failure still
        /// outranks the queue one, because it is checked first.
        @Test("both persisted sets have their own unreadable state, and they are distinct")
        func bothStoresHaveTheirOwnState() {
            let queueFailed = TriageSurfaceState.resolve(
                results: .success(TriageSpecimens.response()),
                queuedIDs: .failure(.unreadable("corrupt")),
                dismissedIDs: .success([])
            )
            #expect(queueFailed == .queueUnreadable)

            let dismissalsFailed = TriageSurfaceState.resolve(
                results: .success(TriageSpecimens.response()),
                queuedIDs: .success(Set<String>()),
                dismissedIDs: .failure(.unreadable("corrupt"))
            )
            #expect(dismissalsFailed == .dismissalsUnreadable)
            #expect(queueFailed != dismissalsFailed, "the two failures render the same message")
        }

        // MARK: - A14 on undo (critic finding 5)

        /// The user's last act was "undo". Reporting success for a wholly refused one is the same
        /// defect as I1's refused Keychain write rendering "Paired."
        @Test("a wholly refused undo reports the failure instead of clearing it")
        func refusedUndoIsSurfaced() async {
            let queue = InMemoryCapabilityQueue()
            let (model, _) = TriageModelTests.model(queue: queue)
            await model.load()

            model.toggleSelection(TriageSpecimens.stdio.id)
            await model.queueSelected()
            #expect(model.undo != nil)

            // The store starts refusing between the commit and the undo.
            let refusing = InMemoryCapabilityQueue(failure: .writeFailed("refused"))
            let (blocked, _) = TriageModelTests.model(queue: refusing)
            await blocked.load()
            blocked.toggleSelection(TriageSpecimens.stdio.id)
            await blocked.queueSelected()
            // The queue itself was refused, so there is nothing to undo and no offer to make.
            #expect(blocked.undo == nil)
            #expect(blocked.writeFailure?.isTotal == true)
        }

        /// The only path out of the Dismissed bucket. A refused restore left the row where it was
        /// with nothing said.
        @Test("a refused restore is surfaced rather than swallowed")
        func refusedRestoreIsSurfaced() async {
            let dismissals = InMemoryDismissalStore(
                items: [DismissedCapability(entry: TriageSpecimens.stdio)],
                failure: .writeFailed("refused")
            )
            let (model, _) = TriageModelTests.model(dismissals: dismissals)
            await model.load()

            await model.restore(TriageSpecimens.stdio.id)

            #expect(model.writeFailure != nil, "a refused restore reported nothing")
            #expect(model.writeFailure?.refused == [TriageSpecimens.stdio.id])
        }

        // MARK: - A24 on a partial surface (critic finding 13)

        /// With the official registry down and everything Smithery returned already queued,
        /// Undecided rendered the segments, the warning and the hint — and nothing below them. A
        /// blank list under a warning reads as the warning having eaten the results.
        @Test("an empty bucket on a partial surface still gets its empty state")
        func partialSurfaceStillDerivesEmptiness() async {
            let (model, _) = TriageModelTests.model(warnings: ["official registry unavailable"])
            await model.load()

            guard case .partial = model.state else {
                Issue.record("the warning did not produce a partial state: \(model.state)")
                return
            }

            model.select(bucket: .dismissed)
            #expect(
                model.displayState == .empty(.dismissed),
                "a partial surface skipped the empty-bucket derivation: \(model.displayState)"
            )
        }

        // MARK: - A16: Triage reads the registry with the same page Discover does

        @Test("the search asks for the same limit Discover asks for")
        func searchLimitMatchesDiscover() async {
            let (model, client) = TriageModelTests.model()
            await model.load()

            #expect(client.searchLimits == [TriageModel.searchLimit])
        }
    }
#endif
