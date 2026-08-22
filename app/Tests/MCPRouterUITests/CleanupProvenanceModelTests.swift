#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// M12 — the board side of what a destructive dialog may say about its own figures.
    ///
    /// The wording is enumerated in `MCPRouterKitTests/CleanupProvenanceTests`. This is the half that
    /// only the model can answer: that a reading is stamped when it is taken, that a stale reading
    /// keeps the stamp it had rather than acquiring a fresh one, and that being stale is not by
    /// itself a reason to refuse a destructive act.
    @Suite("Cleanup — the reading behind a destructive dialog")
    struct CleanupProvenanceModelTests {
        static let pinned = Date(timeIntervalSince1970: 1_755_000_000)

        /// A clock the test moves by hand. Nothing here sleeps.
        @MainActor
        final class TestClock {
            var now: Date
            init(_ start: Date) { now = start }
            func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
        }

        @MainActor
        static func board(
            calls: Int? = 5,
            clock: TestClock
        ) -> (CleanupBoardModel, M7RecordingClient) {
            let client = M7RecordingClient()
            client.serversToServe = [M7Fixtures.server(name: "alpha", calls: 0)]
            if let calls {
                client.summaryToServe = UsageSummary(
                    since: ISO8601DateFormatter().string(from: pinned.addingTimeInterval(-41 * 86400)),
                    servers: [
                        ServerSummary(
                            name: "alpha", calls: calls, errors: 0, firstSeen: nil, lastUsed: nil,
                            projects: [:], projectNames: []
                        )
                    ]
                )
            } else {
                client.summaryFailure = .routerNotRunning
            }
            let board = CleanupBoardModel(client: client, clock: { clock.now })
            return (board, client)
        }

        // MARK: - The stamp

        @MainActor
        @Test("C1: a reading is stamped from the model's own clock when it is taken")
        func aReadingIsStampedWhenItIsTaken() async throws {
            let clock = TestClock(Self.pinned)
            let (board, _) = Self.board(clock: clock)
            await board.load()
            let reading = try #require(board.state.reading)
            #expect(
                reading.observedAt == Self.pinned,
                "the reading was not stamped from the injected clock: \(reading.observedAt)"
            )
        }

        /// The mechanism the whole item rests on: a stale reading is an **old** reading, and its
        /// stamp has to stay old. Restamping it on the failing poll would make the dialog date a
        /// reading it does not have.
        @MainActor
        @Test("C4: a stale reading keeps the stamp it was taken with")
        func aStaleReadingKeepsItsStamp() async throws {
            let clock = TestClock(Self.pinned)
            let (board, client) = Self.board(clock: clock)
            await board.load()

            clock.advance(600)
            client.serversFailure = .routerNotRunning
            await board.load()

            #expect(board.isStale, "a failed poll over a good reading did not land on .stale")
            let reading = try #require(board.state.reading)
            #expect(
                reading.observedAt == Self.pinned,
                "the stale reading was restamped to the failing poll: \(reading.observedAt)"
            )
            guard case .marked = board.resetFigureProvenance else {
                Issue.record("a stale board did not mark its reset dialog: \(board.resetFigureProvenance)")
                return
            }
            guard case .marked = board.removeFigureProvenance else {
                Issue.record("a stale board did not mark its removal dialog")
                return
            }
        }

        @MainActor
        @Test("C6: a board with no reading dates nothing")
        func aBoardWithNoReadingDatesNothing() async {
            let clock = TestClock(Self.pinned)
            let client = M7RecordingClient()
            client.serversFailure = .routerNotRunning
            let board = CleanupBoardModel(client: client, clock: { clock.now })
            await board.load()

            #expect(!board.isStale, "a first load that failed is .failed, not .stale")
            #expect(board.resetFigureProvenance == .none)
            #expect(board.removeFigureProvenance == .none)
        }

        /// A fresh reading whose `usageSummary()` threw states no figure, so it dates none.
        @MainActor
        @Test("C6: a reading the summary did not answer for carries no reset provenance")
        func anUnansweredSummaryCarriesNoProvenance() async {
            let clock = TestClock(Self.pinned)
            let (board, _) = Self.board(calls: nil, clock: clock)
            await board.load()

            #expect(board.state.reading?.recordedCalls == nil)
            #expect(
                board.resetFigureProvenance == .none,
                "a figure the router never gave was dated: \(board.resetFigureProvenance)"
            )
            // The removal dialog's figures come from `servers()`, which answered — so that one is
            // still dated. The two dialogs read different responses and this is where that shows.
            #expect(board.removeFigureProvenance != .none)
        }

        // MARK: - What staleness does not do

        /// C9 — being stale is not a refusal.
        ///
        /// Asserted against `removalRefusalReason`, which is what the sheet's `.disabled` and `.help`
        /// both read. Adding `|| isStale` to it — the mutation this guards — turns this red.
        @MainActor
        @Test("C9: a stale reading does not refuse the destructive act")
        func aStaleReadingDoesNotRefuse() async {
            let clock = TestClock(Self.pinned)
            let (board, client) = Self.board(clock: clock)
            await board.load()
            #expect(board.removalRefusalReason(for: "alpha") == nil)

            client.serversFailure = .routerNotRunning
            await board.load()
            #expect(board.isStale)
            #expect(
                board.removalRefusalReason(for: "alpha") == nil,
                "a stale reading dimmed Remove; .stale means the last read threw, not that the write will"
            )
        }

        /// And the refusal that **does** exist is not weakened by the new branch.
        @MainActor
        @Test("C9: a candidate that has left the list still refuses, with its reason")
        func aGoneCandidateStillRefuses() async {
            let clock = TestClock(Self.pinned)
            let (board, _) = Self.board(clock: clock)
            await board.load()
            #expect(
                board.removalRefusalReason(for: "never-existed")
                    == CleanupPresentation.consequenceUnavailable
            )
        }

        // MARK: - The premise the Kit-side test cannot check

        /// `MCPRouterKitTests` cannot import `MCPRouterUI`, so the half of that argument which reads
        /// `removeConsequence` is checked here: a server with neither env nor header keys draws no
        /// key names, which is why the removal provenance line does not claim any.
        @MainActor
        @Test("the removal line's premise holds: a bare entry's consequence names no keys")
        func theRemovalLinesPremiseHolds() {
            let bare = ServersBoardModel.removeConsequence(envKeys: [], headerKeys: [])
            #expect(
                !bare.lowercased().contains("key"),
                "the no-secrets consequence names keys, so provenance could have claimed them: \(bare)"
            )
        }

        // MARK: - The wiring

        /// Both sheets render the note, and neither decides the treatment for itself.
        ///
        /// Source-level for the reason `CleanupRowActionsTests` gives for its own assertions: the
        /// claim is about a SwiftUI body, this repo has no view-tree seam in the unit suite, and a
        /// claim nobody checks is worse than one checked at the only reachable layer. What it can
        /// catch is real — deleting either call, or reintroducing an `isStale` branch inside a sheet,
        /// turns it red. That the note *renders* as a banner rather than a caption is proved in the
        /// UI pass, not here, and the acceptance ledger says so.
        @Test("C5: both destructive sheets render the note, and neither branches on staleness itself")
        func bothSheetsRenderTheNote() throws {
            let whole = try String(
                contentsOf: ShellTestSupport.repoRoot()
                    .appending(path: "app/Sources/MCPRouterUI/Boards/CleanupSheets.swift"),
                encoding: .utf8
            )
            // Comment lines are dropped before anything is searched. The doc comment on
            // `ProvenanceNote` explains why a sheet must not branch on staleness, and it names the
            // expression to do that — so a search over the raw file finds the sentence forbidding
            // the thing and reports it as the thing. G3 built a delexer for this confusion; one line
            // of it is enough here, and a comment cannot contain a call site anyway.
            let source = whole
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            #expect(
                source.contains("ProvenanceNote(board.resetFigureProvenance)"),
                "the reset dialog draws no provenance note"
            )
            #expect(
                source.contains("ProvenanceNote(board.removeFigureProvenance)"),
                "the removal dialog draws no provenance note"
            )
            // The treatment is the model's decision so that it can be asserted at all, and so the
            // two dialogs cannot drift into different renderings of one state.
            #expect(
                !source.contains("board.isStale"),
                "a sheet branches on staleness itself rather than rendering the decided treatment"
            )
        }
    }
#endif
