#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    @MainActor
    @Suite("Discover returned-result recency")
    struct DiscoverRecencyTests {
        static let now = Date(timeIntervalSince1970: 1_793_577_600)
        static func entries() -> [RegistryEntry] {
            [entry("official", age: 1), entry("smithery:recent", age: 7),
             entry("smithery:outside", age: 7, offset: -1), entry("older", age: 45),
             entry("undated", age: nil), entry("bad-date", age: nil, stamp: "yesterday"),
             entry("merged-official", age: 6, uses: 9)]
        }

        static func entry(
            _ id: String,
            age: Int?,
            offset: TimeInterval = 0,
            stamp: String? = nil,
            uses: Int? = 2
        ) -> RegistryEntry {
            let date = age
                .map {
                    ISO8601DateFormatter().string(from: now.addingTimeInterval(-Double($0) * 86400 + offset))
                }
            return RegistryEntry(
                id: id,
                name: id,
                displayName: id,
                description: "A fixture server",
                source: id.hasPrefix("smithery:") ? .smithery : .official,
                updatedAt: stamp ?? date,
                useCount: uses
            )
        }

        static func response() -> RegistrySearchResponse {
            RegistrySearchResponse(
                results: entries(),
                sources: RegistrySources(official: 4, smithery: 3, merged: 50),
                warnings: []
            )
        }

        @Test("both provenance clocks share a cutoff; equality is included, malformed dates excluded")
        func sharedCutoff() {
            let result = RegistryRecency.rows(in: Self.entries(), window: .seven, now: Self.now)
            #expect(result.map(\.id) == ["official", "merged-official", "smithery:recent"])
            #expect(RegistryPresentation.dateMeaning(for: result[0]) == .entryUpdated)
            #expect(RegistryPresentation.dateMeaning(for: result[2]) == .firstPublished)
            #expect(DiscoverBands.members(
                of: .recentlyChanged,
                in: Self.entries(),
                window: .seven,
                now: Self.now
            ) == result)
            #expect(RegistryRecency.rows(in: Self.entries(), window: .thirty, now: Self.now).count == 4)
            #expect(RegistryRecency.rows(in: Self.entries(), window: .ninety, now: Self.now).count == 5)
            #expect(RegistryRecency.rows(in: [], window: .anyTime, now: Self.now).isEmpty)
        }

        @Test("window filters locally only under timestamp ordering and names returned and matched scope")
        func localWindowAndScope() async {
            let client = DiscoverRecordingClient()
            client.staged = [.success(Self.response())]
            let date = Self.now
            let board = DiscoverBoardModel(client: client, now: { date })
            await board.load()
            let best = board.rows
            board.ordering = .mostUsed
            let popular = board.rows
            for window in RecencyWindow.allCases {
                board.window = window
                board.ordering = .bestMatch
                #expect(board.rows == best)
                board.ordering = .mostUsed
                #expect(board.rows == popular)
            }
            board.ordering = .recentlyAdded
            board.selection = "older"
            board.window = .seven
            #expect(board.selectedEntry() == nil && !board.commitDefaultAction())
            #expect(board.rows.map(\.id) == ["official", "merged-official", "smithery:recent"])
            #expect(board.recencySummary?.contains("3 of 7 returned results") == true)
            #expect(board.recencySummary?.contains("updated or added within the past 7 days") == true)
            #expect(RegistryPresentation.footerNotes(for: Self.response(), ordering: board.ordering)
                .contains { $0.contains("7 of 50 that matched") })
            #expect(client.searchQueries.count == 1, "changing a local window must not query either registry")
        }
    }
#endif
