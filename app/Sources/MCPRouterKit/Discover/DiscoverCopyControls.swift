import Foundation

// The chrome around the list: the band headers, the window control, and the units every figure
// carries. Three total switches, one per element.

public extension DiscoverCopy.BandKey {
    var entry: DiscoverCopy.Entry {
        switch self {
        case .mostUsed:
            DiscoverCopy.Entry(body: "Most used")

        case .mostUsedNote:
            DiscoverCopy.Entry(body: """
            Sessions started on Smithery, all-time, of the results shown. The only popularity \
            figure either index publishes — the official registry publishes none, so entries it \
            alone carries are absent from this band rather than ranked at zero.
            """)

        case .recentlyChanged:
            DiscoverCopy.Entry(body: "Recently changed")

        case .recentlyChangedNote:
            DiscoverCopy.Entry(body: """
            The most recently changed of the results shown. The official registry reports when an \
            entry was last edited; Smithery reports when it was created. They are different stamps \
            under one field, so this orders them without claiming they mean the same thing.
            """)
        }
    }
}

public extension DiscoverCopy.WindowKey {
    var entry: DiscoverCopy.Entry {
        switch self {
        case .label:
            DiscoverCopy.Entry(body: "Chosen window")

        case .appliesTo:
            DiscoverCopy.Entry(body: """
            The window filters recently changed. Most used is an all-time total and has no window.
            """)

        case .disabledInSearch:
            DiscoverCopy.Entry(body: "Search results aren't windowed.", isDisabled: true)

        case .anyTime:
            DiscoverCopy.Entry(body: "Any time")

        case .ninety:
            DiscoverCopy.Entry(body: "90 days")

        case .thirty:
            DiscoverCopy.Entry(body: "30 days")

        case .seven:
            DiscoverCopy.Entry(body: "7 days")
        }
    }
}

public extension DiscoverCopy.UnitKey {
    var entry: DiscoverCopy.Entry {
        switch self {
        case .searchPlaceholder:
            // Plural, because two indexes are searched and either can fail alone (A9). It never
            // says "skills": there is no skills index on either router, so a placeholder promising
            // one would promise a capability the product does not have.
            DiscoverCopy.Entry(body: "Search the server registries")

        case .searchingAccessibility:
            DiscoverCopy.Entry(body: "Searching the server registries")

        case .useCount:
            // "sessions on Smithery" — never "installs", never "downloads". Smithery publishes
            // sessions started, and the unit names both the quantity and who published it (A6).
            DiscoverCopy.Entry(body: "{count} sessions on Smithery")

        case .stars:
            DiscoverCopy.Entry(body: "{count} stars on GitHub")

        case .truncated:
            DiscoverCopy.Entry(body: "Showing the first {count} matches. Narrow the search to see others.")
        }
    }
}
