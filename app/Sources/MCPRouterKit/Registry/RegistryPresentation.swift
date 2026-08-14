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
            // Parsed once per row rather than inside the comparator. A comparator that parses does
            // it O(n log n) times, and each parse builds two `ISO8601DateFormatter`s — so a 200-row
            // response would build a few thousand formatters to sort itself. Decorating first makes
            // it exactly one parse per row.
            let dated = scoped.map { (entry: $0, date: timestamp($0.updatedAt)) }
            return stableSorted(dated) { lhs, rhs in
                // A row with no parseable date sorts last rather than to the top, which is where
                // `nil` read as the distant past or the distant future would put it.
                switch (lhs.date, rhs.date) {
                case let (left?, right?): left > right
                case (.some, .none): true
                case (.none, .some), (.none, .none): false
                }
            }.map(\.entry)
        }
    }

    /// A stable sort, by construction.
    ///
    /// `useCount` and `updatedAt` tie constantly — both are absent on whole classes of row — and
    /// Swift's `sort` carries no stability guarantee. An unstable sort over a response whose own
    /// order is already non-deterministic gives a list that reshuffles between renders of *the same
    /// data*, which looks exactly like the board reloading when it has not.
    ///
    /// Generic over the element so the date ordering can sort rows it has already parsed, rather
    /// than re-parsing inside the comparator.
    static func stableSorted<Element>(
        _ rows: [Element],
        by areInIncreasingOrder: (Element, Element) -> Bool
    ) -> [Element] {
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
        case .bestMatch:
            return nil
        case .mostUsed:
            return """
            Nothing in this search carries a usage figure, so there is nothing to order by.
            """
        case .recentlyAdded:
            return """
            Nothing in this search came from Smithery, so there is no add date to order by.
            """
        }
    }
}
