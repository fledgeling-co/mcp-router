#if os(macOS)
    import Foundation
    import MCPRouterKit

    /// What the board *shows*, as against what the model *knows*.
    ///
    /// The subtitle, the clock formatting and the one derived value on the surface — the age — live
    /// here rather than beside the load and subscribe logic. They are the part of the model most
    /// likely to be read by someone checking a claim about what the router observes, and they are
    /// worth finding in one place.
    ///
    /// That sentence was already the whole boundary; it just was not yet the whole file. Everything
    /// the view asks the model for — the filtered result, the options behind the pop-ups, the
    /// selection the keyboard moves, and the one exhaustive `condition` the view switches over —
    /// answers the same question and now lives beside it. `condition` in particular belongs here
    /// rather than next to `load()`: the order its cases are tested in **is** the design, and it is
    /// read by whoever is checking which of §5's nine states a surface can reach.
    ///
    /// Nothing here writes a `private(set)` property. It reads the state, or it writes `filter` and
    /// `selection`, which are `public var` and always were — so the split cost this type no write
    /// barrier, which is the only compiler-enforced protection those properties have in a
    /// single-module target.
    public extension ActivityModel {
        /// The board's subtitle, or nil where nothing has been observed to say.
        func subtitle() -> String? {
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
        ///
        /// `nil` in, `nil` out, and that case is real: a window seeded by a record that arrived on
        /// the stream before the first backfill returned has no `since`, because the router has not
        /// said when its counting window opened and the record's own `ts` is not that answer. The
        /// callers omit the clause rather than inventing one.
        func displaySince(_ raw: String?) -> String? {
            guard let raw else { return nil }
            guard let date = raw.asControlAPIDate else { return raw }
            return Self.timeOfDay.string(from: date)
        }

        /// Internal, not public: it was `private` inside the class before this file existed, and a
        /// `public extension` would otherwise export a formatter as API for no caller that wants it.
        internal static let timeOfDay: DateFormatter = {
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
        func age(of record: CallRecord) -> String {
            guard let date = record.ts.asControlAPIDate else { return "—" }
            return shortAgo(date, from: clock())
        }

        /// The newest loaded record's time of day, for the feed states.
        ///
        /// Named in the copy as *the newest call here* and never as a completeness watermark: the
        /// wire carries no watermark, so a record's timestamp proves one arrived and never that
        /// none was missed.
        var newestTimestamp: String? {
            guard let ts = records?.records.first?.ts, let date = ts.asControlAPIDate else {
                return nil
            }
            return Self.timeOfDay.string(from: date)
        }

        // MARK: - What the view asks it

        /// The records the current filter admits, with the total behind them.
        var result: ActivityResult {
            records?.applying(filter) ?? ActivityResult(visible: [], total: 0)
        }

        var visible: [CallRecord] { result.visible }

        var sessions: [ActivityOption<SessionKey>] { records?.sessions() ?? [] }
        var directories: [ActivityOption<DirectoryKey>] { records?.directories() ?? [] }

        /// The selected record, or nil. Looked up in the **visible** slice, so a filtered-away row
        /// can never feed the inspector.
        var selectedRecord: CallRecord? {
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
        ///
        /// Internal, not public, and explicit for the same reason `timeOfDay` is: inside a
        /// `public extension` an unmarked member is exported, and this is called only by
        /// `filter.didSet`, `load()` and `apply(_:)` — all of which stay beside the stored state.
        internal func dropSelectionIfHidden() {
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

        /// The one condition the view switches over.
        ///
        /// A single exhaustive derivation rather than a chain of `if`s in the body: the order these
        /// are tested in **is** the design, and spread across a view it drifts. A total failure with
        /// nothing loaded outranks everything because there is nothing to show; a feed problem over
        /// a good history outranks the populated case because the list alone would look complete.
        var condition: ActivityCondition {
            if let failure, records == nil {
                switch failure {
                case .routerNotRunning: return .offline(failure)
                case .unauthorized: return .unauthorized(failure)
                case .malformedResponse, .server, .transport: return .error(failure)
                }
            }
            guard let records else { return .loading }
            // The mirror of the partial below: there are rows on screen and the history behind them
            // failed to reload. Not gated on `phase == .live` — a reconnect that fails leaves the
            // phase wherever the new subscription got to, and gating on one value put the board back
            // on `.populated` with a stale list and no banner.
            if let failure { return .historyUnavailable(failure) }
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
        func message(for condition: ActivityCondition) -> StateMessage? {
            switch condition {
            case .populated, .loading:
                nil
            case .empty:
                ActivityCopy.empty(since: displaySince(records?.since))
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
        var filtersEnabled: Bool {
            guard let records else { return false }
            return !records.isEmpty
        }

        // MARK: - Selection, as the keyboard moves it

        func moveSelection(by offset: Int) {
            let rows = visible
            guard !rows.isEmpty else { return }
            guard let selection, let index = rows.firstIndex(where: { $0.id == selection }) else {
                selection = offset >= 0 ? rows.first?.id : rows.last?.id
                return
            }
            let next = min(max(index + offset, 0), rows.count - 1)
            self.selection = rows[next].id
        }

        func clearSelection() {
            selection = nil
        }

        func clearFilters() {
            filter.clear()
        }
    }
#endif
