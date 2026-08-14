#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// What the board's **record window** does when its two independent sources interact badly — run
    /// in series instead of together, merged in the wrong order, or reloaded over a ring that has
    /// rolled forward underneath it.
    ///
    /// Their own suite because they share a subject the rest of the model tests do not: a history from
    /// `GET /usage` and a live half from `GET /usage/stream` that must end up as one correctly ordered
    /// list. The *subscription's* own lifecycle — which taps are refused, which teardowns are ignored
    /// — is `ActivityReconnectTests`, and both build from `ActivityFixture`. Every defect below was
    /// green code with no coverage of any kind.
    @MainActor
    @Suite("Activity — the two sources, interacting badly")
    struct ActivityRecoveryTests {
        private typealias Fixture = ActivityFixture

        // MARK: - The blockers the completeness critic found

        /// The backfill and the subscription run **together**. In series, every call the router
        /// records between the snapshot returning and the socket opening is lost: too old for the
        /// stream, too new for the response.
        @Test("start runs the backfill and the subscription concurrently")
        func startIsConcurrent() async {
            let events: [StreamEvent] = [
                .phase(.live),
                .record(Fixture.record(ts: "2026-08-14T23:00:00.000Z", tool: "arrived_during_fetch"))
            ]
            let subject = Fixture.model(source: ReplayActivityEventSource(events))
            await subject.start()
            #expect(subject.phase == .live)
            #expect(subject.visible.contains { $0.tool == "arrived_during_fetch" })
            #expect(subject.visible.count > 1, "the backfill landed too")
        }

        /// The merge kept the *first* `capacity` records, so once the backfill filled the window
        /// every streamed record was truncated away on any reload.
        @Test("a reload with a full backfill keeps the records the stream delivered")
        func reloadDoesNotTruncateTheLiveHalf() async {
            let full = (0 ..< ActivityRecords.capacity).map {
                Fixture.record(ts: "2026-08-14T08:00:\($0).000Z", tool: "backfilled\($0)")
            }
            let subject = ActivityModel(
                client: StaticUsageClient(records: full), source: nil, clock: { Fixture.now }
            )
            await subject.load()
            #expect(subject.visible.count == ActivityRecords.capacity)

            subject.apply(Fixture.record(ts: "2026-08-14T23:59:59.000Z", tool: "streamed"))
            await subject.load()

            #expect(
                subject.visible.contains { $0.tool == "streamed" },
                "a full backfill pushed the live half off the end of the merge"
            )
            #expect(subject.visible.first?.tool == "streamed", "and it is still the newest")
        }

        // MARK: - The hole that fix left open

        /// **The mirror of the truncation bug, and the one its fix opened.**
        ///
        /// `merge` prepended *every* held record the response did not carry, on the stated ground
        /// that anything held and not returned "arrived after the fetch began". That is only true at
        /// the head of the window. `GET /usage` returns a contiguous newest-first slice of the ring
        /// (`recent()` is `ring.slice(-limit).reverse()`), so when the ring has rolled forward the
        /// held records missing from the response are the ones that rolled *out* — the oldest calls
        /// the board holds. Prepending those put them at the top of a newest-first log.
        ///
        /// Reachable by pressing Reconnect on a busy router: the feed drops, the router keeps
        /// working, and the reload promotes the twenty oldest rows above the twenty newest.
        @Test("a reload over a rolled-forward ring does not promote the oldest calls to the top")
        func reloadOverARolledRingKeepsNewestFirst() async {
            let newest = ActivityRecords.capacity - 1
            let rolled = 20
            let subject = ActivityModel(
                client: StaticUsageClient(windows: [
                    Fixture.window(newest: newest),
                    Fixture.window(newest: newest + rolled)
                ]),
                source: nil,
                clock: { Fixture.now }
            )
            await subject.load()
            #expect(subject.visible.first?.tool == "call\(newest)")

            await subject.load()

            #expect(
                subject.visible.first?.tool == "call\(newest + rolled)",
                "the newest call the router returned is not the newest row"
            )
            #expect(
                !subject.visible.prefix(rolled).contains { $0.tool == "call0" },
                "a call that rolled out of the router's ring was promoted to the top"
            )
            #expect(
                subject.visible.count == ActivityRecords.capacity,
                "the window is still full"
            )
        }

        /// The same defect at its extreme: the ring rolled further than the window, so the two share
        /// no record at all. Prepending the held window then truncated the entire response away and
        /// left a board showing only calls the router no longer has.
        @Test("a reload whose window shares nothing with the held one shows the router's window")
        func reloadWithNoOverlapPrefersTheResponse() async {
            let newest = ActivityRecords.capacity - 1
            let subject = ActivityModel(
                client: StaticUsageClient(windows: [
                    Fixture.window(newest: newest),
                    Fixture.window(newest: newest + ActivityRecords.capacity + 10)
                ]),
                source: nil,
                clock: { Fixture.now }
            )
            await subject.load()
            await subject.load()

            #expect(
                subject.visible.first?.tool == "call\(newest + ActivityRecords.capacity + 10)",
                "the response's newest record is the newest row"
            )
            #expect(
                !subject.visible.contains { $0.tool == "call0" },
                "records the router's ring no longer carries are still on the board"
            )
        }

        // MARK: - The second critic's findings

        /// **A record the router's ring no longer carries must not be pinned to the top forever.**
        ///
        /// The first `streamArrivals` prune was `subtracting(returned).intersection(kept)`, which
        /// keeps exactly the ids the merge just promoted — they are in `kept` and, by construction,
        /// not in `returned`. So a record that arrived on the feed and then rolled out of the ring
        /// was promoted to row 0 of a newest-first log by every subsequent reload, for the life of
        /// the board, and the feed banner went on to name its timestamp as the newest call held.
        ///
        /// The suite had {rolled ring, no stream} and {stream, ring not rolled}; this is the cell
        /// where the two meet, which is the one the provenance rewrite introduced.
        @Test("a feed record that rolled out of the ring is not promoted, and is not promoted twice")
        func rolledOutStreamArrivalIsNotPinnedToTheTop() async {
            let old = Fixture.record(ts: "2026-08-14T09:00:00.000Z", tool: "rolled_out_of_the_ring")
            // The router's window has moved entirely past `old` — it shares no record with it.
            let fresh = (0 ..< 3).map {
                Fixture.record(ts: "2026-08-14T09:3\($0):00.000Z", tool: "current\($0)")
            }
            let client = StaticUsageClient(records: Array(fresh.reversed()))
            let subject = ActivityModel(client: client, source: nil, clock: { Fixture.now })
            subject.beginSession()

            subject.apply(old)
            #expect(subject.visible.count == 1)

            await subject.load()
            #expect(
                subject.visible.first?.tool != "rolled_out_of_the_ring",
                "a record the router no longer carries is sitting above its current window"
            )
            #expect(
                !subject.visible.contains { $0.tool == "rolled_out_of_the_ring" },
                "the rolled-out record is still on the board"
            )

            // And again: the first version survived its own prune, so a second reload re-promoted it.
            await subject.load()
            #expect(
                !subject.visible.contains { $0.tool == "rolled_out_of_the_ring" },
                "the rolled-out record came back on a second reload — the set was not cleared"
            )
        }

        /// A record that arrives *while* the backfill is in flight is a different case, and is kept.
        /// Stated beside the test above so the fix cannot be "drop everything the response omits".
        @Test("a record that arrived during the fetch is still kept")
        func arrivalDuringTheFetchSurvivesTheMerge() async {
            let subject = Fixture.model(
                source: ReplayActivityEventSource([
                    .phase(.live),
                    .record(Fixture.record(ts: "2026-08-14T23:00:00.000Z", tool: "arrived_during"))
                ])
            )
            await subject.start()
            #expect(subject.visible.contains { $0.tool == "arrived_during" })
        }

        /// Finding 6: one session reported with a client name for some calls and without it for
        /// others must be **one** menu entry with the whole count, not two with half each.
        @Test("a session is one option even when the router names its client inconsistently")
        func sessionIdentityIgnoresTheClientName() {
            let subject = ActivityModel(
                client: FixtureControlAPIClient(.empty), source: nil, clock: { Fixture.now }
            )
            subject.apply(Fixture.record(ts: "…1", pid: 900, client: "claude"))
            subject.apply(Fixture.record(ts: "…2", pid: 900, client: nil))
            subject.apply(Fixture.record(ts: "…3", pid: 900, client: "claude"))

            let sessions = subject.sessions
            #expect(sessions.count == 1, "the client name split one session into \(sessions.count)")
            #expect(sessions.first?.calls == 3)
            #expect(sessions.first?.label.contains("900") == true)
        }

        @Test("the selection follows the record, not the row index, across an insert")
        func selectionFollowsTheRecord() async throws {
            let subject = Fixture.model()
            await subject.load()
            // `try #require`, not `try?`: the optional form passes when the value is nil, which is
            // the exact failure this is written to catch.
            let chosen = try #require(subject.visible.first)
            subject.selection = chosen.id
            subject.apply(Fixture.record(ts: "2026-08-14T23:59:59.000Z", tool: "brand_new"))
            #expect(subject.selection == chosen.id)
            #expect(subject.selectedRecord?.id == chosen.id)
        }

        @Test("a selection the filter hides is cleared rather than left describing an unseen row")
        func filteringClearsAHiddenSelection() async throws {
            let subject = Fixture.model()
            await subject.load()
            let orphan = try #require(subject.visible.first { $0.pid == nil })
            subject.selection = orphan.id
            subject.filter.session = subject.sessions.first { $0.key != .unattributed }?.key
            #expect(subject.selection == nil)
            #expect(subject.selectedRecord == nil)
        }
    }
#endif
