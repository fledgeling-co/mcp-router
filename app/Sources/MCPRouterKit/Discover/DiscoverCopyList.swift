import Foundation

public extension DiscoverCopy.ListKey {
    var entry: DiscoverCopy.Entry {
        switch self {
        case .emptyNoQuery:
            DiscoverCopy.Entry(
                headline: "Nothing came back from either index.",
                body: "Both registries answered and neither listed anything.",
                actionLabel: "Try again"
            )

        case .emptyQuery:
            DiscoverCopy.Entry(
                headline: "No server matches \u{201C}{query}\u{201D}.",
                body: """
                Search covers the official MCP registry and Smithery. Try a shorter word, or clear \
                the search to browse the bands.
                """,
                actionLabel: "Clear search"
            )

        case .bandEmpty:
            // A5: one band empty while the other is populated is the common case, not an edge
            // case, and it is not the whole-list Empty state.
            DiscoverCopy.Entry(
                headline: "Nothing in these results changed in the last {window} days.",
                body: "Widen the window to see more.",
                actionLabel: "Any time"
            )

        case .partialOfficialDown:
            DiscoverCopy.Entry(
                headline: "Showing Smithery only.",
                body: "The official registry didn't answer, so anything it alone lists is missing.",
                actionLabel: "Try again"
            )

        case .partialSmitheryDown:
            DiscoverCopy.Entry(
                headline: "Showing the official registry only.",
                body: """
                Smithery didn't answer, so anything it alone lists is missing — including the \
                session counts Most used ranks on.
                """,
                actionLabel: "Try again"
            )

        case .partialGitHubLimited:
            DiscoverCopy.Entry(
                headline: "Repository details are incomplete.",
                body: """
                GitHub limits how often it can be asked, so stars and archive status are missing \
                for some entries. Everything else is complete.
                """
            )

        case .partialUnrecognised:
            // A25: a warning matching no known class renders verbatim under a generic heading
            // rather than being dropped. The wire carries free text and the classification is by
            // prefix, so this is the case that keeps a reworded warning visible.
            DiscoverCopy.Entry(headline: "The search reported a problem.", body: "{warning}")

        case .failed:
            DiscoverCopy.Entry(
                headline: "The registry search failed.",
                body: "{reason}. Nothing was queued and nothing changed on your Mac.",
                actionLabel: "Try again"
            )

        case .offline:
            // A27: `DESIGN.md` §5 asks Offline to "offer to start it". The phone cannot start a
            // process on the Mac, so it gives the instruction instead — a recorded deviation with
            // its reason, not a criterion quietly passed off as satisfied.
            DiscoverCopy.Entry(
                headline: "The router isn't running on {mac}.",
                body: """
                Discover reads the registries through it, so nothing can be searched until it \
                starts. Open MCP Router on your Mac.
                """
            )
        }
    }
}
