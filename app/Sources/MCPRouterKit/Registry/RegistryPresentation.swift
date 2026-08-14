import Foundation

/// Every decision the Discover board makes, with no UI framework in sight.
///
/// The split follows the Skills board's, and for its stated reason: a branch only a running app
/// can exercise is a branch that ships wrong. Everything here is reachable from a test without a
/// host.
///
/// **What makes this board different from every other one.** On every other surface a number is
/// either observed or absent, and `DESIGN.md` §6 is satisfied by leaving out what the router
/// cannot see. Here the data is not the router's own — it is what two third-party indexes said,
/// merged — so a figure can be present *for some rows and not others*, one field can mean *two
/// different things depending on which index the row came from*, and **every string on the surface
/// is attacker-controlled**. All three are worse than absence, because a partial or spoofed signal
/// presented as a total one is a false claim wearing the costume of a feature.
///
/// Four rules follow, and each is a function below rather than a convention:
///
/// 1. **Provenance is derived from evidence, not from the `source` label.** See `Provenance`.
/// 2. **A figure carries its unit and its universe.** `2,984` and `9` under one heading read as one
///    scale; `2,984 sessions` and `9 stars` cannot be.
/// 3. **An ordering is offered only over a universe where its signal is complete**, and says what
///    it set aside.
/// 4. **Every third-party string is sanitised before it reaches a view.** See `sanitized`.
public enum RegistryPresentation {
    // MARK: - Provenance

    /// Which index actually supplied a row, established from evidence rather than from `source`.
    ///
    /// **`source` cannot be trusted to mean what it says, and the shipped fixture proves it.**
    /// `RegistryMerge.merge` builds one map keyed by `dedupeKey`, puts every official row in, then
    /// folds Smithery rows onto whatever it finds already there — and what it finds can be *another
    /// Smithery row*, because the Smithery pass writes into the same map it reads. When that
    /// happens it still stamps `source: "both"`. `dedupeKey` falls back to a normalised
    /// `displayName` whenever `repository` yields no `owner/repo`, so two Smithery entries sharing
    /// a display name collide.
    ///
    /// This is not hypothetical. In `Fixtures/registry-search.json` the first row is
    /// `id: "smithery:github"`, `source: "both"`, `repository: "https://github.com/"` — a bare host
    /// with no owner or repo. It is two Smithery rows that collided on the name "github", and
    /// nothing official is behind it.
    ///
    /// Two consequences, both of which would have been defects:
    ///
    /// - A date labelled by `source` would print **"updated"** over a Smithery `createdAt` on that
    ///   very row.
    /// - A provenance mark filled from `source` would light the *official registry* cell — the
    ///   strongest trust signal on an install surface — from an attacker-chosen `displayName`.
    ///
    /// The reliable evidence is the **`id` prefix**. `RegistryMerge.smitheryRow` sets
    /// `id = "smithery:<qualifiedName>"`; `officialRow` sets `id` to the entry's own name; and the
    /// merge preserves the *base* row's `id` (`merged = existing.spread()` overrides only `source`,
    /// `useCount`, `verified`, `iconUrl` and `install`). So the prefix names whichever builder made
    /// the surviving row.
    public struct Provenance: Equatable, Sendable {
        /// The surviving base row was built from an official-registry entry.
        public var isOfficial: Bool
        /// Smithery contributed this row — as its base, or folded onto an official one.
        public var isSmithery: Bool

        /// True only for a row an official entry actually underlies.
        public var showsOfficialMark: Bool { isOfficial }
    }

    /// The prefix `RegistryMerge.smitheryRow` stamps onto every id it creates.
    static let smitheryIDPrefix = "smithery:"

    public static func provenance(for entry: RegistryEntry) -> Provenance {
        // A row whose id carries the Smithery prefix was built by `smitheryRow`, whatever `source`
        // was later stamped on it.
        let smitheryBased = entry.id.hasPrefix(smitheryIDPrefix)
        return Provenance(
            isOfficial: !smitheryBased,
            isSmithery: smitheryBased || entry.source == .smithery || entry.source == .both
        )
    }

    // MARK: - Universes

    /// The set of rows an ordering is honest over.
    ///
    /// Three rather than two, and the third is the one that is easy to get wrong. The usage figure
    /// and the first-published date do **not** live on the same rows: the merge overrides
    /// `useCount` onto a row it folds Smithery into, but `updatedAt` is not among the fields it
    /// overrides — so an official-based row keeps the official registry's entry-update time even
    /// when Smithery data has been folded onto it.
    public enum Universe: String, Sendable, Equatable, CaseIterable {
        case all
        /// Rows that actually carry a usage figure. Defined by the figure's presence rather than by
        /// a source label, so it is exactly the set the ordering can speak about.
        case carriesUsage
        /// Rows whose `updatedAt` is genuinely a first-published date — Smithery-based rows.
        case datePublished

        func contains(_ entry: RegistryEntry) -> Bool {
            switch self {
            case .all: true
            case .carriesUsage: entry.useCount != nil
            case .datePublished: dateMeaning(for: entry) == .firstPublished
            }
        }
    }

    // MARK: - Ordering

    /// The three orderings, each named for the universe it is honest over.
    ///
    /// **There is deliberately no "most starred".** Star enrichment spends at most ten GitHub
    /// fetches per call and stops on the first rate-limited response, but results are cached for
    /// 24 hours and applied before any budget is spent — so coverage *accumulates* across calls
    /// rather than churning. That is the accurate reading of `Registry.enrichWithStars`, and it is
    /// still a reason to refuse the ordering: coverage grows as this Mac searches, so the same
    /// query ranks differently on Tuesday than on Monday for reasons that are about this machine's
    /// cache rather than about the servers. Stars are still *displayed* where present, because a
    /// star count is a fact.
    ///
    /// **There is no trending ordering.** See `trendingNote`.
    public enum Ordering: String, CaseIterable, Sendable, Identifiable {
        /// The router's own merged rank, passed through untouched.
        case bestMatch
        case mostUsed
        case recentlyAdded

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .bestMatch: "Best match"
            case .mostUsed: "Most used on Smithery"
            case .recentlyAdded: "Recently added to Smithery"
            }
        }

        public var universe: Universe {
            switch self {
            case .bestMatch: .all
            case .mostUsed: .carriesUsage
            case .recentlyAdded: .datePublished
            }
        }
    }

    /// The rows to draw, in order.
    ///
    /// `bestMatch` returns the response's own sequence **untouched** — not re-sorted, not
    /// stabilised, not reversed. It is the router's ranking, and the moment this applies its own
    /// comparator the board is presenting an ordering the app invented while labelling it the
    /// router's.
    public static func rows(_ response: RegistrySearchResponse, ordering: Ordering) -> [RegistryEntry] {
        let universe = ordering.universe
        let scoped = response.results.filter { universe.contains($0) }
        switch ordering {
        case .bestMatch:
            return scoped
        case .mostUsed:
            return stableSorted(scoped) { ($0.useCount ?? 0) > ($1.useCount ?? 0) }
        case .recentlyAdded:
            return stableSorted(scoped) { lhs, rhs in
                // A row with no parseable date sorts last rather than to the top, which is where
                // `nil` read as the distant past or the distant future would put it.
                switch (timestamp(lhs.updatedAt), timestamp(rhs.updatedAt)) {
                case let (left?, right?): left > right
                case (.some, .none): true
                case (.none, .some), (.none, .none): false
                }
            }
        }
    }

    /// A stable sort, by construction.
    ///
    /// `useCount` and `updatedAt` tie constantly — both are absent on whole classes of row — and
    /// Swift's `sort` carries no stability guarantee. An unstable sort over a response whose own
    /// order is already non-deterministic gives a list that reshuffles between renders of *the same
    /// data*, which looks exactly like the board reloading when it has not.
    static func stableSorted(
        _ rows: [RegistryEntry],
        by areInIncreasingOrder: (RegistryEntry, RegistryEntry) -> Bool
    ) -> [RegistryEntry] {
        rows.enumerated()
            .sorted { lhs, rhs in
                if areInIncreasingOrder(lhs.element, rhs.element) { return true }
                if areInIncreasingOrder(rhs.element, lhs.element) { return false }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// How many rows the ordering's universe set aside. Counted off the rows actually returned —
    /// never off `sources.official`, which is a pre-merge, pre-slice count of a different set.
    public static func excludedCount(_ response: RegistrySearchResponse, ordering: Ordering) -> Int {
        let universe = ordering.universe
        return response.results.count { !universe.contains($0) }
    }

    /// The quiet sentence under a scoped ordering, naming the count and the actual reason.
    ///
    /// `nil` when nothing was excluded — a sentence saying "0 rows are not shown" is noise about a
    /// condition that never applied.
    public static func exclusionNote(
        _ response: RegistrySearchResponse,
        ordering: Ordering
    ) -> String? {
        let excluded = excludedCount(response, ordering: ordering)
        guard excluded > 0, ordering != .bestMatch else { return nil }
        let noun = excluded == 1 ? "row is" : "rows are"
        switch ordering {
        case .bestMatch:
            return nil
        case .mostUsed:
            return """
            \(excluded) \(noun) not shown here: they carry no usage figure, because only Smithery \
            publishes one and it publishes it only for its own entries.
            """
        case .recentlyAdded:
            return """
            \(excluded) \(noun) not shown here: the official registry records when an entry was \
            last updated rather than when it was added, and ordering the two together would sort \
            two different clocks against each other.
            """
        }
    }

    /// Why a scoped ordering is unavailable, when its universe is empty.
    ///
    /// The segment dims in place carrying this (`DESIGN.md` §3.4 — disabled dims and never
    /// disappears) rather than being hidden, which would leave the control silently changing shape
    /// between searches.
    public static func disabledReason(
        _ response: RegistrySearchResponse,
        ordering: Ordering
    ) -> String? {
        let universe = ordering.universe
        guard ordering != .bestMatch,
              !response.results.contains(where: { universe.contains($0) }) else { return nil }
        switch ordering {
        case .bestMatch: return nil
        case .mostUsed: return "Nothing in this search carries a usage figure, so there is nothing to order by."
        case .recentlyAdded: return "Nothing in this search came from Smithery, so there is no add date to order by."
        }
    }

    // MARK: - The date, and its two meanings

    /// What a row's `updatedAt` actually means.
    ///
    /// `RegistryMerge.officialRow` takes it from `_meta` — a **registry-entry update**.
    /// `RegistryMerge.smitheryRow` takes it from Smithery's **`createdAt`** — a **first-published**
    /// date. One wire field, two meanings, and which one is settled by `provenance` rather than by
    /// `source`, for the reason `Provenance` documents at length.
    public enum DateMeaning: String, Sendable, Equatable, CaseIterable {
        case entryUpdated
        case firstPublished

        public var verb: String {
            switch self {
            case .entryUpdated: "updated"
            case .firstPublished: "added"
            }
        }
    }

    public static func dateMeaning(for entry: RegistryEntry) -> DateMeaning {
        provenance(for: entry).isOfficial ? .entryUpdated : .firstPublished
    }

    public struct DateCell: Equatable, Sendable {
        public var text: String
        public var meaning: DateMeaning
    }

    /// The date as it reads on a row, or `nil` when there is no parseable date.
    ///
    /// `nil` rather than a placeholder: `updatedAt` is optional on the wire, and an em-dash where a
    /// date belongs is a quieter lie than a wrong date but a lie all the same. The cell is simply
    /// not drawn.
    public static func dateCell(for entry: RegistryEntry) -> DateCell? {
        guard let date = timestamp(entry.updatedAt) else { return nil }
        let meaning = dateMeaning(for: entry)
        return DateCell(text: "\(meaning.verb) \(dayFormatter.string(from: date))", meaning: meaning)
    }

    /// When GitHub last saw a push to the repository — an index-independent fact, and the best
    /// answer available to "is this still alive".
    ///
    /// Shown in the detail sheet rather than on the row: it is present only where enrichment
    /// reached, so a row column would be empty for most rows and read as a claim about them. It is
    /// never an ordering, for the same reason stars are not.
    public static func lastPushed(for entry: RegistryEntry) -> String? {
        guard let date = timestamp(entry.pushedAt) else { return nil }
        return "code last pushed \(dayFormatter.string(from: date))"
    }

    /// Both shapes the indexes actually emit.
    ///
    /// Smithery sends `2025-11-19T07:26:28.312Z` and the official registry
    /// `2025-09-14T15:20:36.371442Z` — three and six fractional digits — while GitHub's `pushedAt`
    /// has none. One formatter configured for fractional seconds rejects the third; one configured
    /// without rejects the first two. Trying both is what makes every real row parse.
    static func timestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = fractionalFormatter.date(from: raw) { return date }
        return plainFormatter.date(from: raw)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plainFormatter = ISO8601DateFormatter()

    /// Held once. A `DateFormatter` built per row is the classic way a table becomes slow.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("d MMM y")
        return formatter
    }()

    // MARK: - The figure

    /// The one number a row carries, with its unit and where it came from.
    ///
    /// Never a bare integer: `2,984` and `9` on adjacent rows under one heading would read as one
    /// scale, and they are not on one scale.
    public struct Figure: Equatable, Sendable {
        public var text: String
        public var attribution: String
    }

    /// `nil` when the row carries neither figure — **never a zero**.
    ///
    /// A rendered `0` claims the number was measured and found to be none. For an official-only row
    /// there is no usage figure in existence to be zero; for a row enrichment never reached there
    /// is a star count that simply was not fetched.
    public static func figure(for entry: RegistryEntry) -> Figure? {
        if let uses = entry.useCount {
            return Figure(
                text: "\(decimal(uses)) \(uses == 1 ? "session" : "sessions")",
                attribution: "sessions started, as counted by Smithery"
            )
        }
        if let stars = entry.stars {
            return Figure(
                text: "\(decimal(stars)) \(stars == 1 ? "star" : "stars")",
                attribution: "stars on GitHub"
            )
        }
        return nil
    }

    static func decimal(_ value: Int) -> String {
        decimalFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    // MARK: - Sanitising third-party text

    /// Strips what a hostile index entry would use to make text lie about itself.
    ///
    /// Every string on this board — `displayName`, `name`, `description`, and every element of an
    /// install command — is chosen by whoever published the entry, and this is the surface where a
    /// user decides whether to run their code. Two classes are removed:
    ///
    /// - **Bidirectional overrides and isolates** (U+202A–U+202E, U+2066–U+2069). A right-to-left
    ///   override inside a `displayName` renders `evil-server` as `revres-live`, which is a spoof
    ///   of the one field the user reads to identify what they are installing.
    /// - **C0 and C1 controls**, newline and tab included. A newline inside `args` lets an entry
    ///   inject extra lines into the block the capability statement offers as ground truth — text
    ///   that appears to be the app speaking.
    ///
    /// Applied at the boundary, so no view can forget it.
    public static func sanitized(_ raw: String) -> String {
        String(raw.unicodeScalars.filter { scalar in
            if (0x202A ... 0x202E).contains(scalar.value) { return false }
            if (0x2066 ... 0x2069).contains(scalar.value) { return false }
            // C0 (including \n and \t), DEL, and C1.
            if scalar.value < 0x20 || scalar.value == 0x7F { return false }
            if (0x80 ... 0x9F).contains(scalar.value) { return false }
            return true
        })
    }

    /// Sanitised, and capped so one entry cannot push everything else off the surface.
    ///
    /// The cap is not a layout nicety: `description` is unbounded on the wire, and a megabyte of
    /// text in a sheet is a denial of the sheet.
    public static func sanitized(_ raw: String, cap: Int) -> String {
        let clean = sanitized(raw)
        guard clean.count > cap else { return clean }
        return String(clean.prefix(cap)) + "…"
    }

    // MARK: - Artwork

    /// This board never loads a remote image, and the reason is the product's own boundary.
    ///
    /// `iconUrl` is a URL chosen by a third-party index. Fetching it would (a) make the Mac app
    /// open a connection to a host of an attacker's choosing, disclosing the user's address once
    /// per row, and (b) violate the standing constraint that the app talks to the router **only**
    /// over the loopback control API — an outbound fetch to `api.smithery.ai` is a second channel,
    /// which is the one thing that boundary exists to forbid.
    ///
    /// So every row draws the authored monogram plate (`DESIGN.md` §4's provision for an entry
    /// whose marketplace ships no art), and no gradient rectangle stands anywhere. Serving the real
    /// artwork means proxying it through the router, which is a router-side item.
    public static let remoteArtworkRefusal = """
    Artwork is drawn locally. This app fetches nothing from the registries directly — it talks only \
    to the router on this Mac.
    """

    /// The one or two letters on the monogram plate, from the name the entry gave.
    public static func monogram(for entry: RegistryEntry) -> String {
        let clean = sanitized(entry.displayName).trimmingCharacters(in: .whitespacesAndNewlines)
        let words = clean.split(separator: " ", omittingEmptySubsequences: true)
        if let first = words.first, let initial = first.first {
            if words.count > 1, let second = words.dropFirst().first?.first {
                return "\(initial)\(second)".uppercased()
            }
            return String(first.prefix(2)).uppercased()
        }
        return "?"
    }

    // MARK: - Header

    /// The subtitle under "Discover".
    ///
    /// Names both indexes, because the board's whole subject is that this is a merged catalogue,
    /// and counts **what is on screen** rather than what matched. The difference between the two is
    /// the footer's first sentence, and saying "47 servers" above a list of 30 would be the board
    /// contradicting itself.
    public static func subtitle(for response: RegistrySearchResponse) -> String {
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
    public static let rankingNote = """
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
    public static func footerNotes(
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
    public static let trendingNote = """
    No trend or velocity figure is shown. Measuring one needs a history of these indexes over \
    time, which the router does not keep yet.
    """

    /// Turns the router's terse warning into a sentence saying what it means for what is on screen,
    /// keeping the router's own text so the fact and its consequence are both visible.
    static func expand(_ warning: String) -> String {
        let lowered = warning.lowercased()
        if lowered.contains("unreachable") {
            return """
            \(warning). Everything here came from the other index alone, so nothing that index \
            carries is missing on purpose.
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
    public struct EmptyMessage: Equatable, Sendable {
        public var title: String
        public var detail: String
        public var action: String
        public var clearsSearch: Bool
        public var resetsOrdering: Bool
    }

    /// Keyed on the query **and** the ordering, because this board has three distinct empties and
    /// keying on either alone renders the wrong one — or none, leaving column headers over blank
    /// space, which is M4's recorded defect.
    public static func emptyMessage(
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
    public static func archivedNote(for entry: RegistryEntry) -> String? {
        (entry.archived ?? false) ? "repository archived" : nil
    }

    /// What the skeleton has to admit, because this board's loading is not a flicker.
    ///
    /// A cold search is two index calls at a 12-second timeout **plus** up to ten sequential GitHub
    /// requests at the same timeout each (`Registry.enrichWithStars`), so the worst case is minutes
    /// rather than the second or two every other board's loading state lasts. A skeleton that sits
    /// there silently for two minutes reads as a hang; saying so, and offering a way out, is the
    /// difference.
    public static let slowSearchNote = """
    Searching both registries. This can take a while the first time — star counts are fetched one \
    repository at a time and cached for a day.
    """
}
