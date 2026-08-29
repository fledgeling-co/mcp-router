import Foundation

/// One catalogue the report compared against, and how old it is.
///
/// The age is the point. Nothing in F6 refreshes a catalogue — 2 of the 10 marketplaces on this
/// machine are not git checkouts at all, so even a refresh has a class it cannot serve, and
/// reaching the network is the act the brief puts behind user approval. So the router does not get
/// to say *up to date* without saying what it read and when that last moved.
public struct CatalogueReading: Sendable, Hashable {
    public let name: String
    public let path: String
    /// The newest modification time anywhere in the catalogue's tree, or `nil` when it could not be
    /// measured. Never `0` for "not measured" — a zero here is a measurement (`DESIGN.md` §6).
    public let newestModifiedMilliseconds: Double?
    public let ageMilliseconds: Double?
    /// `true` when the age is past the caller's `staleAfterMs`. `false` when the age is unknown,
    /// with ``problem`` carrying the reason — an unknown age is reported rather than assumed stale.
    public let stale: Bool
    /// `true` when the entry holds a `.git` directory. A report that implied every catalogue could
    /// be refreshed would be wrong for 2 of the 10 on this machine, in the place a caller decides
    /// what to do next.
    public let refreshable: Bool
    public let offers: Int
    public let declaredNoVersion: Int
    /// Why the catalogue could not be **read**, or `nil`. This is the only one of the two that
    /// reaches a verdict: a catalogue nobody could parse cannot offer a version to compare with.
    public let problem: String?
    /// Why the catalogue's **age** could not be taken, or `nil`.
    ///
    /// Kept apart from ``problem`` deliberately, and the separation was found by a failing test
    /// rather than reasoned: folding the two together made an unmeasurable age suppress every
    /// version comparison against a catalogue that was perfectly readable, turning eight verdicts
    /// into `noCatalogue`. How old a file is and whether it parses are independent questions.
    public let ageProblem: String?

    public init(
        name: String,
        path: String,
        newestModifiedMilliseconds: Double?,
        ageMilliseconds: Double?,
        stale: Bool,
        refreshable: Bool,
        offers: Int,
        declaredNoVersion: Int,
        problem: String?,
        ageProblem: String? = nil
    ) {
        self.name = name
        self.path = path
        self.newestModifiedMilliseconds = newestModifiedMilliseconds
        self.ageMilliseconds = ageMilliseconds
        self.stale = stale
        self.refreshable = refreshable
        self.offers = offers
        self.declaredNoVersion = declaredNoVersion
        self.problem = problem
        self.ageProblem = ageProblem
    }
}

/// One installed entry, and what comparing it produced.
public struct FreshnessRow: Sendable {
    public let kind: ExtensionKind
    public let name: String
    /// The catalogue this row was compared against, or `nil` when there was none.
    public let catalogue: String?
    public let verdict: FreshnessVerdict

    public init(kind: ExtensionKind, name: String, catalogue: String?, verdict: FreshnessVerdict) {
        self.kind = kind
        self.name = name
        self.catalogue = catalogue
        self.verdict = verdict
    }
}

/// The counts, with the invariant that keeps a later verdict from landing in neither class.
public struct FreshnessSummary: Sendable, Hashable {
    public let total: Int
    public let updatesAvailable: Int
    public let compared: Int
    public let uncomparable: Int
    public let staleCatalogues: Int

    public init(rows: [FreshnessRow], catalogues: [CatalogueReading]) {
        total = rows.count
        updatesAvailable = rows.count { $0.verdict.hasUpdate }
        compared = rows.count { $0.verdict.isComparison }
        uncomparable = rows.count { !$0.verdict.isComparison }
        staleCatalogues = catalogues.count(where: \.stale)
    }
}

/// Every entry of every requested kind, the catalogues behind them, and the counts.
public struct FreshnessReport: Sendable {
    public let rows: [FreshnessRow]
    public let catalogues: [CatalogueReading]
    public let summary: FreshnessSummary
    public let checkedAtMilliseconds: Double
    public let staleAfterMilliseconds: Double
    /// A kind whose directory could not be read, with the reason. Separate from an empty row set:
    /// a store nobody has written to and a store that could not be opened are both "no rows".
    public let unreadable: [String]

    public init(
        rows: [FreshnessRow],
        catalogues: [CatalogueReading],
        checkedAtMilliseconds: Double,
        staleAfterMilliseconds: Double,
        unreadable: [String]
    ) {
        self.rows = rows
        self.catalogues = catalogues
        summary = FreshnessSummary(rows: rows, catalogues: catalogues)
        self.checkedAtMilliseconds = checkedAtMilliseconds
        self.staleAfterMilliseconds = staleAfterMilliseconds
        self.unreadable = unreadable
    }
}
