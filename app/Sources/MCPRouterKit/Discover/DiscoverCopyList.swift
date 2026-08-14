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

        case .bandEmptyMostUsed:
            // A5, and Most used gets its own sentence because **the window does not reach this
            // band** (A4). Offering "widen the window" here would advise an action that cannot
            // change what is shown, under a claim about a filter that was never applied. It is the
            // common case rather than an edge one: the official registry publishes no popularity
            // figure at all, so an all-official page empties this band every time.
            DiscoverCopy.Entry(
                headline: "No result here has a session count.",
                body: """
                Only Smithery publishes one, so entries the official registry alone carries are \
                absent from this band rather than ranked at zero.
                """
            )

        case .bandEmptyRecentlyChangedWindowed:
            DiscoverCopy.Entry(
                headline: "Nothing in these results changed in the last {window} days.",
                body: "Widen the window to see more.",
                actionLabel: "Any time"
            )

        case .bandEmptyRecentlyChangedAnyTime:
            // Under Any time no window is applied, so emptiness means something else entirely: no
            // entry carried a change date this app could read. One shared template rendered
            // "Nothing in these results changed in the last Any time days" — ungrammatical, false,
            // and offering an "Any time" action that reset the window to the one already chosen.
            DiscoverCopy.Entry(
                headline: "No result here carries a change date.",
                body: "Neither index reported when these entries were last changed."
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
