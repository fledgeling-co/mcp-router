#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// The Activity board's model: its two independent sources, its conditions, and the sentences it
    /// is allowed to say about them.
    ///
    /// None of these needs a window. The board's real defects are here — in which condition wins
    /// when two are true, in what a sentence claims about a field, and in whether a filter change
    /// costs a request — and every one of them is checkable without rendering anything.
    @MainActor
    @Suite("Activity — the board's model")
    struct ActivityModelTests {
        static let now = Date(timeIntervalSince1970: 1_755_166_918)

        static func model(
            _ scenario: FixtureControlAPIClient.Scenario = .populated,
            source: (any ActivityEventSource)? = nil
        ) -> ActivityModel {
            ActivityModel(
                client: FixtureControlAPIClient(scenario),
                source: source,
                clock: { now }
            )
        }

        static func record(
            ts: String = "2026-08-14T09:41:58.412Z",
            server: String = "obscura",
            tool: String = "browser_navigate",
            ok: Bool = true,
            ms: Int = 42,
            cold: Bool = false,
            pid: Int? = 51310,
            cwd: String? = "/Users/x/Dev/mcp-router",
            project: String? = "mcp-router",
            client: String? = "claude",
            err: String? = nil
        ) -> CallRecord {
            CallRecord(
                ts: ts, server: server, tool: tool, ok: ok, ms: ms, cold: cold,
                pid: pid, cwd: cwd, project: project, client: client, err: err
            )
        }

        // MARK: - B18: filtering is client-side, and that claim is falsifiable

        @Test("changing a filter issues no request to the router")
        func filteringCostsNoRequest() async {
            let subject = Self.model()
            await subject.load()
            let afterLoad = subject.requestCount
            #expect(afterLoad == 1)

            subject.filter.session = subject.sessions.first?.key
            subject.filter.directory = subject.directories.first?.key
            subject.clearFilters()

            #expect(
                subject.requestCount == afterLoad,
                "a filter that refetches makes the backfill and the live half disagree"
            )
        }

        @Test("the backfill asks for the whole ring and applies no server-side filter")
        func backfillIsUnfiltered() async throws {
            let recorder = RecordingUsageClient()
            let subject = ActivityModel(client: recorder, source: nil, clock: { Self.now })
            await subject.load()

            let call = try #require(await recorder.calls.first)
            #expect(call.limit == ActivityRecords.capacity)
            #expect(call.server == nil, "the stream is unfiltered; narrowing the backfill diverges them")
            #expect(call.cwd == nil)
        }

        // MARK: - B31 / F30-F32: which condition wins when two are true

        @Test("nothing loaded and nothing failed is loading, not empty")
        func nilIsNotEmpty() {
            #expect(Self.model().condition == .loading)
        }

        @Test("the router not running replaces the board rather than showing an empty log")
        func offlineOutranksEverything() async {
            let subject = Self.model(.offline)
            await subject.load()
            #expect(subject.condition == .offline(.routerNotRunning))
        }

        @Test("a dropped feed over a good history is partial, and a first failure is not")
        func droppedAndNeverConnectedAreDifferentStates() async {
            let dropped = Self.model()
            await dropped.load()
            dropped.apply(phase: .live)
            dropped.apply(phase: .disconnected)
            #expect(dropped.condition == .partial(.dropped))

            let never = Self.model()
            await never.load()
            never.apply(phase: .disconnected)
            #expect(
                never.condition == .partial(.neverConnected),
                "a feed that never ran has no gap to have missed, and says so differently"
            )
            #expect(
                dropped.message(for: dropped.condition)?.title
                    != never.message(for: never.condition)?.title
            )
        }

        /// F30: retrying is information; only a spent ladder earns a control.
        @Test("only the given-up feed states offer a reconnect button")
        func onlyGivenUpOffersAButton() {
            #expect(ActivityCopy.partialReconnecting(newest: nil).actionLabel == nil)
            #expect(ActivityCopy.partialDisconnected(newest: nil).actionLabel == ActivityCopy.reconnect)
            #expect(ActivityCopy.neverConnected().actionLabel == ActivityCopy.reconnect)
        }

        /// The mirror of partial: a failed reload must not discard a subscription that is delivering.
        @Test("a failed history over a live feed keeps the rows and names the missing half")
        func historyFailureDoesNotDiscardALiveFeed() async {
            let subject = ActivityModel(
                client: FailingUsageClient(),
                source: nil,
                clock: { Self.now }
            )
            subject.apply(Self.record())
            subject.apply(phase: .live)
            await subject.load()

            #expect(subject.visible.count == 1, "the live row survived a failed reload")
            guard case .historyUnavailable = subject.condition else {
                Issue.record("expected historyUnavailable, got \(subject.condition)")
                return
            }
        }

        @Test("a reload that fails does not throw away a history that had loaded")
        func failedReloadKeepsWhatLoaded() async {
            let subject = Self.model()
            await subject.load()
            let loaded = subject.visible.count
            #expect(loaded > 0)

            let failing = ActivityModel(client: FailingUsageClient(), source: nil, clock: { Self.now })
            for record in subject.visible {
                failing.apply(record)
            }
            await failing.load()
            #expect(failing.visible.count == loaded)
        }

        // MARK: - B20: the two sources overlap, and the merge keeps both halves

        @Test("a record that arrived on the stream survives the backfill that follows it")
        func backfillMergesRatherThanReplaces() async {
            let subject = Self.model()
            // A call the recording does not contain, delivered before the fetch returns.
            subject.apply(Self.record(ts: "2026-08-14T09:59:59.000Z", tool: "arrived_first"))
            await subject.load()
            #expect(
                subject.visible.contains { $0.tool == "arrived_first" },
                "replacing the window would silently drop every call made during the request"
            )
        }

        // MARK: - F35 / F36: the live window rolls under a filter and a selection

        /// The scenario is a **rolling window**, not a second filter change. The earlier version of
        /// this test triggered the fallback by mutating the filter again, which is the one thing a
        /// reader stranded on a vanished option has no reason to do — so it was green while the real
        /// path was unimplemented.
        @Test("a filter whose last record rolls out of the window falls back on the next arrival")
        func vanishedFilterOptionFallsBackAsTheWindowRolls() {
            let subject = ActivityModel(
                client: FixtureControlAPIClient(.empty), source: nil, clock: { Self.now }
            )
            // One session, one record. Filter by it, then push it out of the window.
            let doomed = Self.record(ts: "2026-08-14T09:00:00.000Z", pid: 4242, client: "claude")
            subject.apply(doomed)
            subject.filter.session = .attributed(pid: 4242)
            #expect(subject.visible.count == 1)

            for index in 0 ..< (ActivityRecords.capacity + 1) {
                subject.apply(
                    Self.record(ts: "2026-08-14T10:00:\(index).000Z", tool: "t\(index)", pid: 7777)
                )
            }

            #expect(
                subject.filter.session == nil,
                "the window rolled the filtered session away and the board stayed filtered by it"
            )
            #expect(!subject.visible.isEmpty, "the reader can see the list again")
        }

        // MARK: - The keyboard, at the level it is decided

        @Test("arrow keys move within the visible rows and stop at both ends")
        func selectionMovesAndClamps() async {
            let subject = Self.model()
            await subject.load()
            let rows = subject.visible
            #expect(rows.count > 2)

            subject.moveSelection(by: 1)
            #expect(subject.selection == rows.first?.id, "no selection, down, selects the newest")

            subject.moveSelection(by: -1)
            #expect(subject.selection == rows.first?.id, "up at the top stays")

            for _ in 0 ..< (rows.count + 5) {
                subject.moveSelection(by: 1)
            }
            #expect(subject.selection == rows.last?.id, "down past the end stays")

            subject.clearSelection()
            #expect(subject.selection == nil)
        }

        @Test("the keyboard does nothing at all on an empty board rather than selecting a ghost")
        func selectionOnAnEmptyBoard() async {
            let subject = Self.model(.empty)
            await subject.load()
            subject.moveSelection(by: 1)
            #expect(subject.selection == nil)
        }

        // MARK: - B23: a malformed event does not tear the board down

        @Test("the stream's phases drive the board and its records accumulate")
        func replaySourceDrivesTheBoard() async {
            let events: [StreamEvent] = [
                .phase(.live),
                .record(Self.record(ts: "2026-08-14T10:00:00.000Z", tool: "one")),
                .record(Self.record(ts: "2026-08-14T10:00:01.000Z", tool: "two")),
                .phase(.reconnecting)
            ]
            let subject = Self.model(source: ReplayActivityEventSource(events))
            await subject.load()
            await subject.subscribe()

            #expect(subject.phase == .reconnecting)
            #expect(subject.hasEverConnected)
            #expect(subject.visible.contains { $0.tool == "one" })
            #expect(subject.condition == .partial(.reconnecting))
        }

        @Test("no feed configured is not a dropped feed")
        func noSourceIsNotADisconnection() async {
            let subject = Self.model(source: nil)
            await subject.load()
            await subject.subscribe()
            #expect(subject.phase == nil, "a reconnect button with nothing to reconnect to")
            #expect(subject.condition == .populated)
        }

        // MARK: - The one derivation on the surface

        @Test("the age is derived from ts against the clock, and never goes negative")
        func ageIsDerivedAndFloored() {
            let subject = Self.model()
            let future = ISO8601DateFormatter().string(
                from: Self.now.addingTimeInterval(3600)
            )
            #expect(subject.age(of: Self.record(ts: future)) == "now", "clock skew, not a fault")
            #expect(subject.age(of: Self.record(ts: "not a timestamp")) == "—")
        }
    }
#endif
