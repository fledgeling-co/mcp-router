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

        /// Two taps used to stack two subscription loops writing into one model.
        @Test("a second reconnect while one is running is refused rather than stacked")
        func reconnectIsNotReentrant() async {
            let subject = Self.model(source: ReplayActivityEventSource([.phase(.live)]))
            async let first: Void = subject.reconnect()
            async let second: Void = subject.reconnect()
            _ = await (first, second)
            #expect(!subject.isReconnecting, "the guard is released when the reconnect finishes")
            #expect(subject.requestCount <= 2, "a stacked reconnect would issue more")
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
