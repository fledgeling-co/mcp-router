import Foundation

/// Triage's commit and state copy.
///
/// Split from `TriageCopy` **before it grew past the cap, not after**. The seam is real — the keys,
/// the entry type and the row-level vocabulary are one thing; the commit bar and the nine
/// `DESIGN.md` §5 states are another — and it is taken now because `TriageCopy` was already at 330
/// of the 400-line limit with the state matrix only partly written, and because `make format`'s own
/// wrapping *adds* lines and has pushed files past that cap in this repo before. A split designed
/// under a red gate is a split designed in a hurry.
///
/// The precedent is I2's: it split `DiscoverCopy` into six files with no rule suppressions at all,
/// where I1's single `PairingCopy` carries a four-rule file-scope disable instead. This follows I2.
extension TriageCopy {
    // MARK: - The commit

    static func commit(_ key: CommitKey) -> Entry {
        switch key {
        case .ready:
            Entry(
                body: "Queues them for review on {mac}.",
                actionLabel: "Send {count} to Mac",
                carriesNarrowing: true
            )
        case .neverPaired:
            Entry(
                body: "No Mac paired yet, so there is nowhere to send this. Pair one in Settings.",
                actionLabel: "Send {count} to Mac",
                isDisabled: true,
                carriesNarrowing: true
            )
        case .dismiss:
            Entry(body: "Not for me")
        case .undoQueued:
            Entry(body: "{count} queued for your Mac")
        case .undoDismissed:
            Entry(body: "{count} moved to Not for me")
        case .undo:
            Entry(body: "Undo")
        case .partialWrite:
            Entry(
                headline: "Some of those were not saved.",
                body: """
                {count} are in the queue. The rest were refused by this phone and are still in \
                Undecided.
                """
            )
        case .writeFailed:
            Entry(
                headline: "That was not saved.",
                body: "This phone refused the write, so nothing was queued. Try again."
            )
        }
    }

    // MARK: - The capability clauses

    static func clause(_ key: ClauseKey) -> Entry {
        switch key {
        case .runsLocally:
            Entry(body: "Runs a program on your Mac")
        case .remote:
            Entry(body: "Nothing runs on your Mac · {host}")
        case .remoteUnknownHost:
            // The plate's own reasoning, kept: a line naming the wrong host is worse than one
            // admitting it does not know which, because the point of the line is telling the user
            // where their arguments go.
            Entry(body: "Nothing runs on your Mac · the index does not say where requests go")
        case .credential:
            Entry(body: "needs a credential")
        case .credentialSmithery:
            // Carries no attention severity, and the words say why. Every Smithery-hosted install
            // declares a required Authorization unconditionally, so inside that subset the warning
            // distinguishes nothing — and Smithery is most of the corpus.
            Entry(body: "needs Smithery's key, which every entry there declares")
        case .archived:
            Entry(body: "repository archived")
        case .noInstall:
            Entry(body: "Neither index says how this runs")
        }
    }

    // MARK: - States

    /// The states, split in two on a real seam rather than by raising a limit.
    ///
    /// An empty bucket and a degraded search are different kinds of thing: the first is a fact about
    /// the user's own decisions and always offers the act that fills it, the second is a fact about
    /// the router or this phone's storage and always offers a retry. They are written separately.
    static func state(_ key: StateKey) -> Entry {
        switch key {
        case .emptyUndecided: emptyState(.undecided)
        case .emptyQueued: emptyState(.queued)
        case .emptyDismissed: emptyState(.dismissed)
        default: degradedState(key)
        }
    }

    /// The three bucket empties. One bucket empty while another is populated is the common case,
    /// not an edge case — it is what a working week looks like.
    ///
    /// **Keyed on `TriageBucket` rather than on `StateKey`**, so the switch is total over a
    /// three-case type and needs no `default`. Keyed on `StateKey` it would need one, and the only
    /// things available to put there are a crash or a fabricated string.
    private static func emptyState(_ bucket: TriageBucket) -> Entry {
        switch bucket {
        case .undecided:
            // No recency claim. There is no feed, no cursor and no seen-state anywhere in this
            // product, so "nothing new since Tuesday" is not a thing that can be said honestly.
            Entry(
                headline: "Nothing left to decide",
                body: """
                You have decided on everything in these results. Search Discover for something \
                specific, or widen what you are looking at.
                """,
                actionLabel: "Go to Discover"
            )
        case .queued:
            Entry(
                headline: "Nothing queued yet",
                body: "Tick something in Undecided and send it across.",
                actionLabel: "Go to Undecided"
            )
        case .dismissed:
            Entry(
                headline: "Nothing turned down",
                body: """
                Anything you turn down stays here, so a decision made on a train is still readable at \
                your desk.
                """
            )
        }
    }

    /// Everything the router or the phone's own storage can go wrong with.
    ///
    /// The three empties route here only if `state(_:)` is ever changed to send them; they are
    /// listed so this switch stays total over `StateKey` without a `default` that could silently
    /// absorb a state added later.
    private static func degradedState(_ key: StateKey) -> Entry {
        switch key {
        case .emptyUndecided: emptyState(.undecided)
        case .emptyQueued: emptyState(.queued)
        case .emptyDismissed: emptyState(.dismissed)
        case .partialOfficialDown:
            Entry(
                headline: "Showing Smithery only.",
                body: "The official registry did not answer, so anything it alone lists is missing.",
                actionLabel: "Try again"
            )
        case .partialSmitheryDown:
            Entry(
                headline: "Showing the official registry only.",
                body: "Smithery did not answer, so anything it alone lists is missing.",
                actionLabel: "Try again"
            )
        case .partialGitHubLimited:
            Entry(
                headline: "Repository details are incomplete.",
                body: """
                GitHub limits how often it can be asked, so archive status is missing for some \
                entries. Everything else is complete.
                """
            )
        case .partialUnrecognised:
            Entry(
                headline: "The search reported a problem.",
                body: "{warning}"
            )
        case .failed:
            Entry(
                headline: "The registry search failed",
                body: """
                The router answered, but not with results. Nothing was queued and nothing changed on \
                your Mac.
                """,
                actionLabel: "Try again"
            )
        case .offline:
            Entry(
                headline: "The router is not running on {mac}",
                body: """
                Triage reads the registries through it, so there is nothing to decide on until it \
                starts. Open MCP Router on your Mac.
                """
            )
        case .dismissalsUnreadable:
            Entry(
                headline: "Your dismissals could not be read.",
                body: """
                Something is saved on this phone and this version cannot decode it, so things you \
                turned down may be listed again. Nothing has been deleted.
                """,
                actionLabel: "Try again"
            )
        }
    }
}
