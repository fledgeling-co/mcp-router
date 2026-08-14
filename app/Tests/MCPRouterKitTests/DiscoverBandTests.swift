import Foundation
import Testing
@testable import MCPRouterKit

/// A2, A4 and A5: two bands, membership by presence rather than by zero, and a window that filters
/// exactly one of them.
@Suite("Discover bands — A2, A4 and A5")
struct DiscoverBandTests {
    /// A fixed clock, so a window test measures the window rather than the day it is run.
    static let now = Date(timeIntervalSince1970: 1_764_000_000) // 2025-11-24T14:40:00Z

    private func entry(
        id: String,
        useCount: Int? = nil,
        updatedAt: String? = nil
    ) -> RegistryEntry {
        RegistryEntry(
            id: id,
            name: id,
            displayName: id,
            description: "",
            source: .official,
            repository: nil,
            version: nil,
            updatedAt: updatedAt,
            useCount: useCount,
            verified: nil,
            iconURL: nil,
            stars: nil,
            forks: nil,
            pushedAt: nil,
            archived: nil,
            install: nil,
            installed: false
        )
    }

    // MARK: - A2

    @Test("exactly two bands ship, and neither is a trend")
    func twoBands() {
        #expect(DiscoverBand.allCases.count == 2)
        #expect(DiscoverBand.allCases.contains(.mostUsed))
        #expect(DiscoverBand.allCases.contains(.recentlyChanged))
    }

    /// The criterion this band design exists to protect: **absence says "not measured", zero says
    /// "measured, and none".** The official registry publishes no popularity figure at all, so
    /// ranking its entries last at zero would assert a measurement nobody took.
    @Test("an entry with no useCount is absent from Most used, never ranked at zero")
    func missingCountIsAbsent() {
        let entries = [
            entry(id: "counted", useCount: 12),
            entry(id: "uncounted")
        ]
        let members = DiscoverBands.members(
            of: .mostUsed,
            in: entries,
            window: .anyTime,
            now: Self.now
        )
        #expect(members.map(\.id) == ["counted"])
    }

    @Test("Most used orders by useCount descending, and ties break stably on id")
    func mostUsedOrdering() {
        let entries = [
            entry(id: "b", useCount: 5),
            entry(id: "c", useCount: 90),
            entry(id: "a", useCount: 5)
        ]
        let members = DiscoverBands.members(
            of: .mostUsed,
            in: entries,
            window: .anyTime,
            now: Self.now
        )
        // A total, stable order: SwiftUI keys rows by identity, and an unstable sort makes rows
        // swap places on a re-render that changed nothing.
        #expect(members.map(\.id) == ["c", "a", "b"])
    }

    @Test("an entry with an unparseable stamp drops out of Recently changed rather than sorting")
    func unparseableStampDropsFromBand() {
        let entries = [
            entry(id: "good", updatedAt: "2025-11-19T07:26:28.312Z"),
            entry(id: "junk", updatedAt: "yesterday")
        ]
        let members = DiscoverBands.members(
            of: .recentlyChanged,
            in: entries,
            window: .anyTime,
            now: Self.now
        )
        #expect(members.map(\.id) == ["good"])
    }

    // MARK: - A4

    /// The guard on A4, and the reason it is a criterion rather than a note: the tidy-looking
    /// change is to filter both bands by the window, and it would silently make Most used claim a
    /// per-window session count that was never measured. `useCount` is a cumulative all-time total.
    @Test("Most used membership is identical across all four windows")
    func mostUsedIgnoresTheWindow() {
        let entries = [
            entry(id: "old", useCount: 40, updatedAt: "2020-01-01T00:00:00Z"),
            entry(id: "new", useCount: 10, updatedAt: "2025-11-23T00:00:00Z")
        ]
        let baseline = DiscoverBands.members(
            of: .mostUsed,
            in: entries,
            window: .anyTime,
            now: Self.now
        ).map(\.id)

        #expect(baseline == ["old", "new"])
        for window in RecencyWindow.allCases {
            let members = DiscoverBands.members(
                of: .mostUsed,
                in: entries,
                window: window,
                now: Self.now
            ).map(\.id)
            #expect(members == baseline, "\(window) changed Most used")
        }
    }

    @Test("the window filters Recently changed, and each option filters differently")
    func windowFiltersRecentlyChanged() {
        let entries = [
            entry(id: "yesterday", updatedAt: "2025-11-23T00:00:00Z"),
            entry(id: "fortyDays", updatedAt: "2025-10-15T00:00:00Z"),
            entry(id: "ancient", updatedAt: "2020-01-01T00:00:00Z")
        ]

        func members(_ window: RecencyWindow) -> [String] {
            DiscoverBands.members(
                of: .recentlyChanged,
                in: entries,
                window: window,
                now: Self.now
            ).map(\.id)
        }

        #expect(members(.anyTime) == ["yesterday", "fortyDays", "ancient"])
        #expect(members(.ninety) == ["yesterday", "fortyDays"])
        #expect(members(.thirty) == ["yesterday"])
        #expect(members(.seven) == ["yesterday"])
    }

    /// A4: Any time is the default, and that is a data decision rather than a convenience — the
    /// recorded fixture's newest stamp is outside every offered window, so any other default would
    /// render an empty band on first open. A designed-in empty state is a different thing from one
    /// a search happened to produce.
    @Test("only Any time has no cutoff, and the other three carry their days")
    func windowDays() {
        #expect(RecencyWindow.anyTime.days == nil)
        #expect(RecencyWindow.ninety.days == 90)
        #expect(RecencyWindow.thirty.days == 30)
        #expect(RecencyWindow.seven.days == 7)
        #expect(RecencyWindow.allCases.first == .anyTime)
    }

    @Test("only Recently changed responds to the window")
    func respondsToWindow() {
        #expect(DiscoverBand.recentlyChanged.respondsToWindow)
        #expect(!DiscoverBand.mostUsed.respondsToWindow)
    }

    // MARK: - A5

    /// One band empty while the other is populated is the **common** case, not an edge case: an
    /// entire index publishes no `useCount`, and every window but Any time excludes the recorded
    /// fixture's newest entry. It is not the whole-list Empty state.
    @Test("a band empty within a populated list is its own state, not the list's Empty")
    func bandEmptyWithinResults() {
        let entries = [entry(id: "uncounted", updatedAt: "2025-11-23T00:00:00Z")]

        #expect(DiscoverBands.isBandEmptyWithinResults(
            .mostUsed, in: entries, window: .anyTime, now: Self.now
        ))
        #expect(!DiscoverBands.isBandEmptyWithinResults(
            .recentlyChanged, in: entries, window: .anyTime, now: Self.now
        ))
    }

    /// An empty list is the list's own Empty state, and no band may claim it as a band-empty — the
    /// two have different copy and different actions.
    @Test("no band reports band-empty when the whole list is empty")
    func emptyListIsNotBandEmpty() {
        for band in DiscoverBand.allCases {
            #expect(!DiscoverBands.isBandEmptyWithinResults(
                band, in: [], window: .anyTime, now: Self.now
            ))
        }
    }
}
