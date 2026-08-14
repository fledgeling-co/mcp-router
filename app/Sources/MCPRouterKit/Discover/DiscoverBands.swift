import Foundation

/// The two bands Discover ships, and the window that filters one of them.
///
/// **Two, not the brief's three, and the reason is in the data rather than in taste.** The brief
/// asks for "recently added / popular / trending over a chosen window". `useCount` is published, so
/// popular ships. `updatedAt` is on every entry, so recently-added ships re-labelled and re-scoped.
/// Trending requires two observations of the same quantity over time, and **the router keeps none**
/// — `github-cache.json` holds current values with one freshness stamp and overwrites them on
/// refresh, so no rate, delta or per-window change is computable for any entry. A trend band would
/// have to be invented, and this product displays no number the router does not observe.
///
/// The obvious replacement — ranking on `pushedAt` as "actively worked on" — was considered and
/// rejected. That field is present for at most 10 entries per search, never for Smithery-hosted
/// ones, and **which** 10 is decided by merge order rather than by any property of the entries. A
/// band is a ranking claim about a population; ranking on a field whose membership is an artifact
/// of a fetch budget makes a claim the data cannot support. The repository activity moved to Detail
/// as a per-entry fact instead, where its absence can be explained rather than silently changing an
/// order.
public enum DiscoverBand: String, Sendable, CaseIterable, Identifiable {
    case mostUsed
    case recentlyChanged

    public var id: String { rawValue }

    public var titleKey: DiscoverCopy.Key {
        switch self {
        case .mostUsed: .band(.mostUsed)
        case .recentlyChanged: .band(.recentlyChanged)
        }
    }

    /// One quiet secondary sentence under the header (`DESIGN.md` §6 helper text).
    ///
    /// **Every note is scoped to "the results shown", and none asserts an index-wide fact.**
    /// `/registry/search` sorts by `useCount → stars → updatedAt` and *then* truncates with
    /// `results.slice(0, limit)`, so the client receives the top N by popularity and cannot ask for
    /// anything else. Any order this app applies is a re-sort of a popularity-selected page, and
    /// may only make claims about the rows in front of the user.
    public var noteKey: DiscoverCopy.Key {
        switch self {
        case .mostUsed: .band(.mostUsedNote)
        case .recentlyChanged: .band(.recentlyChangedNote)
        }
    }

    /// Whether the window control affects this band.
    ///
    /// Only `recentlyChanged` does. `useCount` is a cumulative all-time total, and slicing it by a
    /// window would assert a per-window figure that was never measured — the same defect as a
    /// trend band, in a quieter costume. The asymmetry is stated on the control itself
    /// (`DiscoverCopy.Key.window(.appliesTo)`) rather than left to be discovered.
    public var respondsToWindow: Bool { self == .recentlyChanged }
}

/// The window offered on Recently changed.
///
/// **`anyTime` is the default, and that is a data decision rather than a convenience.** The
/// recorded fixture's newest `updatedAt` is 2025-11-19, outside every offered window, so any other
/// default would render an empty band on first open — a designed-in empty state, which is a
/// different thing from an empty state that a search happened to produce.
public enum RecencyWindow: String, Sendable, CaseIterable, Identifiable {
    case anyTime
    case ninety
    case thirty
    case seven

    public var id: String { rawValue }

    /// The window in days, or nil for no filter.
    public var days: Int? {
        switch self {
        case .anyTime: nil
        case .ninety: 90
        case .thirty: 30
        case .seven: 7
        }
    }

    public var copyKey: DiscoverCopy.Key {
        switch self {
        case .anyTime: .window(.anyTime)
        case .ninety: .window(.ninety)
        case .thirty: .window(.thirty)
        case .seven: .window(.seven)
        }
    }

    public var label: String { DiscoverCopy.entry(copyKey).body }
}

/// Band membership and ordering, as pure functions over the results already in hand.
public enum DiscoverBands {
    /// The entries in a band, ordered.
    ///
    /// **An entry lacking a band's field is absent from that band, never ranked at zero** (A2). A
    /// missing `useCount` means Smithery does not index the entry — the official registry publishes
    /// no popularity figure at all — and placing it last as a zero would assert a measurement of
    /// nobody using it. Absence says "not measured"; zero says "measured, and none".
    ///
    /// Ties break on `id` ascending so the order is total and stable. SwiftUI keys rows by
    /// identity, and an unstable sort makes rows swap places on a re-render that changed nothing.
    public static func members(
        of band: DiscoverBand,
        in entries: [RegistryEntry],
        window: RecencyWindow,
        now: Date = Date()
    ) -> [RegistryEntry] {
        switch band {
        case .mostUsed:
            // The window is not consulted here, and a test asserts this membership is identical
            // across all four windows. That assertion is the guard on A4: the tidy-looking change
            // is to filter both bands by the window, and it would silently make Most used claim a
            // per-window session count that was never measured.
            return entries
                .filter { $0.useCount != nil }
                .sorted { lhs, rhs in
                    let left = lhs.useCount ?? 0
                    let right = rhs.useCount ?? 0
                    return left == right ? lhs.id < rhs.id : left > right
                }

        case .recentlyChanged:
            let cutoff = window.days.map { days in
                now.addingTimeInterval(-Double(days) * 86400)
            }
            return entries
                .compactMap { entry -> (RegistryEntry, Date)? in
                    guard let changed = DiscoverPresentation.date(from: entry.updatedAt) else {
                        // An unparseable stamp drops the entry from this band rather than sorting
                        // it to one end. It is still reachable from Most used and from search.
                        return nil
                    }
                    if let cutoff, changed < cutoff { return nil }
                    return (entry, changed)
                }
                .sorted { lhs, rhs in
                    lhs.1 == rhs.1 ? lhs.0.id < rhs.0.id : lhs.1 > rhs.1
                }
                .map(\.0)
        }
    }

    /// Whether a band is empty while the list as a whole is not — the case A5 gives its own state.
    ///
    /// One band empty while the other is populated is the **common** case, not an edge case: an
    /// entire index publishes no `useCount`, and every window but Any time excludes the fixture's
    /// newest entry. It is not the whole-list Empty state and does not borrow its copy.
    public static func isBandEmptyWithinResults(
        _ band: DiscoverBand,
        in entries: [RegistryEntry],
        window: RecencyWindow,
        now: Date = Date()
    ) -> Bool {
        !entries.isEmpty && members(of: band, in: entries, window: window, now: now).isEmpty
    }
}
