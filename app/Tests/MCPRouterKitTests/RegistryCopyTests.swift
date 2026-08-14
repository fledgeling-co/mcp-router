import Foundation
import Testing
@testable import MCPRouterKit

/// M5 · Discover — what the board says about its own result.
///
/// Split from `RegistryPresentationTests` for length. Grouped because every clause here is a
/// sentence or a figure the board states in its own voice: the one number a row carries, the
/// footer's admissions of incompleteness, the three distinct empties, and what happens to a string
/// an attacker chose.
@Suite("M5 · registry copy and figures")
struct RegistryCopyTests {
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

    // MARK: - A2 · nothing is displayed that the router does not observe

    @Test("a figure carries its unit, and absence is never rendered as zero")
    func figureCarriesItsUnitAndNeverFabricatesZero() throws {
        let sessions = try #require(RegistryPresentation.figure(for: entry(useCount: 2984)))
        #expect(sessions.text.contains("sessions"))
        #expect(sessions.text.contains("2,984") || sessions.text.contains("2984"))

        let stars = try #require(RegistryPresentation.figure(for: entry(stars: 9)))
        #expect(stars.text == "9 stars")

        // Singulars, because "1 sessions" is the tell of a number nobody looked at.
        #expect(RegistryPresentation.figure(for: entry(useCount: 1))?.text == "1 session")
        #expect(RegistryPresentation.figure(for: entry(stars: 1))?.text == "1 star")

        // Neither figure: nothing at all. A rendered `0` claims the number was measured and found
        // to be none.
        #expect(RegistryPresentation.figure(for: entry()) == nil)

        // A real zero is still a measurement and is still shown.
        #expect(RegistryPresentation.figure(for: entry(useCount: 0))?.text == "0 sessions")
    }

    @Test("no trend, velocity, rank or eval figure is invented anywhere in the Discover sources")
    func noFabricatedFieldsInDiscoverSources() throws {
        // The brief asked for a trending band. Nothing in this product keeps a history of either
        // index, so the figure would mean "sessions gained while this Mac happened to be awake" —
        // telemetry about the user's own use of the app, presented as a fact about the ecosystem.
        // This asserts the absence structurally rather than trusting it was never added.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        // **Every Discover source, Kit and UI.** This listed the four Kit files only, so a
        // `Text("2,104 installs")` added to `DiscoverBoardRow.swift` passed a test whose name says
        // "anywhere in the Discover sources" — the constraint is about what reaches the screen, and
        // the five files that draw the screen were the ones not being read.
        let sources = [
            "Sources/MCPRouterKit/Registry/RegistryPresentation.swift",
            "Sources/MCPRouterKit/Registry/RegistryPresentation+Row.swift",
            "Sources/MCPRouterKit/Registry/RegistryPresentation+Notes.swift",
            "Sources/MCPRouterKit/Registry/RegistryCapability.swift",
            "Sources/MCPRouterUI/Boards/DiscoverBoard.swift",
            "Sources/MCPRouterUI/Boards/DiscoverBoardModel.swift",
            "Sources/MCPRouterUI/Boards/DiscoverBoardRow.swift",
            "Sources/MCPRouterUI/Boards/DiscoverBoardMetrics.swift",
            "Sources/MCPRouterUI/Boards/DiscoverDetailSheet.swift"
        ]
        // Declarations only, and shaped as declarations. The prose in `trendingNote` says the words
        // "trend" and "velocity" on purpose — saying that neither is measured is the whole point of
        // it — so a bare substring search would fire on the very sentence that keeps the promise.
        // What must not exist is a *property or function* named after a figure nothing observes.
        //
        // The UI files add a second shape to look for: a *rendered literal*. A declaration search
        // cannot see `Text("2,104 installs")`, so the units themselves are searched for where they
        // would appear inside a string.
        let forbidden = ["var trending", "let trendCount", "func trend(", "var velocity",
                         "let velocity", "func velocity", "installCount", "func rank(",
                         "var rank", "evalScore", "popularityScore", "var score",
                         " installs\"", " downloads\"", "Rank #", "eval score"]

        // Proof the reader is reading: every listed path must exist and be non-trivial, or a
        // renamed file would silently turn this whole test into a loop over nothing.
        for path in sources {
            let text = try String(contentsOf: root.appending(path: path), encoding: .utf8)
            #expect(text.count > 500, "\(path) is missing or empty — this test would be vacuous")
            for needle in forbidden {
                #expect(!text.contains(needle), "\(path) declares \(needle), which nothing observes")
            }
        }
    }

    // MARK: - A7 · partiality is stated, never smoothed

    @Test("each footer sentence appears exactly when its condition holds")
    func footerNotesAreConditional() {
        let complete = response([entry()], merged: 1)
        let notes = RegistryPresentation.footerNotes(for: complete, ordering: .bestMatch)
        #expect(notes.contains(RegistryPresentation.trendingNote), "sentence four is always stated")
        #expect(notes.contains(RegistryPresentation.rankingNote))
        #expect(!notes.contains { $0.contains("Showing") }, "nothing was sliced, so nothing is said")

        let sliced = response([entry()], merged: 47)
        let slicedNotes = RegistryPresentation.footerNotes(for: sliced, ordering: .bestMatch)
        #expect(slicedNotes.contains { $0.contains("Showing 1 of 47") })

        // The ranking note is about `Best match`'s own bias, so it is not claimed under an ordering
        // it does not describe.
        let scoped = RegistryPresentation.footerNotes(for: complete, ordering: .mostUsed)
        #expect(!scoped.contains(RegistryPresentation.rankingNote))
    }

    /// A warning this code has no nicer sentence for is passed through **verbatim** rather than
    /// dropped — swallowing it would leave the board silently confident about a result the router
    /// flagged.
    @Test("an unrecognised warning survives to the footer word for word")
    func unknownWarningsArePassedThrough() {
        let odd = "Something the app has never heard of happened."
        let notes = RegistryPresentation.footerNotes(
            for: response([entry()], warnings: [odd]),
            ordering: .bestMatch
        )
        #expect(notes.contains(odd))
    }

    @Test("a known warning keeps the router's own text and adds what it means on screen")
    func knownWarningsAreExpandedNotReplaced() {
        let raw = "The official registry was unreachable (HTTP 503)."
        let notes = RegistryPresentation.footerNotes(
            for: response([entry()], warnings: [raw]),
            ordering: .bestMatch
        )
        let expanded = notes.first { $0.contains("unreachable") }
        #expect(expanded?.contains(raw) == true, "the router's own words are kept")
        #expect(expanded != raw, "and its consequence for what is on screen is added")
    }

    @Test("the subtitle counts what is on screen, not what matched")
    func subtitleCountsWhatIsDrawn() {
        // Saying "47 servers" above a list of one would be the board contradicting itself.
        #expect(RegistryPresentation.subtitle(for: response([entry()], merged: 47))
            == "Official registry · Smithery · 1 server")
        #expect(RegistryPresentation.subtitle(for: response([entry(id: "a"), entry(id: "b")]))
            .hasSuffix("2 servers"))
    }

    // MARK: - A8 · the three empties are distinct

    @Test("the three empty states are keyed on the query and the ordering together")
    func emptyMessagesAreDistinct() throws {
        // A scoped ordering emptied a response that does have rows: the search found things, this
        // ordering simply cannot speak about them.
        let officialOnly = response([entry(id: "a"), entry(id: "b")])
        let scoped = try #require(
            RegistryPresentation.emptyMessage(officialOnly, ordering: .mostUsed, query: "")
        )
        #expect(scoped.resetsOrdering)
        #expect(!scoped.clearsSearch)
        #expect(scoped.action == "Show best match")

        // A query matched nothing.
        let queried = try #require(
            RegistryPresentation.emptyMessage(response([]), ordering: .bestMatch, query: "  postgres ")
        )
        #expect(queried.clearsSearch)
        #expect(!queried.resetsOrdering)
        #expect(queried.title.contains("postgres"), "the query is quoted back, trimmed")

        // Both indexes answered and neither listed anything.
        let cold = try #require(
            RegistryPresentation.emptyMessage(response([]), ordering: .bestMatch, query: "   ")
        )
        #expect(!cold.clearsSearch)
        #expect(!cold.resetsOrdering)
        #expect(cold.title == "Neither index returned anything")

        // Whitespace alone is not a query — the M4 defect was a view re-deciding this against an
        // untrimmed string the presentation layer had already called blank.
        #expect(cold != queried)

        // A populated board has no empty message at all.
        #expect(RegistryPresentation.emptyMessage(
            response([entry()]), ordering: .bestMatch, query: ""
        ) == nil)
    }

    // MARK: - Hostile input

    /// Every string on this board is chosen by whoever published the entry, and this is the surface
    /// where a user decides whether to run their code.
    @Test("bidirectional overrides and control characters never reach a view")
    func hostileTextIsStripped() {
        let spoofed = "evil\u{202E}-server"
        #expect(!RegistryPresentation.sanitized(spoofed).unicodeScalars.contains { $0.value == 0x202E })

        let isolates = "a\u{2066}b\u{2069}c"
        #expect(RegistryPresentation.sanitized(isolates) == "abc")

        // C0 including newline and tab, DEL, and C1. A newline inside `args` would let an entry
        // inject extra lines into the block the capability statement offers as ground truth.
        #expect(RegistryPresentation.sanitized("a\nb\tc\u{7F}d\u{85}e") == "abcde")
    }

    /// **Written from the threat, not from the implementation.**
    ///
    /// The test above tested exactly the four families the filter already handled, which is a test
    /// derived from the code and structurally unable to find the gap in it. These four families
    /// defeated that filter, and one of them is the newline the argv rule claims to keep out.
    @Test("the invisible characters a filter written from its own code would miss")
    func hostileTextBeyondTheObviousFamilies() {
        // Implicit marks: they reorder a run with no embedding, so the U+202A–202E range misses
        // them entirely. This is the classic display-spoofing pair.
        #expect(RegistryPresentation.sanitized("evil\u{200E}-server") == "evil-server")
        #expect(RegistryPresentation.sanitized("evil\u{200F}-server") == "evil-server")
        #expect(RegistryPresentation.sanitized("evil\u{061C}-server") == "evil-server")

        // Line and paragraph separators — a line break that is not a C0 control, and therefore
        // exactly the argv injection the C0 rule was written to prevent, in the form it missed.
        #expect(RegistryPresentation.sanitized("npx\u{2028}rm -rf") == "npxrm -rf")
        #expect(RegistryPresentation.sanitized("npx\u{2029}rm -rf") == "npxrm -rf")

        // Zero-width: two different strings that draw identically, on the surface whose whole job
        // is helping someone identify what they are about to run.
        #expect(RegistryPresentation.sanitized("git\u{200B}hub") == "github")
        #expect(RegistryPresentation.sanitized("git\u{200C}hub") == "github")
        #expect(RegistryPresentation.sanitized("git\u{200D}hub") == "github")

        // Deprecated format controls.
        #expect(RegistryPresentation.sanitized("a\u{206A}b\u{206F}c") == "abc")

        // And the filter still leaves ordinary text — including non-Latin scripts — alone, so this
        // is not passing by stripping everything.
        #expect(RegistryPresentation.sanitized("Ünïcödé — 日本語 · 🎛") == "Ünïcödé — 日本語 · 🎛")

        // Ordinary text is untouched, including non-ASCII that is not a control.
        #expect(RegistryPresentation.sanitized("GitHub — Modèle 日本語") == "GitHub — Modèle 日本語")
    }

    @Test("an unbounded string is capped rather than allowed to deny the surface")
    func longTextIsCapped() {
        let huge = String(repeating: "x", count: 4096)
        let capped = RegistryPresentation.sanitized(huge, cap: 60)
        #expect(capped.count == 61, "sixty characters and the ellipsis that says there were more")
        #expect(capped.hasSuffix("…"))
        // Under the cap, nothing is added — an ellipsis on a complete string is a false claim that
        // something was withheld.
        #expect(RegistryPresentation.sanitized("short", cap: 60) == "short")
    }

    @Test("the monogram survives a name made entirely of control characters")
    func monogramNeverEmpty() {
        #expect(RegistryPresentation.monogram(for: entry(displayName: "GitHub Server")) == "GS")
        #expect(RegistryPresentation.monogram(for: entry(displayName: "github")) == "GI")
        #expect(RegistryPresentation.monogram(for: entry(displayName: "\u{202E}\u{2066}")) == "?")
        #expect(RegistryPresentation.monogram(for: entry(displayName: "")) == "?")
    }
}
