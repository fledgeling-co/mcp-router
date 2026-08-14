#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// What happens to the **subscription** when a reader presses Reconnect, or walks away, or does
    /// both at once.
    ///
    /// Split from `ActivityRecoveryTests` because the two suites answer different questions about the
    /// same board. That one is about the record window — what a merge keeps, what it drops, and in
    /// what order. This one is about the live feed's *lifecycle*: which taps are refused, which
    /// teardowns are ignored, and whether the guard that serialises reconnects is ever released. Every
    /// defect below was green code with no coverage of any kind.
    @MainActor
    @Suite("Activity — the subscription, recovering badly")
    struct ActivityReconnectTests {
        private typealias Fixture = ActivityFixture

        /// Two taps used to stack two subscription loops writing into one model.
        @Test("a second reconnect while one is running is refused rather than stacked")
        func reconnectIsNotReentrant() async {
            let subject = Fixture.model(source: ReplayActivityEventSource([.phase(.live)]))
            async let first: Void = subject.reconnect()
            async let second: Void = subject.reconnect()
            _ = await (first, second)
            #expect(!subject.isReconnecting, "the guard is released when the reconnect finishes")
            // `<= 2` admitted the very thing this test is named for: two calls that both got past
            // the guard would issue exactly two requests. One reconnect is one reload.
            #expect(subject.requestCount == 1, "the second reconnect was not refused")
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
            let subject = Fixture.model(source: LiveForeverEventSource([.phase(.live)]))
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
            func set() {
                isSet = true
            }
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
                client: FailingUsageClient(), source: nil, clock: { Fixture.now }
            )
            subject.beginSession()
            subject.apply(Fixture.record())
            await subject.reconnect()
            guard case .historyUnavailable = subject.condition else {
                Issue.record("expected historyUnavailable, got \(subject.condition)")
                return
            }
        }

        /// **A reconnect pressed on a board that is gone must not install a feed.**
        ///
        /// `FeedBanner`'s action runs in an unstructured `Task`, so it can resume after the reader
        /// has switched destination and `endSession` has torn the subscription down. Installing one
        /// then leaves a live feed behind a board nobody is looking at — the thing the teardown had
        /// just prevented.
        @Test("a reconnect after the board has gone away does nothing")
        func detachedReconnectDoesNotReinstallTheFeed() async {
            let subject = Fixture.model(source: LiveForeverEventSource([.phase(.live)]))
            let before = subject.requestCount
            subject.endSession(1)
            _ = await Self.completes { await subject.reconnect() }
            #expect(
                subject.requestCount == before,
                "a detached model reloaded and resubscribed behind a board that is gone"
            )
            #expect(subject.phase == nil, "the teardown left a phase describing a dead feed")
        }

        /// **A superseded board's teardown must not kill its replacement's feed.**
        ///
        /// The model outlives the view, and SwiftUI does not promise that an outgoing view's
        /// `.onDisappear` runs before an incoming view's `.task`. If it runs second, an unguarded
        /// `stopFeed()` cancels the feed the new board just started, and nothing re-arms it: a full
        /// list, no live feed, and a subtitle that would still have read "live".
        @Test("a stale teardown from a superseded board is ignored")
        func staleTeardownDoesNotKillTheLiveFeed() async {
            let subject = Fixture.model(source: LiveForeverEventSource([.phase(.live)]))
            let stale = subject.beginSession() - 1 // what the first board is still holding
            subject.endSession(stale)
            _ = await Self.completes { await subject.reconnect() }
            #expect(
                subject.requestCount > 0,
                "the model refused to reconnect — a superseded board's teardown detached it"
            )
        }
    }
#endif
