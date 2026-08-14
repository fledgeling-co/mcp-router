import Foundation

// The seven key types `DiscoverCopy.Key` is a sum over — one per UI element, so each element's
// copy is a switch that is total over its own type. Case lists only; the copy itself lives beside
// each element's `entry` property.

public extension DiscoverCopy {
    /// The two band headers and their notes.
    enum BandKey: String, Sendable, CaseIterable {
        case mostUsed
        case mostUsedNote
        case recentlyChanged
        case recentlyChangedNote
    }

    /// The window control: its label, the two sentences that state which band it drives, and its
    /// four options.
    enum WindowKey: String, Sendable, CaseIterable {
        case label
        case appliesTo
        case disabledInSearch
        case anyTime
        case ninety
        case thirty
        case seven
    }

    /// The search field, and the units every figure in the feature carries.
    ///
    /// A unit is copy rather than presentation: `DiscoverPresentation` decides *which digits*, this
    /// decides what they are called. Keeping the two apart is what lets A7 assert that the digits
    /// trace to a named field while A6 asserts that the label names what Smithery published.
    enum UnitKey: String, Sendable, CaseIterable {
        case searchPlaceholder
        /// What VoiceOver says while the skeleton rows are on screen. In the manifest rather than
        /// on the view, because a paraphrase written at the call site drifts from the placeholder
        /// it is paraphrasing and no copy check can see it.
        case searchingAccessibility
        case useCount
        case stars
        case truncated
    }

    /// The list's states — `DESIGN.md` §5's nine, less the two it does not have.
    ///
    /// `Default` is the populated list and carries no copy of its own; `Success` is absent by
    /// construction, because the list has no commit. Both are recorded in the spec's state matrix
    /// rather than given invented strings.
    enum ListKey: String, Sendable, CaseIterable {
        case emptyNoQuery
        case emptyQuery
        /// A5, and **three keys rather than one**, because one sentence cannot be true of all
        /// three cases. Most used does not respond to the window at all (A4), and Recently changed
        /// under `anyTime` has no window applied — so a single "nothing changed in the last
        /// {window} days" is ungrammatical for one of them and false for two.
        case bandEmptyMostUsed
        case bandEmptyRecentlyChangedWindowed
        case bandEmptyRecentlyChangedAnyTime
        case partialOfficialDown
        case partialSmitheryDown
        case partialGitHubLimited
        case partialUnrecognised
        case failed
        case offline
    }

    /// Detail's states and its fact chips.
    ///
    /// Detail performs no fetch (A11), so its Empty, Loading and Error are structurally unreachable
    /// and have no keys. Their absence is the point: writing plausible copy for a state that cannot
    /// occur is scaffolding wearing a design's clothes.
    enum DetailKey: String, Sendable, CaseIterable {
        case partialNoRepository
        case partialGitHubLimited
        case offline
        case noLastCommit
        case lastCommit
        case chipSourceOfficial
        case chipSourceSmithery
        case chipSourceBoth
        case chipArchived
    }

    /// The capability plate — the five derivations of A13, the credential line's Smithery variant,
    /// and the label above the literal invocation.
    enum PlateKey: String, Sendable, CaseIterable {
        case stdio
        case remote
        /// The remote line when `install.url` does not parse. A line naming the wrong host is worse
        /// than one admitting it does not know which host, because the whole point of the line is
        /// telling the user where their arguments go.
        case unknownHost
        case credential
        case credentialSmithery
        case archived
        case noInstall
        case invocationLabel
    }

    /// What the commit says when the local queue write is refused.
    ///
    /// Its own element type rather than a commit state: these are not states the commit resolves
    /// into, they are what is rendered beside it when a write fails. In the manifest because
    /// `DESIGN.md` §6 governs them like any other user-facing sentence — what happened and what to
    /// do, next to the thing that failed.
    enum QueueFailureKey: String, Sendable, CaseIterable {
        case unreadable
        case writeFailed
    }

    /// The commit — the seven states of A16–A21. Every one of them carries the narrowing (A20),
    /// and `DiscoverCopy.narrowingKeys` is derived from this type rather than restated.
    enum CommitKey: String, Sendable, CaseIterable {
        case reachable
        case notReachable
        case neverPaired
        case noDescriptor
        case queuedReachable
        case queuedNotReachable
        case alreadyDeclared
    }
}
