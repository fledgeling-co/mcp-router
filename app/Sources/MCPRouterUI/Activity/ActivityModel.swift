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
        @ObservationIgnored private let clock: @MainActor () -> Date

        /// **`nil` is not empty.** Empty means the router answered and has logged nothing; nil means
        /// nothing has answered yet. A board that cannot tell them apart shows "No calls yet" while
        /// it is still loading, which is a considered statement about a question nobody has asked.
        public private(set) var records: ActivityRecords?

        /// The typed failure of the last history load, where there was one.
        public private(set) var failure: ControlAPIError?

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
        public func load() async {
            requestCount += 1
            do {
                let response = try await client.usage(
                    limit: ActivityRecords.capacity,
                    server: nil,
                    cwd: nil
                )
                records = merge(response)
                failure = nil
            } catch {
                // A failed reload does not discard a history that did load, and does not discard a
                // stream that is delivering. The board keeps what it has and names the part that is
                // missing; throwing the rows away would lose the half that arrived, which is the
                // opposite of what §5's partial asks for.
                failure = error
            }
            dropSelectionIfHidden()
        }

        /// Merges a fresh response into whatever is already held, newest first.
        private func merge(_ response: UsageResponse) -> ActivityRecords {
            guard let held = records, !held.isEmpty else { return ActivityRecords(response) }
            // The response is newest-first and so is the window; interleaving by timestamp would
            // need a total order the wire does not promise. Concatenating response-then-held and
            // letting the de-duplicating initialiser keep the first sighting of each id preserves
            // the router's own ordering for everything it returned, and keeps anything the stream
            // delivered that the response did not carry.
            let combined = response.records + held.records
            return ActivityRecords(records: combined, since: response.since)
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
            phase = nil
            await load()
            await subscribe()
        }

        /// One arriving record. Exposed so a test drives the model directly rather than through a
        /// stream it also has to build.
        @discardableResult
        public func apply(_ record: CallRecord) -> Bool {
            guard var held = records else {
                // A record arriving before the backfill landed is still a real call. It seeds the
                // window rather than being dropped, and the backfill de-duplicates against it.
                records = ActivityRecords(records: [record], since: record.ts)
                return true
            }
            let inserted = held.prepend(record)
            records = held
            return inserted
        }

        // MARK: - What the view asks it

        /// The records the current filter admits, with the total behind them.
        public var result: ActivityResult {
            records?.applying(filter) ?? ActivityResult(visible: [], total: 0)
        }

        public var visible: [CallRecord] { result.visible }

        public var sessions: [ActivityOption<SessionKey>] { records?.sessions() ?? [] }
        public var directories: [ActivityOption<DirectoryKey>] { records?.directories() ?? [] }

        /// The selected record, or nil. Looked up in the **visible** slice, so a filtered-away row
        /// can never feed the inspector.
        public var selectedRecord: CallRecord? {
            guard let selection else { return nil }
            return visible.first { $0.id == selection }
        }

        /// Clears a selection that the current filter hides, and clears a filter whose option no
        /// longer exists.
        ///
        /// The second is a live-session condition rather than a hypothetical: options exist only
        /// while a loaded record carries their value, and the window rolls, so the pid you filtered
        /// on can lose its last record and vanish from its own pop-up. Left alone the board would
        /// sit filtered by something the menu no longer offers, with no way back except Clear
        /// filters — so the filter falls back to "all" and the reader sees the list refill.
        private func dropSelectionIfHidden() {
            if let session = filter.session, !sessions.contains(where: { $0.key == session }) {
                filter.session = nil
            }
            let offered = directories
            if let directory = filter.directory, !offered.contains(where: { $0.key == directory }) {
                filter.directory = nil
            }
            if let selection, !visible.contains(where: { $0.id == selection }) {
                self.selection = nil
            }
        }

        /// The board's subtitle, or nil where nothing has been observed to say.
        public func subtitle() -> String? {
            guard let records else { return nil }
            return ActivityCopy.subtitle(
                count: records.count,
                since: displaySince(records.since),
                feed: ActivityCopy.feedLabel(phase)
            )
        }

        /// `since` as a clock time, or the raw value when it is not a timestamp this version parses.
        ///
        /// Falling back to the raw string rather than to a placeholder: the router sent something,
        /// and showing it unparsed is honest where showing "—" would discard a fact.
        public func displaySince(_ raw: String) -> String {
            guard let date = raw.asControlAPIDate else { return raw }
            return Self.timeOfDay.string(from: date)
        }

        private static let timeOfDay: DateFormatter = {
            let formatter = DateFormatter()
            formatter.setLocalizedDateFormatFromTemplate("jmm")
            return formatter
        }()

        /// The relative age of one record, at this instant.
        ///
        /// A **derived** value, and the one derivation on this surface: the router sends an absolute
        /// `ts` and this subtracts it from the device clock, which is not the router's clock. It is
        /// derived rather than fabricated — nothing is invented, one observed value is re-expressed
        /// — and the absolute timestamp is in the inspector so the raw fact is never out of reach. A
        /// `ts` in the future (a clock skew, not a fault) reads as "now" rather than as a negative
        /// age, because `shortAgo` floors the interval at zero.
        public func age(of record: CallRecord) -> String {
            guard let date = record.ts.asControlAPIDate else { return "—" }
            return shortAgo(date, from: clock())
        }

        /// The newest loaded record's time of day, for the feed states.
        ///
        /// Named in the copy as *the newest call here* and never as a completeness watermark: the
        /// wire carries no watermark, so a record's timestamp proves one arrived and never that
        /// none was missed.
        public var newestTimestamp: String? {
            guard let ts = records?.records.first?.ts, let date = ts.asControlAPIDate else {
                return nil
            }
            return Self.timeOfDay.string(from: date)
        }

        /// The one condition the view switches over.
        ///
        /// A single exhaustive derivation rather than a chain of `if`s in the body: the order these
        /// are tested in **is** the design, and spread across a view it drifts. A total failure with
        /// nothing loaded outranks everything because there is nothing to show; a feed problem over
        /// a good history outranks the populated case because the list alone would look complete.
        public var condition: ActivityCondition {
            if let failure, records == nil {
                switch failure {
                case .routerNotRunning: return .offline(failure)
                case .unauthorized: return .unauthorized(failure)
                case .malformedResponse, .server, .transport: return .error(failure)
                }
            }
            guard let records else { return .loading }
            // The mirror of the partial below: the feed is delivering and the history is not.
            if let failure, phase == .live { return .historyUnavailable(failure) }
            if records.isEmpty { return .empty }
            if result.isFilteredToNothing { return .filteredToNothing(total: result.total) }
            switch phase {
            case .reconnecting: return .partial(.reconnecting)
            case .disconnected: return hasEverConnected ? .partial(.dropped) : .partial(.neverConnected)
            case .live, nil: return .populated
            }
        }

        /// The message the current condition renders, where it renders one.
        ///
        /// Offline, unauthorised and error read their strings **from `ControlAPIError`** rather than
        /// from `ActivityCopy`: §6 asks for one wording per state across both devices, and a second
        /// copy of "The router isn't running" written here would be a second thing to keep in step.
        public func message(for condition: ActivityCondition) -> StateMessage? {
            switch condition {
            case .populated, .loading:
                nil
            case .empty:
                ActivityCopy.empty(since: displaySince(records?.since ?? ""))
            case let .filteredToNothing(total):
                ActivityCopy.filteredToNothing(total: total)
            case let .partial(feed):
                switch feed {
                case .reconnecting: ActivityCopy.partialReconnecting(newest: newestTimestamp)
                case .dropped: ActivityCopy.partialDisconnected(newest: newestTimestamp)
                case .neverConnected: ActivityCopy.neverConnected()
                }
            case let .historyUnavailable(error):
                ActivityCopy.historyUnavailable(error: error)
            case let .offline(error), let .unauthorized(error), let .error(error):
                StateMessage(
                    title: error.headline,
                    detail: error.advice,
                    actionLabel: error.actionLabel
                )
            }
        }

        /// Whether the filters have anything to filter. §3.4: they dim in place with their reason
        /// rather than disappearing.
        public var filtersEnabled: Bool {
            guard let records else { return false }
            return !records.isEmpty
        }

        // MARK: - Selection, as the keyboard moves it

        public func moveSelection(by offset: Int) {
            let rows = visible
            guard !rows.isEmpty else { return }
            guard let selection, let index = rows.firstIndex(where: { $0.id == selection }) else {
                selection = offset >= 0 ? rows.first?.id : rows.last?.id
                return
            }
            let next = min(max(index + offset, 0), rows.count - 1)
            self.selection = rows[next].id
        }

        public func clearSelection() {
            selection = nil
        }

        public func clearFilters() {
            filter.clear()
        }
    }

    /// What the board is currently showing. One case per designed state.
    ///
    /// An enum rather than a set of booleans, so the view's `switch` cannot compile while ignoring
    /// one — the same reason `SurfaceState` is an enum.
    public enum ActivityCondition: Equatable, Sendable {
        case loading
        case empty
        case populated
        case filteredToNothing(total: Int)
        /// The history is showing and the live half is not arriving.
        case partial(FeedTrouble)
        /// The feed is delivering and the history is not — the mirror of `partial`.
        case historyUnavailable(ControlAPIError)
        case offline(ControlAPIError)
        case unauthorized(ControlAPIError)
        case error(ControlAPIError)

        /// Three ways the feed can be absent, and three different things to say.
        ///
        /// `reconnecting` is information and earns no button — the retry is already running.
        /// `dropped` and `neverConnected` both mean the ladder is spent, and they are separate cases
        /// because one implies a gap in a feed that was working and the other does not.
        public enum FeedTrouble: Equatable, Sendable {
            case reconnecting
            case dropped
            case neverConnected
        }
    }
#endif
