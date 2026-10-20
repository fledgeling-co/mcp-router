#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// The Insights board's period control: what the board asks the router for, and what it draws when the
    /// answer comes back.
    ///
    /// **The request is the proof.** A picker that changed a label and kept the old reading would pass a
    /// check on the label alone, so each test reads the window the client was actually asked for, and the
    /// window the board drew from the answer it got.
    @Suite("Insights period control")
    @MainActor
    struct InsightsPeriodBoardTests {
        /// Answers each read with the window it was asked for, and records the sequence of asks.
        final class PeriodClient: AnalystTestClient, @unchecked Sendable {
            private let lock = NSLock()
            private(set) var asks: [InsightsPeriod] = []

            func insights(period: InsightsPeriod) async throws(ControlAPIError) -> InsightsResponse {
                lock.withLock { asks.append(period) }
                return period == .last7Days ? InsightsFixtures.week : InsightsFixtures.populated
            }
        }

        @Test("the board opens on seven days, the period the design opens on, and asks the router for it")
        func opensOnSevenDays() async {
            let client = PeriodClient()
            let board = InsightsBoardModel(client: client)
            #expect(board.period == .last7Days)
            await board.load()
            #expect(client.asks == [.last7Days])
            #expect(board.state.response?.windowHours == 168)
        }

        @Test("choosing 24 hours asks for 24 hours and draws the day that comes back")
        func choosingADayReadsTheDay() async {
            let client = PeriodClient()
            let board = InsightsBoardModel(client: client)
            await board.load()

            await board.choosePeriod(.last24Hours)
            #expect(board.period == .last24Hours)
            #expect(client.asks == [.last7Days, .last24Hours])
            #expect(board.state.response?.windowHours == 24)
        }

        @Test("choosing the period already shown does not read the router again")
        func choosingTheSamePeriodIsNotARead() async {
            let client = PeriodClient()
            let board = InsightsBoardModel(client: client)
            await board.load()

            await board.choosePeriod(.last7Days)
            #expect(client.asks == [.last7Days])
        }

        @Test("a week the router began counting inside reads as incomplete, with its unobserved hours blank")
        func weekFixtureIsIncomplete() {
            let week = InsightsFixtures.week
            #expect(week.windowComplete == false)
            #expect(week.observedSince != nil)
            #expect(week.callsPerHour.count == 168)
            #expect(week.callsPerHour.filter { $0.calls == nil }.count == 96)
        }
    }
#endif
