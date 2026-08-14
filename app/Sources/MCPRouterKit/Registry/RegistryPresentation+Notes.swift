import Foundation

/// What the board says *about* its result: the subtitle, the footer's honesty notes, and the
/// three distinct empties.
///
/// Split from `RegistryPresentation` for length alone. Grouped because every member here is a
/// sentence the board says in its own voice rather than a value read off a row — which is exactly
/// the class of text that has to be computed from the response instead of written as a constant.
public extension RegistryPresentation {
    // MARK: - Header

    /// The subtitle under "Discover".
    ///
    /// Names both indexes, because the board's whole subject is that this is a merged catalogue,
    /// and counts **what is on screen** rather than what matched. The difference between the two is
    /// the footer's first sentence, and saying "47 servers" above a list of 30 would be the board
    /// contradicting itself.
    static func subtitle(for response: RegistrySearchResponse) -> String {
        let shown = response.results.count
        return "Official registry · Smithery · \(shown) \(shown == 1 ? "server" : "servers")"
    }

    // MARK: - The footer

    /// What `Best match` actually ranks on — disclosed, because it is not neutral.
    ///
    /// `RegistryMerge.rank` sorts on `useCount` desc, then `stars` desc, then `updatedAt`, and it
    /// reads a missing `useCount` as `0`. Only Smithery publishes a usage figure, so **every
    /// official-only row sorts below every Smithery row that has any usage at all**. That is a
    /// structural bias toward one commercial index, and a board that discloses the bias of its two
    /// scoped orderings while presenting the default as "best match" would be hiding the larger one.
    static let rankingNote = """
    Best match is the router's own order: most sessions on Smithery first, then GitHub stars, then \
    date. Only Smithery publishes a session count, so entries that appear only in the official \
    registry sort below entries that have one.
    """

    /// Everything the board must admit about the result it is drawing, computed from the response.
    ///
    /// The brief's rule: "Where a count is incomplete, say so in the footer rather than presenting
    /// a partial ranking as total." Each sentence appears only when its condition holds — a
    /// permanently-visible caveat is one nobody reads by the third visit — except the two that are
    /// always true.
    ///
    /// An unrecognised warning is passed through **verbatim** rather than dropped. Swallowing a
    /// warning this code has no nicer sentence for would leave the board silently confident about a
    /// result the router flagged (`SWIFT_PRACTICES.md` §3).
    static func footerNotes(
        for response: RegistrySearchResponse,
        ordering: Ordering = .bestMatch
    ) -> [String] {
        var notes: [String] = []

        let shown = response.results.count
        if response.sources.merged > shown {
            notes.append("""
            Showing \(shown) of \(response.sources.merged) that matched. The rest are not ranked \
            lower — they are past the limit this search asked for.
            """)
        }
        if ordering == .bestMatch {
            notes.append(rankingNote)
        }
        for warning in response.warnings {
            notes.append(expand(warning))
        }
        notes.append(trendingNote)
        return notes
    }

    /// Stated once, always, and naming its successor rather than apologising.
    ///
    /// The brief asked for a trending band — "a signed delta over a stated window". Nothing in this
    /// product keeps a history of either index, so there is no delta to sign. It is not that a
    /// derived figure is forbidden; a delta between two responses this app received would be
    /// observed. It is that the number would mean "sessions gained on Smithery while this Mac
    /// happened to be awake, over a window starting whenever each row first appeared in a search
    /// here" — telemetry about the user's own use of this app, presented as a fact about the
    /// ecosystem.
    ///
    /// The successor is named so this reads as scaffolding rather than a tombstone: the router runs
    /// persistently and the app does not, so a snapshot table there makes the figure legitimate.
    static let trendingNote = """
    No trend or velocity figure is shown. Measuring one needs a history of these indexes over \
    time, which the router does not keep yet.
    """

    /// Turns the router's terse warning into a sentence saying what it means for what is on screen,
    /// keeping the router's own text so the fact and its consequence are both visible.
    ///
    /// **The consequence must not out-claim the warning.** This used to append "Everything here
    /// came from the other index alone, so nothing that index carries is missing on purpose" to
    /// anything containing `unreachable` — but a warning reading "the official registry was
    /// partially unreachable" makes that sentence false, and the board would then be stating, as
    /// fact, a completeness claim inferred from a substring. The added sentence now says only what
    /// follows from the warning whatever its scope: some of that index is missing, and its absence
    /// is not a judgement about the rows that are here.
    static func expand(_ warning: String) -> String {
        let lowered = warning.lowercased()
        if lowered.contains("unreachable") {
            return """
            \(warning). What that index carries is under-represented here, and a row missing for \
            that reason is missing by accident rather than by rank.
            """
        }
        if lowered.contains("github") {
            return """
            \(warning) Star counts therefore cover some rows and not others. A row without one is \
            not less popular; it is unmeasured.
            """
        }
        return warning
    }

    // MARK: - Empty

    /// What an empty result says, and what its one action does.
    ///
    /// Carries the action's *effect* rather than leaving the view to re-derive it: M4 recorded a
    /// button labelled "Show all skills" that cleared the search instead, because the view
    /// re-decided "is there a search" against an untrimmed string the presentation layer had
    /// already called blank. One judgement, made once, decides both the label and what it does.
    struct EmptyMessage: Equatable, Sendable {
        public var title: String
        public var detail: String
        public var action: String
        public var clearsSearch: Bool
        public var resetsOrdering: Bool
    }

    /// Keyed on the query **and** the ordering, because this board has three distinct empties and
    /// keying on either alone renders the wrong one — or none, leaving column headers over blank
    /// space, which is M4's recorded defect.
    static func emptyMessage(
        _ response: RegistrySearchResponse,
        ordering: Ordering,
        query: String
    ) -> EmptyMessage? {
        guard rows(response, ordering: ordering).isEmpty else { return nil }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // A scoped ordering emptied a response that does have rows: the search found things, this
        // ordering simply cannot speak about them.
        if !response.results.isEmpty {
            let others = response.results.count
            return EmptyMessage(
                title: ordering == .mostUsed
                    ? "Nothing here carries a usage figure"
                    : "Nothing here came from Smithery",
                detail: """
                \(ordering == .mostUsed ? "Usage figures" : "Add dates") come from Smithery, and \
                none of these rows carries one. The other \(others) \(others == 1 ? "is" : "are") \
                still here under best match.
                """,
                action: "Show best match",
                clearsSearch: false,
                resetsOrdering: true
            )
        }

        if !trimmed.isEmpty {
            return EmptyMessage(
                title: "Nothing matches \u{201C}\(sanitized(trimmed, cap: 60))\u{201D}",
                detail: """
                Neither index has a server whose name or description contains that. Both match on \
                whole words, so a shorter query often finds more.
                """,
                action: "Clear search",
                clearsSearch: true,
                resetsOrdering: false
            )
        }

        return EmptyMessage(
            title: "Neither index returned anything",
            detail: """
            The official registry and Smithery both answered, and neither lists a server right \
            now. That is unusual — it is more often a sign the indexes are having a bad day than \
            that the catalogue is empty.
            """,
            action: "Search again",
            clearsSearch: false,
            resetsOrdering: false
        )
    }

    // MARK: - Row warnings

    /// The one warning worth carrying on a row rather than in the sheet.
    ///
    /// `archived` is observed — GitHub reported it — and it is the single most useful thing to know
    /// before running someone's code. It renders in `--attn` because it genuinely wants a human
    /// decision, and the *word* carries the meaning so colour is never the only signal
    /// (`DESIGN.md` §2).
    static func archivedNote(for entry: RegistryEntry) -> String? {
        (entry.archived ?? false) ? "repository archived" : nil
    }

    /// What the skeleton has to admit, because this board's loading is not a flicker.
    ///
    /// A cold search is two index calls at a 12-second timeout **plus** up to ten sequential GitHub
    /// requests at the same timeout each (`Registry.enrichWithStars`), so the worst case is minutes
    /// rather than the second or two every other board's loading state lasts. A skeleton that sits
    /// there silently for two minutes reads as a hang; saying so, and offering a way out, is the
    /// difference.
    static let slowSearchNote = """
    Searching both registries. This can take a while the first time — star counts are fetched one \
    repository at a time and cached for a day.
    """
}
