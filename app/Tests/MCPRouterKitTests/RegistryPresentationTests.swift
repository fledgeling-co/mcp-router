import Foundation
import Testing
@testable import MCPRouterKit

/// M5 · Discover — the decisions, tested without a host.
///
/// Every clause here is an *honesty* clause rather than a rendering one: which universe a number is
/// true over, what a date means, whether a figure exists at all, and what happens to a string an
/// attacker chose. Those are exactly the decisions that ship wrong when they live in a `body`, so
/// they live in `RegistryPresentation` and are tested here.
@Suite("M5 · registry presentation")
struct RegistryPresentationTests {
    // MARK: - Fixtures

    /// A row, built by naming only what the test is about.
    ///
    /// `id` carries the provenance the merge actually preserves, so a test that wants a
    /// Smithery-based row says so with the prefix rather than by setting `source`, which is the very
    /// field that cannot be trusted.
    private func entry(
        id: String = "github",
        name: String = "github",
        displayName: String = "GitHub",
        description: String = "",
        source: RegistryEntry.Source = .official,
        repository: String? = nil,
        version: String? = nil,
        updatedAt: String? = nil,
        useCount: Int? = nil,
        verified: Bool? = nil,
        stars: Int? = nil,
        pushedAt: String? = nil,
        archived: Bool? = nil,
        install: RegistryInstall? = nil,
        installed: Bool? = nil
    ) -> RegistryEntry {
        RegistryEntry(
            id: id,
            name: name,
            displayName: displayName,
            description: description,
            source: source,
            repository: repository,
            version: version,
            updatedAt: updatedAt,
            useCount: useCount,
            verified: verified,
            stars: stars,
            pushedAt: pushedAt,
            archived: archived,
            install: install,
            installed: installed
        )
    }

    private func response(
        _ results: [RegistryEntry],
        merged: Int? = nil,
        warnings: [String] = []
    ) -> RegistrySearchResponse {
        RegistrySearchResponse(
            results: results,
            sources: RegistrySources(
                official: results.count,
                smithery: results.count,
                merged: merged ?? results.count
            ),
            warnings: warnings
        )
    }

    private func smithery(_ suffix: String) -> String {
        "smithery:\(suffix)"
    }

    // MARK: - A3 · `updatedAt` carries two meanings, and `source` cannot settle which

    @Test("the date's meaning is read from the id prefix, not from `source`")
    func dateMeaningComesFromProvenance() {
        #expect(RegistryPresentation.dateMeaning(for: entry(id: "github")) == .entryUpdated)
        #expect(
            RegistryPresentation.dateMeaning(for: entry(id: smithery("github"))) == .firstPublished
        )
    }

    /// The defect this whole mechanism exists to prevent, asserted as a case rather than described.
    ///
    /// The shipped fixture's first row is `id: "smithery:github"` stamped `source: "both"` — two
    /// Smithery rows that collided on a display name, with nothing official behind it. A date
    /// labelled from `source` prints "updated" over a Smithery `createdAt` on exactly that row.
    @Test("a `both`-stamped row whose id is Smithery's still reads as first-published")
    func bothStampedSmitheryRowIsNotTreatedAsOfficial() {
        let row = entry(id: smithery("github"), source: .both)
        #expect(RegistryPresentation.dateMeaning(for: row) == .firstPublished)
        #expect(
            !RegistryPresentation.provenance(for: row).showsOfficialMark,
            "the official mark is the strongest trust signal here and must not light from `source`"
        )
    }

    /// Red-green, run as one test: the assertion is re-evaluated against a deliberately inverted
    /// mapping, and the inversion has to fail for the real one to mean anything.
    ///
    /// **Both entries carry `source: .official` — that is the whole design of the fixture pair, and
    /// it is what makes this load-bearing rather than decorative.** Only the id differs, so an
    /// implementation reading `source` instead of the id prefix answers `.entryUpdated` for both
    /// and fails the final assertion. A review read this as "a constant asserted against another
    /// constant"; it is not, but the property it turns on was implicit, so it is stated here.
    @Test("the date mapping is load-bearing — inverting it changes the answer")
    func dateMeaningMappingIsLoadBearing() {
        let official = entry(id: "github", source: .official)
        let smitheryRow = entry(id: smithery("github"), source: .official)

        let real = [
            RegistryPresentation.dateMeaning(for: official),
            RegistryPresentation.dateMeaning(for: smitheryRow)
        ]
        // What the code would say if `provenance` were read the other way round. If this equalled
        // the real answer the mapping would be doing nothing, and the test above would pass over a
        // constant.
        let inverted: [RegistryPresentation.DateMeaning] = [.firstPublished, .entryUpdated]
        #expect(real != inverted, "an inverted mapping must not produce the same answer")
        #expect(real == [.entryUpdated, .firstPublished])
    }

    @Test("the verb reads as the meaning, and an unparseable date draws no cell at all")
    func dateCellIsAbsentRatherThanWrong() throws {
        let added = try #require(
            RegistryPresentation.dateCell(for: entry(
                id: smithery("a"),
                updatedAt: "2025-10-09T00:00:00.000Z"
            ))
        )
        #expect(added.text.hasPrefix("added "))

        let updated = try #require(
            RegistryPresentation.dateCell(for: entry(id: "a", updatedAt: "2025-09-14T15:20:36.371442Z"))
        )
        #expect(updated.text.hasPrefix("updated "))

        #expect(RegistryPresentation.dateCell(for: entry(updatedAt: nil)) == nil)
        #expect(RegistryPresentation.dateCell(for: entry(updatedAt: "not a date")) == nil)
        #expect(RegistryPresentation.dateCell(for: entry(updatedAt: "")) == nil)
    }

    /// Both fractional shapes the two indexes actually emit, plus GitHub's second-precision
    /// `pushedAt`. One formatter alone rejects one of the three.
    @Test("all three real timestamp shapes parse")
    func everyRealTimestampShapeParses() {
        #expect(RegistryPresentation.timestamp("2025-11-19T07:26:28.312Z") != nil)
        #expect(RegistryPresentation.timestamp("2025-09-14T15:20:36.371442Z") != nil)
        #expect(RegistryPresentation.timestamp("2025-09-14T15:20:36Z") != nil)
    }

    // MARK: - A4 · a scoped ordering states its universe

    @Test("best match returns the router's own sequence, untouched")
    func bestMatchIsNotReSorted() {
        // Deliberately in an order no comparator here would produce: ascending use counts, with the
        // highest last. Any client-side sort would move them.
        let rows = [
            entry(id: smithery("a"), useCount: 1),
            entry(id: smithery("b"), useCount: 900),
            entry(id: smithery("c"), useCount: 40)
        ]
        let ordered = RegistryPresentation.rows(response(rows), ordering: .bestMatch)
        #expect(
            ordered.map(\.id) == rows.map(\.id),
            "the moment this applies its own comparator it is presenting the app's ranking as the router's"
        )
    }

    @Test("a scoped ordering filters to the universe it can speak about")
    func scopedOrderingsFilterToTheirUniverse() {
        let rows = [
            entry(id: "official-only", updatedAt: "2025-01-01T00:00:00Z"),
            entry(id: smithery("with-uses"), useCount: 10, verified: true),
            entry(id: smithery("no-uses"), updatedAt: "2025-06-01T00:00:00Z")
        ]
        let payload = response(rows)

        #expect(RegistryPresentation.rows(payload, ordering: .mostUsed).map(\.id)
            == [smithery("with-uses")])
        #expect(RegistryPresentation.excludedCount(payload, ordering: .mostUsed) == 2)

        // `datePublished` is the Smithery-based rows — including the one with no usage figure, which
        // is why the two universes are not the same set.
        #expect(Set(RegistryPresentation.rows(payload, ordering: .recentlyAdded).map(\.id))
            == [smithery("with-uses"), smithery("no-uses")])
        #expect(RegistryPresentation.excludedCount(payload, ordering: .recentlyAdded) == 1)

        #expect(RegistryPresentation.excludedCount(payload, ordering: .bestMatch) == 0)
    }

    @Test("the exclusion note names the count and appears only when something was excluded")
    func exclusionNoteIsConditional() throws {
        let mixed = response([entry(id: "official"), entry(id: smithery("s"), useCount: 3)])
        let note = try #require(RegistryPresentation.exclusionNote(mixed, ordering: .mostUsed))
        #expect(note.contains("1 row is"), "the count is stated, and its verb agrees")

        // Nothing excluded — a sentence saying "0 rows are not shown" is noise about a condition
        // that never applied.
        let allSmithery = response([entry(id: smithery("s"), useCount: 3)])
        #expect(RegistryPresentation.exclusionNote(allSmithery, ordering: .mostUsed) == nil)
        #expect(RegistryPresentation.exclusionNote(mixed, ordering: .bestMatch) == nil)
    }

    @Test("an ordering whose universe is empty says why, and best match never does")
    func disabledReasonAppearsOnlyForAnEmptyUniverse() {
        let officialOnly = response([entry(id: "a"), entry(id: "b")])
        #expect(RegistryPresentation.disabledReason(officialOnly, ordering: .mostUsed) != nil)
        #expect(RegistryPresentation.disabledReason(officialOnly, ordering: .recentlyAdded) != nil)
        #expect(RegistryPresentation.disabledReason(officialOnly, ordering: .bestMatch) == nil)

        let hasUsage = response([entry(id: smithery("a"), useCount: 1)])
        #expect(RegistryPresentation.disabledReason(hasUsage, ordering: .mostUsed) == nil)
    }

    /// The response's own order is non-deterministic between calls, so an unstable sort over it
    /// reshuffles rows between renders of the *same* data — which reads as the board reloading when
    /// it has not.
    @Test("ordering is stable: ties keep arrival order, and two runs agree")
    func orderingIsStable() {
        let tied = (0 ..< 12).map { index in
            entry(id: smithery("row-\(index)"), useCount: 7)
        }
        let payload = response(tied)
        let first = RegistryPresentation.rows(payload, ordering: .mostUsed).map(\.id)
        let second = RegistryPresentation.rows(payload, ordering: .mostUsed).map(\.id)

        #expect(first == tied.map(\.id), "an all-tie sort must not move anything")
        #expect(first == second)
    }

    @Test("a row with no parseable date sorts last rather than to the top")
    func undatedRowsSortLast() {
        let rows = [
            entry(id: smithery("undated")),
            entry(id: smithery("older"), updatedAt: "2024-01-01T00:00:00Z"),
            entry(id: smithery("newer"), updatedAt: "2026-01-01T00:00:00Z")
        ]
        #expect(RegistryPresentation.rows(response(rows), ordering: .recentlyAdded).map(\.id)
            == [smithery("newer"), smithery("older"), smithery("undated")])
    }
}
