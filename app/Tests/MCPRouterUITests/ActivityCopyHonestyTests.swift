#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// What the Activity board's sentences are allowed to claim.
    ///
    /// A separate suite because these are not tests of behaviour — they are tests of **honesty**,
    /// and the failure they catch is a fluent sentence stating something the wire does not carry.
    /// An earlier draft of this board said "The router has been up since 09:12" and "the history
    /// below is complete up to 09:41". Both read perfectly and neither was a fact: `since` is the
    /// moment the counting window opened, persisted across restarts, and there is no completeness
    /// watermark on the wire at all.
    @MainActor
    @Suite("Activity — what the copy may claim")
    struct ActivityCopyTests {
        static let now = Date(timeIntervalSince1970: 1_755_166_918)

        static func model(
            _ scenario: FixtureControlAPIClient.Scenario = .populated
        ) -> ActivityModel {
            ActivityModel(client: FixtureControlAPIClient(scenario), source: nil, clock: { now })
        }

        // MARK: - B32 / F3: what the copy is allowed to claim about `since`

        /// `UsageResponse.since` is `stats.since` in `src/usage.ts`, which `readStats()` persists
        /// across restarts and only `reset()` moves. It is the moment the counting window opened,
        /// **not** a process start time — so no sentence on this board may say the router has been
        /// up since it.
        @Test("no sentence claims the router's uptime from a field that is a counting window")
        func copyDoesNotClaimUptime() {
            let sentences = [
                ActivityCopy.empty(since: "09:12").detail,
                ActivityCopy.disabledFilters,
                ActivityCopy.subtitle(count: 3, since: "09:12", feed: "live"),
                ActivityCopy.filteredToNothing(total: 28).detail
            ]
            for sentence in sentences {
                let lowered = sentence.lowercased()
                #expect(!lowered.contains("has been up"), "uptime is not on the wire: \(sentence)")
                #expect(!lowered.contains("router started"), "start time is not on the wire: \(sentence)")
                #expect(!lowered.contains("uptime"))
            }
        }

        /// No watermark exists on the wire. The newest record's timestamp proves a record arrived,
        /// never that none was missed, so the feed states may name it and may not call it complete.
        @Test("the feed states name the newest call rather than claiming completeness")
        func feedCopyClaimsNoWatermark() {
            let messages = [
                ActivityCopy.partialReconnecting(newest: "09:41"),
                ActivityCopy.partialDisconnected(newest: "09:41"),
                ActivityCopy.neverConnected()
            ]
            for message in messages {
                let text = "\(message.title) \(message.detail)".lowercased()
                #expect(!text.contains("complete up to"))
                #expect(!text.contains("is complete"))
            }
            #expect(ActivityCopy.partialReconnecting(newest: "09:41").detail.contains("newest call"))
        }

        /// `ControlEventStream` never reports how many attempts it made — it yields `.disconnected`
        /// and finishes. A count here would be `ReconnectPolicy`'s default copied into a sentence.
        @Test("the given-up sentence names no attempt count")
        func disconnectedCopyNamesNoAttemptCount() {
            let message = ActivityCopy.partialDisconnected(newest: "09:41")
            let text = "\(message.title) \(message.detail)"
            #expect(!text.contains("six"))
            #expect(text.rangeOfCharacter(from: .decimalDigits) == nil || text.contains("09:41"))
        }

        /// The subtitle is the loaded window's size and is worded so it cannot be read as a total —
        /// the window caps at 500 and a busy router will have served far more.
        @Test("the subtitle says what is showing rather than what the router has recorded")
        func subtitleIsNotATotal() {
            let subtitle = ActivityCopy.subtitle(count: 500, since: "09:12", feed: "live")
            #expect(subtitle.hasPrefix("Showing "))
            #expect(!subtitle.lowercased().contains("total"))
        }

        @Test("the empty state offers nothing, and is not an error")
        func emptyStateOffersNothing() async {
            let subject = Self.model(.empty)
            await subject.load()

            #expect(subject.condition == .empty)
            let message = try? #require(subject.message(for: .empty))
            #expect(message?.actionLabel == nil, "no control here can make an agent call a tool")
            #expect(message?.title == "No calls yet")
        }
    }
#endif
