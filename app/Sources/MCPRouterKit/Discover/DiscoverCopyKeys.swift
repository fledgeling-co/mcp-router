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
        case bandEmpty
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
        case credential
        case credentialSmithery
        case archived
        case noInstall
        case invocationLabel
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
