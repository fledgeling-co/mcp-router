#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Observation

    /// The Activity board's state, and the one place it talks to the router.
    ///
    /// **This board owns the call stream, and the shell deliberately does not.** `ShellModel`
    /// constructs its `ServerStateTracker` poll-only and says why: "the call stream is what M2's
    /// Activity board is for, and attaching it here would put a second subscription behind a surface
    /// that renders nothing from it." So the subscription is taken here, scoped to the board's
    /// `.task`, and closed when the reader navigates away. Nothing polls `/servers` from here — the
    /// shell already does, once.
    ///
    /// **Two independent sources, and therefore two independent failures.** The history comes from
    /// `GET /usage` and the live half from `GET /usage/stream`, and either can fail while the other
    /// works. A board with one failure story answers a dropped stream by throwing away a good
    /// history, or answers a failed reload by discarding a subscription that is still delivering.
    /// `ActivityCondition` has a case for each direction because both are real.
    ///
    /// Two boundaries this type does not cross. It speaks only the loopback control API through
    /// F3's client, opening no socket, no file and no process of its own. And it renders no figure
    /// the router did not report: the count is the loaded window's size, the "since" is
    /// `UsageResponse.since`, every duration is `CallRecord.ms`. There is no rate, no projection and
    /// no saving anywhere in it.
    ///
    /// The clock is injected for the same reason `ShellModel`'s and `ReadoutModel`'s are — every
    /// relative time on this surface is measured from *now*, and a test that has to sleep to reach a
    /// boundary is a test that proves nothing.
    @MainActor
    @Observable
    public final class ActivityModel {
        @ObservationIgnored private let client: any ControlAPIClient
        @ObservationIgnored private let source: (any ActivityEventSource)?
        /// Internal rather than private so `ActivityModel+Presentation` can read it. In an extension
        /// `clock` would otherwise resolve to the C library's `clock()`, which compiles and is a
        /// different thing entirely.
        @ObservationIgnored let clock: @MainActor () -> Date

        /// **`nil` is not empty.** Empty means the router answered and has logged nothing; nil means
        /// nothing has answered yet. A board that cannot tell them apart shows "No calls yet" while
        /// it is still loading, which is a considered statement about a question nobody has asked.
        public private(set) var records: ActivityRecords?

        /// The typed failure of the last history load, where there was one.
        public private(set) var failure: ControlAPIError?

        /// The open dialog, or none. One case today; an enum rather than a `Bool` because the next
        /// one is a different dialog and not a second flag.
        public var sheet: Sheet?

        /// The typed failure of the last **write**, kept apart from `failure` above, which is the
        /// last read's. A dialog that reported a load error would be answering a question the user
        /// did not ask, and a board that folded the two would lose which one is stale.
        public private(set) var writeError: ControlAPIError?

        public enum Sheet: Equatable, Sendable, Identifiable {
            case resetHistory

            public var id: String {
                switch self {
                case .resetHistory: "reset"
                }
            }
        }

        /// What the live feed is doing. `nil` until the subscription reports anything.
        public private(set) var phase: StreamPhase?

        /// Whether the feed has ever reached `.live`.
        ///
        /// This is what separates "the feed dropped" from "the feed never connected". Both land on
        /// `.disconnected` after the retry ladder, and the two want different sentences: one implies
        /// a gap in a feed that was running, the other has nothing to have missed yet.
        public private(set) var hasEverConnected = false

        public var filter = ActivityFilter() {
            didSet {
                guard oldValue != filter else { return }
                dropSelectionIfHidden()
            }
        }

        /// The selected row, by `CallRecord.id`, which is stable across reorders — so the selection
        /// follows the *record* when a live insert pushes it down, never the index.
        public var selection: CallRecord.ID?

        /// How many requests this model has issued. Exposed so a test can prove that changing a
        /// filter issues none — the claim that filtering is client-side is otherwise unfalsifiable.
        public private(set) var requestCount = 0

        /// The ids the **feed** delivered that no response has yet accounted for.
        ///
        /// This is the provenance `merge` needs and position cannot supply: a held record in this
        /// set arrived after the last snapshot, so it is newer than any response now landing. One
        /// that is not in it came from an older response and is superseded.
        ///
        /// It is pruned on every merge to the ids the merged window actually still holds, so it is
        /// bounded by `ActivityRecords.capacity` rather than growing for the life of the board.
        ///
        /// Internal rather than private for the same reason `clock` is: `ActivityModel+Merge` reads
        /// and empties it, and `private` is file-scoped. It stays `@ObservationIgnored` — it is
        /// provenance the merge rule consults, never anything a view renders.
        @ObservationIgnored var streamArrivals: Set<CallRecord.ID> = []

        public init(
            client: any ControlAPIClient,
            source: (any ActivityEventSource)? = nil,
            clock: @escaping @MainActor () -> Date = { Date() }
        ) {
            self.client = client
            self.source = source
            self.clock = clock
        }

        // MARK: - Talking to the router

        /// The backfill: one request, for the whole of the router's ring.
        ///
        /// The endpoint's `server` and `cwd` parameters are deliberately not used. The stream is
        /// unfiltered, so narrowing the backfill server-side would give a board whose two halves
        /// disagree — see `ActivityFilter`.
        ///
        /// A record that arrived on the stream before this returned is **kept**: the response is
        /// merged into the existing window rather than replacing it, and `ActivityRecords`
        /// de-duplicates by id. Replacing would silently drop every call made during the request.
        /// Discard the router's recorded call history.
        ///
        /// The same act `CleanupBoardModel.resetHistory()` performs, against the same endpoint, and
        /// deliberately not a second implementation of it — but it is reachable from here because
        /// `prototype.html:716` puts the entry point in **this** board's header, outside the rows
        /// conditional, so the design specifies it in the empty state as well as the populated one.
        /// The build drew no control there at all: DEF-016.
        ///
        /// Reloads rather than emptying the local records, because the router is what decides what
        /// the history now is — `usage.reset()` also moves the observation window, and a board that
        /// zeroed its own list would show the new count against the old window.
        public func resetHistory() async {
            writeError = nil
            do {
                _ = try await client.resetUsage()
                sheet = nil
                await load()
            } catch {
                writeError = error
            }
        }

        public func load() async {
            requestCount += 1
            // **Only the newest request may write.** `isReconnecting` serialises reconnects against
            // each other and against nothing else, and `start()` does not consult it — so a board
            // whose stream endpoint refuses quickly shows the disconnected banner while the first
            // `GET /usage` is still outstanding, and a reader who taps Reconnect then has two
            // requests in flight. Whichever *returned* second used to win, so an older window could
            // land on top of a newer one and roll the log backwards, and `merge` would run its
            // provenance check against the wrong response.
            loadGeneration += 1
            let generation = loadGeneration
            do {
                let response = try await client.usage(
                    limit: ActivityRecords.capacity,
                    server: nil,
                    cwd: nil
                )
                guard generation == loadGeneration else { return }
                records = merge(response)
                failure = nil
            } catch {
                guard generation == loadGeneration else { return }
                // A failed reload does not discard a history that did load, and does not discard a
                // stream that is delivering. The board keeps what it has and names the part that is
                // missing; throwing the rows away would lose the half that arrived, which is the
                // opposite of what §5's partial asks for.
                failure = error
            }
            dropSelectionIfHidden()
        }

        /// Which `load()` is allowed to write. Bumped on entry; a response whose generation is stale
        /// is discarded rather than merged.
        @ObservationIgnored private var loadGeneration = 0

        /// The board's whole conversation with the router, with **both** halves in flight at once.
        ///
        /// Running these in series — `await load()` then `await subscribe()` — loses every call the
        /// router records between the snapshot returning and the socket opening. On a cold start
        /// against a busy router that window is however long `GET /usage` takes, and nothing in the
        /// board would ever show those calls: they are too old for the stream and too new for the
        /// response. Started together, the id guard in `ActivityRecords.prepend` does exactly the
        /// job it was written for and the overlap is free.
        public func start() async {
            async let backfill: Void = load()
            async let feed: Void = runFeed()
            _ = await (backfill, feed)
        }

        /// The live subscription, owned here rather than by whichever task happened to start it.
        ///
        /// Two taps used to stack two subscription loops writing into one model. The `isReconnecting`
        /// flag no longer prevents that — it cannot, because it is released while the feed is still
        /// running — so the guarantee is structural instead: there is one slot, and starting a feed
        /// cancels whatever was in it.
        @ObservationIgnored private var feed: Task<Void, Never>?

        /// Starts a fresh subscription, replacing any running one, and awaits it.
        ///
        /// The cancellation handler is what keeps the board's `.task` scoping intact: the work runs
        /// in an unstructured `Task` so that a *later* call can cancel it, and without the handler
        /// that task would outlive the view whose `.task` started it.
        private func runFeed() async {
            let task = replaceFeed()
            await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
        }

        @discardableResult
        private func replaceFeed() -> Task<Void, Never> {
            feed?.cancel()
            let task = Task { [weak self] in await self?.subscribe() ?? () }
            feed = task
            return task
        }

        /// Ends the live subscription, whoever started it.
        ///
        /// `start()`'s own cancellation handler cancels the task **it** installed, which is not
        /// enough on its own: a reconnect replaces the slot, and that replacement is awaited by
        /// nothing, so a reader who presses Reconnect and then navigates away would leave a feed
        /// running behind a board that is gone.
        public func stopFeed() {
            feed?.cancel()
            feed = nil
            // The phase described a subscription that no longer exists. Left set, a board rebuilt on
            // the next visit renders "live" in its subtitle over a feed that has not connected yet —
            // a claim about the router made entirely inside the app.
            phase = nil
        }

        /// Which board currently owns this model, and whether one does at all.
        ///
        /// The model outlives the view: `ShellModel` holds it as a stored lazy so the log survives a
        /// destination switch, while `ContentZone` rebuilds `ActivityBoard` on every switch. A bare
        /// `stopFeed()` from `.onDisappear` therefore has no idea *which* board is asking, and
        /// SwiftUI does not promise that an outgoing view's `.onDisappear` runs before an incoming
        /// view's `.task`. If it runs second, an unguarded teardown cancels the feed the new board
        /// just started and nothing re-arms it: a full list, no live feed, and — before `stopFeed`
        /// also cleared it — a subtitle still reading "live".
        @ObservationIgnored private var session = 0
        @ObservationIgnored private var isAttached = false

        /// Claims the model for a board that is appearing, and returns the token it must hand back.
        @discardableResult
        public func beginSession() -> Int {
            session += 1
            isAttached = true
            return session
        }

        /// Releases the model, ignoring a token that a superseded board is holding.
        public func endSession(_ token: Int) {
            guard token == session else { return }
            isAttached = false
            stopFeed()
        }

        /// Consume the live feed until the task is cancelled or the stream gives up.
        public func subscribe() async {
            guard let source else {
                // No feed was configured. That is not the same as a feed that dropped, and saying
                // `.disconnected` here would put a "reconnect" button on a board with nothing to
                // reconnect to.
                return
            }
            for await event in source.events() {
                if Task.isCancelled { return }
                switch event {
                case let .record(record):
                    apply(record)
                case let .phase(newPhase):
                    apply(phase: newPhase)
                }
            }
        }

        /// One phase from the feed.
        ///
        /// Exposed so a test can drive an *ordering* — `.live` then `.disconnected` is a different
        /// state from `.disconnected` alone, and no scenario can express the difference because the
        /// difference is the sequence rather than the value.
        public func apply(phase newPhase: StreamPhase) {
            if newPhase == .live { hasEverConnected = true }
            phase = newPhase
        }

        /// What the reconnect button does, and it is deliberately both halves.
        ///
        /// `ControlEventStream` calls `continuation.finish()` after `.disconnected`, so a spent
        /// stream needs a new subscription. Reloading the history at the same time is what closes
        /// the gap: records that arrived while the feed was down were never streamed to this board,
        /// and only a fresh `GET /usage` can bring them back. Subscribing without reloading would
        /// leave a hole the board could not see and would not mention.
        public func reconnect() async {
            guard !isReconnecting else { return }
            // The board this was pressed on may already be gone: `FeedBanner` runs the action in an
            // unstructured `Task`, so a reader who presses Reconnect and immediately switches
            // destination leaves it to resume after `endSession` has torn the feed down. Installing
            // a subscription then would put a live feed behind a board nobody is looking at, which
            // is the thing the teardown had just prevented.
            guard isAttached else { return }
            isReconnecting = true
            defer { isReconnecting = false }
            // **The subscription is started, not awaited, and that is the whole fix.** This read
            // `await start()` under a `defer`, which is dead after the first success: the real
            // `ControlEventStream.events()` loops until its retry ladder is exhausted and only then
            // finishes its continuation, so `start()` does not return while the connection is
            // healthy. The deferred clear therefore ran when the feed *next died* rather than when
            // the reconnect completed, leaving `isReconnecting` true across a working feed and
            // making every later tap hit the guard above and do nothing. Only the backfill is
            // awaited here, because only the backfill has an end.
            //
            // Stacking is still ruled out — `replaceFeed()` cancels the running subscription before
            // installing the new one, which is a stronger guarantee than the flag ever gave.
            replaceFeed()
            // The phase is **not** cleared first. It used to be, and a reload that then failed left
            // `condition` on `.populated` — a stale list, a subtitle reading "connecting", no banner
            // and no way back. It is replaced by whatever the new subscription reports.
            await load()
        }

        /// Whether a reconnect is already running.
        public private(set) var isReconnecting = false

        /// One arriving record. Exposed so a test drives the model directly rather than through a
        /// stream it also has to build.
        @discardableResult
        public func apply(_ record: CallRecord) -> Bool {
            // Recorded before either branch: this record's provenance is the feed whether it seeds
            // the window or is prepended to one, and `merge` reads exactly this to decide which
            // held records survive a later response.
            streamArrivals.insert(record.id)
            guard var held = records else {
                // A record arriving before the backfill landed is still a real call. It seeds the
                // window rather than being dropped, and the backfill de-duplicates against it.
                //
                // `since: nil` deliberately. The router has not said when its counting window
                // opened, and this record's own `ts` is not that answer — it is when one call
                // happened, which is a later moment by an unknown amount. The subtitle omits the
                // clause until a response supplies the fact.
                records = ActivityRecords(records: [record], since: nil)
                return true
            }
            let inserted = held.prepend(record)
            records = held
            // **Bounded by the window, not by uptime.** `merge` empties this set, but a board whose
            // feed never drops never merges again — `load()` is reached only from `start()` and
            // `reconnect()` — so on a long-lived healthy board this would otherwise take one id per
            // call for as long as the app is open. Only ids still in the window can ever be read
            // from it, and `prepend` evicts at capacity, so re-deriving against what is actually
            // held is both correct and a hard ceiling. Done on the threshold rather than per record
            // because the intersection is O(n) and this runs on every arriving call.
            if streamArrivals.count > ActivityRecords.capacity {
                streamArrivals.formIntersection(held.records.map(\.id))
            }
            if inserted {
                // The reason this is here and not only in `filter.didSet`: the window rolls. A
                // record arriving at capacity drops the oldest, and the option the reader filtered
                // by can lose its last loaded record — leaving the board filtered by something its
                // own menu no longer offers, with no way back but Clear filters. The fallback used
                // to be reachable only by changing a filter, which is the one thing a reader in
                // that state has no reason to do.
                //
                // Guarded, because this runs per arriving record and the groupings are O(n): with
                // nothing filtered and nothing selected there is nothing to invalidate.
                if filter.isActive || selection != nil { dropSelectionIfHidden() }
            }
            return inserted
        }
    }
#endif
