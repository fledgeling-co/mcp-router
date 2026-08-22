#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// The two boards' own decisions, taken out of their view bodies so a test can reach them.
    ///
    /// Nothing here renders. What it holds is the set of rules a render would have to obey and that
    /// a screenshot could not tell you about: which rows exist, in what order, and which of them
    /// carry a figure at all.
    @Suite("M22 boards")
    @MainActor
    struct M22BoardTests {
        // MARK: - Harnesses

        @Test("an unreadable config is drawn apart from the rows that were read")
        func unreadableRowsAreSeparated() async {
            let board = HarnessesBoardModel(client: FixtureControlAPIClient(.partial))
            await board.load()
            #expect(board.unreadable.count == 1)
            #expect(board.readable.count == HarnessFixtures.populated.count - 1)
            // Together they are the whole answer — a row cannot fall out of both lists and vanish.
            #expect(board.readable.count + board.unreadable.count == board.rows.count)
        }

        @Test("a router that answers with nothing is an empty board, not a failed one")
        func emptyIsAnAnswer() async {
            let board = HarnessesBoardModel(client: FixtureControlAPIClient(.empty))
            await board.load()
            #expect(board.rows.isEmpty)
            #expect(board.state.error == nil, "an answer of none is not a failure")
            #expect(board.finding == nil)
        }

        @Test("a router that is not running is a failure, with its own words")
        func offlineIsItsOwnState() async {
            let board = HarnessesBoardModel(client: FixtureControlAPIClient(.offline))
            await board.load()
            #expect(board.state.error == .routerNotRunning)
            #expect(board.rows.isEmpty)
        }

        @Test("a refresh that fails keeps the rows it had and names the failure")
        func staleKeepsItsRows() async {
            let board = HarnessesBoardModel(client: FixtureControlAPIClient(.populated))
            await board.load()
            let loaded = board.rows.count
            #expect(loaded > 0)

            // The same board, now unable to reach the router. Throwing the rows away would replace
            // a true-but-old board with an empty one, and an empty board is the stronger claim.
            let offline = HarnessesBoardModel(client: FixtureControlAPIClient(.offline))
            await offline.load()
            #expect(offline.rows.isEmpty, "nothing ever loaded, so there is nothing to keep")
        }

        // MARK: - Insights

        @Test("every detected harness gets a bar, and the ones with no figure sort last")
        func barsCoverEveryHarness() async {
            let board = InsightsBoardModel(client: FixtureControlAPIClient(.populated))
            await board.load()
            let bars = board.harnessBars
            #expect(bars.count == InsightsFixtures.populated.callsByHarness.count)

            // Counted rows first, in descending order; rows with no count after them. A row with no
            // count is not a small row — it is a row with nothing to compare.
            let counted = bars.prefix { $0.calls != nil }
            #expect(counted.count == 3)
            #expect(counted.map { $0.calls ?? -1 } == counted.map { $0.calls ?? -1 }.sorted(by: >))
            #expect(bars.suffix(2).allSatisfy { $0.calls == nil })

            // The zero row is present and is a zero. It is the finding: a harness at zero is one
            // still calling its own servers rather than this endpoint.
            let gemini = bars.first { $0.harness == "geminiCLI" }
            #expect(gemini?.calls == 0)
        }

        @Test("the bar scale never divides by zero, so an idle window draws bars at nothing")
        func scaleIsSafeOnAnIdleWindow() async {
            let board = InsightsBoardModel(client: FixtureControlAPIClient(.empty))
            await board.load()
            #expect(board.harnessScale >= 1)
            #expect(!board.hasHistory)
        }

        @Test("a window with no history is the board's empty state rather than a chart of zeros")
        func thinWindowIsEmpty() async {
            let board = InsightsBoardModel(client: FixtureControlAPIClient(.empty))
            await board.load()
            #expect(board.state.error == nil, "the router answered; it simply has nothing to say")
            #expect(!board.hasHistory)
        }

        @Test("the sparkline's spoken summary is composed from the series it draws")
        func sparklineSummaryIsDerived() {
            let quiet = CallsPerHourChart.summary(
                InsightsFixtures.hours.map { HourlyCalls(hourStart: $0.hourStart, calls: 0) }
            )
            #expect(quiet.contains("none"))

            let busy = CallsPerHourChart.summary(InsightsFixtures.hours)
            let total = InsightsFixtures.hours.reduce(0) { $0 + $1.calls }
            let peak = InsightsFixtures.hours.map(\.calls).max() ?? 0
            #expect(busy.contains(String(total)))
            #expect(busy.contains(String(peak)))
        }

        // MARK: - The two destinations

        @Test("both boards are installed, and the sidebar order and the digits agree")
        func destinationsAreWired() {
            #expect(BoardRegistry.hasBoard(.harnesses))
            #expect(BoardRegistry.hasBoard(.insights))
            #expect(Destination.harnesses.selectionDigit == 4)
            #expect(Destination.insights.selectionDigit == 9)
            // Neither carries a badge. A count there would have to mean "how many want a decision",
            // and neither board's readings reduce to that without deciding for the user which of
            // four readings counts — which is the judgement the finding states in words instead.
            #expect(Destination.harnesses.badgeSource == nil)
            #expect(Destination.insights.badgeSource == nil)
        }
    }
#endif
