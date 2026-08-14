import Foundation

// The capability plate and the one commit.
//
// Every plate line is *derived from the install descriptor*, never authored per entry, and the
// plate is drawn above the commit rather than behind a disclosure control (A12). The brief's rule:
// the security fact is never behind a tap the user can skip.

public extension DiscoverCopy.PlateKey {
    var entry: DiscoverCopy.Entry {
        switch self {
        case .stdio:
            DiscoverCopy.Entry(body: "Runs a program on your Mac, with your own access")

        case .remote:
            // A13: this names the host, and is a fact line rather than an amber one. For a remote
            // MCP server the decision that matters is that tool arguments leave the machine —
            // treating remote as the quiet case inverts the real risk. It is not `--attn` because
            // the user is queueing for review, not granting access, and an amber block that fires
            // on everything stops meaning anything.
            DiscoverCopy.Entry(body: "Nothing runs on your Mac; requests go to {host}")

        case .unknownHost:
            // A13's remote line when the url does not parse. Naming the wrong host is worse than
            // admitting which host is unknown, because the whole point of the line is telling the
            // user where their tool arguments go.
            DiscoverCopy.Entry(body: """
            Nothing runs on your Mac; requests go to an address neither index published
            """)

        case .credential:
            DiscoverCopy.Entry(body: "Needs a credential, entered on your Mac")

        case .credentialSmithery:
            // A14: every Smithery-hosted install declares a required `Authorization`
            // unconditionally, so within that subset the line distinguishes nothing. Saying so is
            // the difference between a warning and noise.
            DiscoverCopy.Entry(body: """
            Needs a Smithery API key, entered on your Mac. Every Smithery-hosted entry asks for \
            one, so this doesn't set this server apart from the others there.
            """)

        case .archived:
            DiscoverCopy.Entry(body: "The repository is archived; nobody is maintaining it")

        case .noInstall:
            DiscoverCopy.Entry(body: "Neither index says how this server runs")

        case .invocationLabel:
            DiscoverCopy.Entry(body: "What would run")
        }
    }
}

public extension DiscoverCopy.QueueFailureKey {
    /// The write failed. States what happened and what to do, next to the thing that failed, and
    /// does not blame or emote (`DESIGN.md` §6, `SWIFT_PRACTICES.md` §3).
    ///
    /// Here rather than in the view, because a sentence assembled at a call site is invisible to
    /// all three copy checks — the pinned literal, the render assertion and the mock-parity scan.
    var entry: DiscoverCopy.Entry {
        switch self {
        case .unreadable:
            DiscoverCopy.Entry(
                body: "This phone's queue couldn't be read, so nothing was saved. Try again."
            )

        case .writeFailed:
            DiscoverCopy.Entry(
                body: "This phone couldn't save the item, so nothing was queued. Try again."
            )
        }
    }
}

public extension DiscoverCopy.CommitKey {
    /// Seven states, all carrying the narrowing (A20). Verb-first and no ellipsis, because it
    /// commits now rather than opening a further view (A16, `DESIGN.md` §3.4, §6).
    var entry: DiscoverCopy.Entry {
        switch self {
        case .reachable:
            DiscoverCopy.Entry(
                body: "Reachable — items you send arrive now.",
                actionLabel: "Send to Mac",
                carriesNarrowing: true
            )

        case .notReachable:
            // A18: live, and relabelled. This writes one item to a local queue, which succeeds
            // with the Mac asleep — so disabling it would refuse an act that works. The label
            // changes because a button reading "Send" above a note reading "saved" contradicts
            // itself. This diverges from I1's `SendCommitBar` deliberately: that is Queue's
            // *send these now* batch control and is right to disable on `.notReachable`.
            DiscoverCopy.Entry(
                body: """
                Can't reach {mac} right now. This is saved here; send it from Queue when it's back.
                """,
                actionLabel: "Save for your Mac",
                carriesNarrowing: true
            )

        case .neverPaired:
            DiscoverCopy.Entry(
                body: "No Mac paired yet, so there's nowhere to send this.",
                actionLabel: "Send to Mac",
                isDisabled: true,
                carriesNarrowing: true
            )

        case .noDescriptor:
            DiscoverCopy.Entry(
                body: """
                Neither index says how this server runs, so there's nothing for your Mac to review.
                """,
                actionLabel: "Send to Mac",
                isDisabled: true,
                carriesNarrowing: true
            )

        case .queuedReachable:
            // Success is an in-place state change. macOS does not toast a click and neither does
            // this (`DESIGN.md` §5, §7).
            DiscoverCopy.Entry(
                body: "Waiting for review on {mac}.",
                actionLabel: "Queued for your Mac",
                isDisabled: true,
                carriesNarrowing: true
            )

        case .queuedNotReachable:
            // A21: says where the item is and how it goes, never that it will go on its own. No
            // item owns flush-on-reachable, so copy promising one would promise nothing.
            DiscoverCopy.Entry(
                body: "Send it from Queue when {mac} is back.",
                actionLabel: "Saved on this phone",
                isDisabled: true,
                carriesNarrowing: true
            )

        case .alreadyDeclared:
            // A23: rendered as the name match it is. The router compares `displayName` against
            // locally declared server keys, which both false-positives on a shared last path
            // segment and misses on case — so the copy may not assert an identity the comparison
            // cannot establish.
            DiscoverCopy.Entry(
                body: "A server called {name} is already declared on {mac}.",
                actionLabel: "Already on your Mac",
                isDisabled: true,
                carriesNarrowing: true
            )
        }
    }
}
