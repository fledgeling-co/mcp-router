import Foundation

/// What the Official mark asserts, and what it does not.
///
/// Every string is the mock's own (`design/mcp-router-console.html`, `id="sh-official"`), because
/// this sheet is a definition and the definition is the design. It lives here rather than in the
/// view for the reason every other `*Copy` enum in this module does: a claim about what a trust
/// mark means is worth being able to assert without a render.
///
/// **The mock's publisher grid is not here, and its absence is deliberate.** The sheet draws eight
/// publisher cards with counts — `Anthropic · 12 servers · 4 skills` — and `RegistryEntry` has no
/// publisher field. What it has is `source`, which is *which index supplied the row*, not who
/// published it. Deriving a publisher by parsing `name` does not work either: the entries are
/// `github`, `deepwiki` and `ai.smithery/Hint-Services-obsidian-github-mcp`, so a namespace parse
/// would invent an ownership claim the index never made — which is the exact claim this sheet
/// exists to explain the app does not invent. Grouping by `source` instead was considered and
/// rejected on this module's own evidence: `RegistryPresentation` records that a figure must come
/// "never off `sources.official`, which is a pre-merge, pre-slice count of a different set".
public enum OfficialMarkCopy {
    public static let title = "What “official” means here"

    public static let lede = """
    It is a statement about who published an entry, and nothing else. It is not a quality mark, \
    not a review, and not a security assessment — a community server can be better written than \
    an official one, and installing either still shows you the same consent sheet.
    """

    public static let conditionsHeading = "An entry is official when both hold"

    public static let conditions = [
        """
        The index that supplied it lists the publisher as the owner of the namespace the entry \
        sits in. That is the index's assertion, read from its response, not ours.
        """,
        """
        The publisher is the vendor whose product the entry talks to. A GitHub server published \
        by GitHub is official; an excellent GitHub server published by someone else is community.
        """
    ]

    public static let limitsHeading = "What the mark does not tell you"

    public static let limits = """
    Whether it is maintained. Whether its checks pass — that is the Checks board, and it is \
    measured here rather than claimed by a publisher. Whether it is safe to give this particular \
    server this particular access; that decision is the consent sheet's, every time, official or \
    not.
    """

    /// Why the publishers the mock lists are not drawn.
    ///
    /// On the surface rather than in this comment, because a section that silently disappears
    /// reads as a design that never had it. `DESIGN.md` §5's partial state: say what arrived and
    /// what did not, with the reason.
    public static let publishersUnavailable = """
    The mock lists the publishers currently matching. This app cannot: neither index reports a \
    publisher for an entry, and reading one out of the entry's name would be a claim about \
    namespace ownership that nobody made.
    """

    public static let dismiss = "Close"
}

public extension DiscoverCopy {
    /// The control that opens `OfficialMarkSheet`, from the mock's own quiet button.
    ///
    /// Lives beside the sheet's copy rather than in `DiscoverCopy.swift` so M18's additions are
    /// readable in one place; it extends `DiscoverCopy` because that is where a Discover string is
    /// looked for.
    static var officialMarkAction: String { "What is official?" }
}

/// Where the servers this router starts look for their binaries.
///
/// **This sheet is a refusal, and it is built rather than skipped for a reason with two
/// precedents in this repo.** The mock draws a resolved seven-directory `PATH`, six per-CLI
/// found/not-found pills, and a callout naming the directory the snapshot missed. Every one of
/// those is a statement about the environment the router's *children* inherit. The router computes
/// it and publishes it nowhere: `ControlAPIClient` declares nineteen methods and none returns a
/// path, an environment or a resolved search list.
///
/// Reading this app's own login-shell `PATH` would produce a different number under the same
/// label — the app is a GUI process launched by Finder, the router is a launchd agent, and R6
/// exists precisely because those two environments differ. `DESIGN.md` §6 and
/// `SWIFT_PRACTICES.md` §5: no number is displayed that the router does not observe.
///
/// So the surface says what it will show and why it cannot yet, which is how `PairingSheet` and
/// `HeldVersionSheet` already handle a decision whose mechanism is not there.
public enum ChildPathCopy {
    public static let title = "What your servers can find"

    public static let lede = """
    Every server this router starts inherits an environment from it. A launchd agent gets a \
    minimal PATH by default, which is right for a daemon that runs its own code and wrong for one \
    whose job is running yours.
    """

    public static let unavailableHeading = "The router does not report this yet"

    public static let unavailable = """
    The router resolves the search path it hands its children, and does not publish it, so there \
    is nothing here this app could show you that it had actually measured. Showing this Mac's own \
    login-shell path instead would be a different list under the same heading — the app and the \
    router start from different environments, which is the whole reason this panel exists.
    """

    public static let dismiss = "Close"
}
