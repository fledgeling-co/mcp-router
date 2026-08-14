#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// The four defects a completeness critic found in the delivered board, each with the test that
    /// would have caught it.
    ///
    /// Their own suite because they share a subject the rest of the model tests do not: what happens
    /// when the board's **two independent sources** interact badly — in series instead of together,
    /// merged in the wrong order, reconnected twice at once, or reloaded into a failure. Every one of
    /// them was green code with no coverage of any kind.
    @MainActor
    @Suite("Activity — the two sources, interacting badly")
    struct ActivityRecoveryTests {
        static let now = Date(timeIntervalSince1970: 1_755_166_918)

        static func model(
            _ scenario: FixtureControlAPIClient.Scenario = .populated,
            source: (any ActivityEventSource)? = nil
        ) -> ActivityModel {
            ActivityModel(client: FixtureControlAPIClient(scenario), source: source, clock: { now })
        }

        static func record(
            ts: String = "2026-08-14T09:41:58.412Z",
            tool: String = "browser_navigate",
            pid: Int? = 51310,
            client: String? = "claude"
        ) -> CallRecord {
            CallRecord(
                ts: ts, server: "obscura", tool: tool, ok: true, ms: 42, cold: false,
                pid: pid, cwd: "/Users/x/Dev/mcp-router", project: "mcp-router",
                client: client, err: nil
            )
        }

        // MARK: - The blockers the completeness critic found

        /// The backfill and the subscription run **together**. In series, every call the router
        /// records between the snapshot returning and the socket opening is lost: too old for the
        /// stream, too new for the response.
        @Test("start runs the backfill and the subscription concurrently")
        func startIsConcurrent() async {
            let events: [StreamEvent] = [
                .phase(.live),
                .record(Self.record(ts: "2026-08-14T23:00:00.000Z", tool: "arrived_during_the_fetch"))
            ]
            let subject = Self.model(source: ReplayActivityEventSource(events))
            await subject.start()
            #expect(subject.phase == .live)
            #expect(subject.visible.contains { $0.tool == "arrived_during_the_fetch" })
            #expect(subject.visible.count > 1, "the backfill landed too")
        }

        /// The merge kept the *first* `capacity` records, so once the backfill filled the window
        /// every streamed record was truncated away on any reload.
        @Test("a reload with a full backfill keeps the records the stream delivered")
        func reloadDoesNotTruncateTheLiveHalf() async {
            let full = (0 ..< ActivityRecords.capacity).map {
                Self.record(ts: "2026-08-14T08:00:\($0).000Z", tool: "backfilled\($0)")
            }
            let subject = ActivityModel(
                client: StaticUsageClient(records: full), source: nil, clock: { Self.now }
            )
            await subject.load()
            #expect(subject.visible.count == ActivityRecords.capacity)

            subject.apply(Self.record(ts: "2026-08-14T23:59:59.000Z", tool: "streamed"))
            await subject.load()

            #expect(
                subject.visible.contains { $0.tool == "streamed" },
                "a full backfill pushed the live half off the end of the merge"
            )
            #expect(subject.visible.first?.tool == "streamed", "and it is still the newest")
        }

        // MARK: - The hole that fix left open

        /// A distinct, ordered timestamp per index, so 520 records have 520 ids.
        static func timestamp(_ index: Int) -> String {
            String(format: "2026-08-14T08:%02d:%02d.000Z", index / 60, index % 60)
        }

        /// `capacity` records, newest first, ending at `newest`.
        static func window(newest: Int) -> [CallRecord] {
            stride(from: newest, through: newest - ActivityRecords.capacity + 1, by: -1)
                .map { record(ts: timestamp($0), tool: "call\($0)") }
        }

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
                    Self.window(newest: newest),
                    Self.window(newest: newest + rolled)
                ]),
                source: nil,
                clock: { Self.now }
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
                    Self.window(newest: newest),
                    Self.window(newest: newest + ActivityRecords.capacity + 10)
                ]),
                source: nil,
                clock: { Self.now }
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

        /// Two taps used to stack two subscription loops writing into one model.
        @Test("a second reconnect while one is running is refused rather than stacked")
        func reconnectIsNotReentrant() async {            let subject = Self.model(source: ReplayActivityEventSource([.phase(.live)]))
            async let first: Void = subject.reconnect()
            async let second: Void = subject.reconnect()
            _ = await (first, second)
            #expect(!subject.isReconnecting, "the guard is released when the reconnect finishes")
            #expect(subject.requestCount <= 2, "a stacked reconnect would issue more")
        }

        /// **The reconnect button was dead after its first success, and every test here missed it.**
        ///
        /// `reconnect()` awaited `start()` under a `defer { isReconnecting = false }`. Against
        /// `ReplayActivityEventSource` that is fine, because a replay finishes after its last event
        /// and `start()` returns — which is why `reconnectIsNotReentrant` above passed over a broken
        /// button. Against the real feed it is not: `ControlEventStream.events()` loops until its
        /// retry ladder is exhausted and only *then* finishes its continuation, so over a healthy
        /// connection `start()` never returns, the deferred clear never runs, and the guard at the
        /// top of `reconnect()` refuses every later tap for the life of the board.
        ///
        /// The waits are bounded because the defect is a call that never returns: awaiting it
        /// directly would hang this suite rather than fail it.
        @Test("a reconnect over a feed that stays live releases its guard, so the next one works")
        func reconnectIsNotDeadAfterItsFirstSuccess() async {
            let subject = Self.model(source: LiveForeverEventSource([.phase(.live)]))
            defer { subject.stopFeed() }

            #expect(
                await Self.completes { await subject.reconnect() },
                "reconnect did not return while the feed stayed live"
            )
            #expect(!subject.isReconnecting, "the guard is still held over a healthy feed")

            let before = subject.requestCount
            _ = await Self.completes { await subject.reconnect() }
            #expect(
                subject.requestCount == before + 1,
                "the second reconnect issued no request — the button is dead after the first"
            )
        }

        /// Set once the work finishes. A plain `Bool` captured by the closure would be a copy.
        @MainActor
        final class Latch {
            private(set) var isSet = false
            func set() { isSet = true }
        }

        /// Runs `body` under a deadline, so a call that never returns **fails** rather than hanging
        /// the suite.
        ///
        /// The obvious spelling — race `await work.value` against a sleep in a task group — does not
        /// work and is worth recording: awaiting a `Task`'s `value` does not stop when the *awaiting*
        /// task is cancelled, so the group's own cancellation cannot reclaim it and the group never
        /// returns. Measured here on 2026-08-14: the suite hung for eleven minutes rather than
        /// failing in two seconds. Polling a latch and cancelling the work is what actually bounds it.
        static func completes(
            within duration: Duration = .seconds(2),
            _ body: @escaping @MainActor () async -> Void
        ) async -> Bool {
            let latch = Latch()
            let work = Task { @MainActor in
                await body()
                latch.set()
            }
            defer { work.cancel() }
            let deadline = ContinuousClock.now.advanced(by: duration)
            while ContinuousClock.now < deadline {
                if latch.isSet { return true }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return false
        }

        /// A reconnect whose reload fails used to land on `.populated`: a stale list, a subtitle
        /// reading "connecting", no banner and no way back.
        @Test("a failed reconnect leaves the board saying so rather than looking healthy")
        func failedReconnectStillNamesTheProblem() async {
            let subject = ActivityModel(
                client: FailingUsageClient(), source: nil, clock: { Self.now }
            )
            subject.apply(Self.record())
            await subject.reconnect()
            guard case .historyUnavailable = subject.condition else {
                Issue.record("expected historyUnavailable, got \(subject.condition)")
                return
            }
        }

        /// Finding 6: one session reported with a client name for some calls and without it for
        /// others must be **one** menu entry with the whole count, not two with half each.
        @Test("a session is one option even when the router names its client inconsistently")
        func sessionIdentityIgnoresTheClientName() {
            let subject = ActivityModel(
                client: FixtureControlAPIClient(.empty), source: nil, clock: { Self.now }
            )
            subject.apply(Self.record(ts: "…1", pid: 900, client: "claude"))
            subject.apply(Self.record(ts: "…2", pid: 900, client: nil))
            subject.apply(Self.record(ts: "…3", pid: 900, client: "claude"))

            let sessions = subject.sessions
            #expect(sessions.count == 1, "the client name split one session into \(sessions.count)")
            #expect(sessions.first?.calls == 3)
            #expect(sessions.first?.label.contains("900") == true)
        }

        @Test("the selection follows the record, not the row index, across an insert")
        func selectionFollowsTheRecord() async throws {
            let subject = Self.model()
            await subject.load()
            // `try #require`, not `try?`: the optional form passes when the value is nil, which is
            // the exact failure this is written to catch.
            let chosen = try #require(subject.visible.first)
            subject.selection = chosen.id
            subject.apply(Self.record(ts: "2026-08-14T23:59:59.000Z", tool: "brand_new"))
            #expect(subject.selection == chosen.id)
            #expect(subject.selectedRecord?.id == chosen.id)
        }

        @Test("a selection the filter hides is cleared rather than left describing an unseen row")
        func filteringClearsAHiddenSelection() async throws {
            let subject = Self.model()
            await subject.load()
            let orphan = try #require(subject.visible.first { $0.pid == nil })
            subject.selection = orphan.id
            subject.filter.session = subject.sessions.first { $0.key != .unattributed }?.key
            #expect(subject.selection == nil)
            #expect(subject.selectedRecord == nil)
        }
    }
#endif
