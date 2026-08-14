import Foundation

// swiftlint:disable cyclomatic_complexity function_body_length type_body_length file_length
//
// The same four metric rules `PairingCopy.swift` disables, disabled here for the same reason and
// on the same terms. `entry(_:)` is one exhaustive `switch` over `Key`, and that exhaustiveness is
// the guarantee: a tenth state added to a surface fails to **compile** until someone writes its
// copy, rather than shipping a blank pane. A switch over a 40-case enum has a cyclomatic
// complexity of 40 by construction, so the metric and the compile-time guarantee cannot both hold.
// Splitting it into per-surface functions returning `Entry?` chained with `??` is exactly how the
// guarantee is lost — a missing key becomes a runtime nil instead of a build failure.
//
// Every case is a `return` with no condition and nothing that can fail. The rules that catch real
// defects — force-unwrap, line length, naming — stay on. The exemption covers this file only.

/// Every user-facing string in Discover and capability detail, keyed by **surface × state**.
///
/// A **sibling** of `PairingCopy`, never an extension of it. `PairingCopy` is a merged shared
/// surface; growing one from inside a feature is how two features come to disagree about what it
/// contains. The one thing this file takes from it is `PairingCopy.neverInstalls`, consumed
/// verbatim rather than paraphrased — three paraphrases of a permission boundary is how a user
/// ends up believing the loosest one.
///
/// **This enum is where every string in the feature lives, including the numbers' units.** No view
/// under `Phone/Discover/` composes a sentence, and `DiscoverPresentation` is the only file that
/// formats a value into one. That is what makes A1 and A7 — "no rate, delta or percentage
/// anywhere" and "every numeric string maps to a named `RegistryEntry` field" — assertions over an
/// enumerable set rather than hopes about a view hierarchy.
public enum DiscoverCopy {
    // MARK: - Substitution

    /// The complete set of substitutions any template in this file may carry.
    ///
    /// An enum rather than free-form interpolation because A28 requires each template's
    /// substitutions to be *enumerated*: `DiscoverCopyTests` walks every entry, extracts the
    /// `{token}`s it actually contains, and fails on one that is not a case here. A typo'd
    /// `{mack}` would otherwise render literally to the user and pass every test.
    public enum Token: String, Sendable, CaseIterable {
        /// The paired Mac's name.
        case mac
        /// A count that came from a named `RegistryEntry` field, already formatted.
        case count
        /// The user's search text, echoed back.
        case query
        /// The chosen recency window, in days.
        case window
        /// A registry entry's display name.
        case name
        /// A failure, rendered from `DiscoverFailureReason` — never the router's free-text body.
        case reason
        /// A warning the router sent that matched no known class, carried verbatim.
        case warning
        /// The host a remote server's requests go to.
        case host

        public var placeholder: String { "{\(rawValue)}" }
    }

    /// A rendered piece of copy.
    ///
    /// `headline` is nil where the state renders inline beside a control rather than as a pane.
    /// For a commit state, `actionLabel` is the **button's label** and `body` is the note beneath
    /// it — the two are one entry because a button whose label and note disagree is the specific
    /// defect A18 exists to prevent, and keeping them adjacent makes the disagreement visible.
    public struct Entry: Sendable, Equatable {
        public let headline: String?
        public let body: String
        public let actionLabel: String?
        /// Whether the control this copy describes is dimmed. `DESIGN.md` §3.4: disabled dims in
        /// place with a discoverable reason, and `body` is that reason.
        public let isDisabled: Bool
        /// Whether this surface also carries `PairingCopy.neverInstalls`.
        public let carriesNarrowing: Bool

        public init(
            headline: String? = nil,
            body: String,
            actionLabel: String? = nil,
            isDisabled: Bool = false,
            carriesNarrowing: Bool = false
        ) {
            self.headline = headline
            self.body = body
            self.actionLabel = actionLabel
            self.isDisabled = isDisabled
            self.carriesNarrowing = carriesNarrowing
        }

        /// Every token that actually appears in this entry's text.
        public var tokens: Set<Token> {
            let text = (headline ?? "") + body + (actionLabel ?? "")
            return Set(Token.allCases.filter { text.contains($0.placeholder) })
        }

        /// Substitute values into the template.
        ///
        /// A token with no supplied value is left as its placeholder rather than silently emptied:
        /// a visible `{mac}` is a bug report, and a sentence that quietly loses its subject is not.
        public func resolved(_ values: [Token: String]) -> Entry {
            func sub(_ text: String) -> String {
                values.reduce(text) { partial, pair in
                    partial.replacingOccurrences(of: pair.key.placeholder, with: pair.value)
                }
            }
            return Entry(
                headline: headline.map(sub),
                body: sub(body),
                actionLabel: actionLabel.map(sub),
                isDisabled: isDisabled,
                carriesNarrowing: carriesNarrowing
            )
        }
    }

    // MARK: - Keys

    /// Which surface a key belongs to. Used to group the completeness check, so "the narrowing is
    /// on every commit state" is a claim a test can evaluate rather than an intention.
    public enum Surface: String, Sendable, CaseIterable {
        case controls
        case list
        case detail
        case plate
        case commit
    }

    /// Every surface-and-state that renders copy in this feature.
    public enum Key: String, Sendable, CaseIterable {
        // MARK: Controls, bands and units

        case searchPlaceholder
        case bandMostUsed
        case bandMostUsedNote
        case bandRecentlyChanged
        case bandRecentlyChangedNote
        case windowLabel
        case windowAppliesTo
        case windowDisabledInSearch
        case windowAnyTime
        case windowNinety
        case windowThirty
        case windowSeven
        case useCountUnit
        case starsUnit
        case truncated

        // MARK: The list — `DESIGN.md` §5's nine states
        //
        // `Default` is the populated list and carries no copy of its own; `Success` is absent by
        // construction, because the list has no commit. Both are recorded in the spec's state
        // matrix rather than given invented strings.

        case listEmptyNoQuery
        case listEmptyQuery
        case listBandEmpty
        case listPartialOfficialDown
        case listPartialSmitheryDown
        case listPartialGitHubLimited
        case listPartialUnrecognised
        case listError
        case listOffline

        // MARK: Detail
        //
        // Detail performs no fetch (A11), so its Empty, Loading and Error are structurally
        // unreachable and have no keys. Their absence is the point: writing plausible copy for a
        // state that cannot occur is scaffolding wearing a design's clothes.

        case detailPartialNoRepository
        case detailPartialGitHubLimited
        case detailOffline
        case detailNoLastCommit
        case detailLastCommit
        case chipSourceOfficial
        case chipSourceSmithery
        case chipSourceBoth
        case chipArchived

        // MARK: The capability plate — the five derivations of A13

        case plateStdio
        case plateRemote
        case plateCredential
        case plateCredentialSmithery
        case plateArchived
        case plateNoInstall
        case plateInvocationLabel

        // MARK: The commit — the seven states of A16–A21

        case commitReachable
        case commitNotReachable
        case commitNeverPaired
        case commitNoDescriptor
        case commitQueuedReachable
        case commitQueuedNotReachable
        case commitAlreadyDeclared

        /// The surface this key renders on.
        public var surface: Surface {
            switch self {
            case .searchPlaceholder, .bandMostUsed, .bandMostUsedNote, .bandRecentlyChanged,
                 .bandRecentlyChangedNote, .windowLabel, .windowAppliesTo, .windowDisabledInSearch,
                 .windowAnyTime, .windowNinety, .windowThirty, .windowSeven, .useCountUnit,
                 .starsUnit, .truncated:
                .controls
            case .listEmptyNoQuery, .listEmptyQuery, .listBandEmpty, .listPartialOfficialDown,
                 .listPartialSmitheryDown, .listPartialGitHubLimited, .listPartialUnrecognised,
                 .listError, .listOffline:
                .list
            case .detailPartialNoRepository, .detailPartialGitHubLimited, .detailOffline,
                 .detailNoLastCommit, .detailLastCommit, .chipSourceOfficial, .chipSourceSmithery,
                 .chipSourceBoth, .chipArchived:
                .detail
            case .plateStdio, .plateRemote, .plateCredential, .plateCredentialSmithery,
                 .plateArchived, .plateNoInstall, .plateInvocationLabel:
                .plate
            case .commitReachable, .commitNotReachable, .commitNeverPaired, .commitNoDescriptor,
                 .commitQueuedReachable, .commitQueuedNotReachable, .commitAlreadyDeclared:
                .commit
            }
        }
    }

    /// The seven commit states, which are the seven keys that must carry the narrowing (A20).
    ///
    /// Derived from `Key.surface` rather than written out a second time, so the set cannot drift
    /// from the enum it describes — a hand-maintained list would be a second source of truth about
    /// something the type system already knows.
    public static var narrowingKeys: Set<Key> {
        Set(Key.allCases.filter { $0.surface == .commit })
    }

    // MARK: - The copy

    public static func entry(_ key: Key) -> Entry {
        switch key {
        // MARK: Controls, bands and units

        case .searchPlaceholder:
            // Plural, because two indexes are searched and either can fail alone (A9). It never
            // says "skills": there is no skills index on either router, so a placeholder promising
            // one would promise a capability the product does not have.
            Entry(body: "Search the server registries")

        case .bandMostUsed:
            Entry(body: "Most used")

        case .bandMostUsedNote:
            Entry(body: """
            Sessions started on Smithery, all-time, of the results shown. The only popularity \
            figure either index publishes — the official registry publishes none, so entries it \
            alone carries are absent from this band rather than ranked at zero.
            """)

        case .bandRecentlyChanged:
            Entry(body: "Recently changed")

        case .bandRecentlyChangedNote:
            Entry(body: """
            The most recently changed of the results shown. The official registry reports when an \
            entry was last edited; Smithery reports when it was created. They are different stamps \
            under one field, so this orders them without claiming they mean the same thing.
            """)

        case .windowLabel:
            Entry(body: "Chosen window")

        case .windowAppliesTo:
            Entry(body: """
            The window filters recently changed. Most used is an all-time total and has no window.
            """)

        case .windowDisabledInSearch:
            Entry(body: "Search results aren't windowed.", isDisabled: true)

        case .windowAnyTime:
            Entry(body: "Any time")

        case .windowNinety:
            Entry(body: "90 days")

        case .windowThirty:
            Entry(body: "30 days")

        case .windowSeven:
            Entry(body: "7 days")

        case .useCountUnit:
            // "sessions on Smithery" — never "installs", never "downloads". Smithery publishes
            // sessions started, and the unit names both the quantity and who published it (A6).
            Entry(body: "{count} sessions on Smithery")

        case .starsUnit:
            Entry(body: "{count} stars on GitHub")

        case .truncated:
            Entry(body: "Showing the first {count} matches. Narrow the search to see others.")

        // MARK: The list

        case .listEmptyNoQuery:
            Entry(
                headline: "Nothing came back from either index.",
                body: "Both registries answered and neither listed anything.",
                actionLabel: "Try again"
            )

        case .listEmptyQuery:
            Entry(
                headline: "No server matches \u{201C}{query}\u{201D}.",
                body: """
                Search covers the official MCP registry and Smithery. Try a shorter word, or clear \
                the search to browse the bands.
                """,
                actionLabel: "Clear search"
            )

        case .listBandEmpty:
            // A5: one band empty while the other is populated is the common case, not an edge
            // case, and it is not the whole-list Empty state.
            Entry(
                headline: "Nothing in these results changed in the last {window} days.",
                body: "Widen the window to see more.",
                actionLabel: "Any time"
            )

        case .listPartialOfficialDown:
            Entry(
                headline: "Showing Smithery only.",
                body: "The official registry didn't answer, so anything it alone lists is missing.",
                actionLabel: "Try again"
            )

        case .listPartialSmitheryDown:
            Entry(
                headline: "Showing the official registry only.",
                body: """
                Smithery didn't answer, so anything it alone lists is missing — including the \
                session counts Most used ranks on.
                """,
                actionLabel: "Try again"
            )

        case .listPartialGitHubLimited:
            Entry(
                headline: "Repository details are incomplete.",
                body: """
                GitHub limits how often it can be asked, so stars and archive status are missing \
                for some entries. Everything else is complete.
                """
            )

        case .listPartialUnrecognised:
            // A25: a warning matching no known class renders verbatim under a generic heading
            // rather than being dropped. The wire carries free text and the classification is by
            // prefix, so this is the case that keeps a reworded warning visible.
            Entry(headline: "The search reported a problem.", body: "{warning}")

        case .listError:
            Entry(
                headline: "The registry search failed.",
                body: "{reason}. Nothing was queued and nothing changed on your Mac.",
                actionLabel: "Try again"
            )

        case .listOffline:
            // A27: `DESIGN.md` §5 asks Offline to "offer to start it". The phone cannot start a
            // process on the Mac, so it gives the instruction instead — a recorded deviation with
            // its reason, not a criterion quietly passed off as satisfied.
            Entry(
                headline: "The router isn't running on {mac}.",
                body: """
                Discover reads the registries through it, so nothing can be searched until it \
                starts. Open MCP Router on your Mac.
                """
            )

        // MARK: Detail

        case .detailPartialNoRepository:
            // A26: a fact, not a failure. GitHub was never asked, because a Smithery entry's
            // repository is its smithery.ai homepage and that is not a parseable repo URL.
            Entry(
                headline: "Smithery doesn't publish repository activity for this entry.",
                body: "There's no last-commit date or archive status to show."
            )

        case .detailPartialGitHubLimited:
            Entry(
                headline: "Repository details are missing for this entry.",
                body: """
                GitHub limits how often it can be asked, so the last-commit date and archive \
                status couldn't be fetched this time.
                """
            )

        case .detailOffline:
            Entry(
                headline: "The router isn't running on {mac}.",
                body: "You can still save this here — send it from Queue when the router is back."
            )

        case .detailNoLastCommit:
            Entry(body: "No last-commit date")

        case .detailLastCommit:
            Entry(body: "Last commit {count}")

        case .chipSourceOfficial:
            Entry(body: "Official registry")

        case .chipSourceSmithery:
            Entry(body: "Smithery")

        case .chipSourceBoth:
            Entry(body: "Both registries")

        case .chipArchived:
            Entry(body: "Archived")

        // MARK: The capability plate
        //
        // Every line here is *derived from the install descriptor*, never authored per entry, and
        // the plate is drawn above the commit rather than behind a disclosure control (A12). The
        // brief's rule: the security fact is never behind a tap the user can skip.

        case .plateStdio:
            Entry(body: "Runs a program on your Mac, with your own access")

        case .plateRemote:
            // A13: this names the host, and is a fact line rather than an amber one. For a remote
            // MCP server the decision that matters is that tool arguments leave the machine —
            // treating remote as the quiet case inverts the real risk. It is not `--attn` because
            // the user is queueing for review, not granting access, and an amber block that fires
            // on everything stops meaning anything.
            Entry(body: "Nothing runs on your Mac; requests go to {host}")

        case .plateCredential:
            Entry(body: "Needs a credential, entered on your Mac")

        case .plateCredentialSmithery:
            // A14: every Smithery-hosted install declares a required `Authorization`
            // unconditionally, so within that subset the line distinguishes nothing. Saying so is
            // the difference between a warning and noise.
            Entry(body: """
            Needs a Smithery API key, entered on your Mac. Every Smithery-hosted entry asks for \
            one, so this doesn't set this server apart from the others there.
            """)

        case .plateArchived:
            Entry(body: "The repository is archived; nobody is maintaining it")

        case .plateNoInstall:
            Entry(body: "Neither index says how this server runs")

        case .plateInvocationLabel:
            Entry(body: "What would run")

        // MARK: The commit
        //
        // Seven states, all carrying the narrowing (A20). Verb-first and no ellipsis, because it
        // commits now rather than opening a further view (A16, `DESIGN.md` §3.4, §6).

        case .commitReachable:
            Entry(
                body: "Reachable — items you send arrive now.",
                actionLabel: "Send to Mac",
                carriesNarrowing: true
            )

        case .commitNotReachable:
            // A18: live, and relabelled. This writes one item to a local queue, which succeeds
            // with the Mac asleep — so disabling it would refuse an act that works. The label
            // changes because a button reading "Send" above a note reading "saved" contradicts
            // itself. This diverges from I1's `SendCommitBar` deliberately: that is Queue's
            // *send these now* batch control and is right to disable on `.notReachable`.
            Entry(
                body: """
                Can't reach {mac} right now. This is saved here; send it from Queue when it's back.
                """,
                actionLabel: "Save for your Mac",
                carriesNarrowing: true
            )

        case .commitNeverPaired:
            Entry(
                body: "No Mac paired yet, so there's nowhere to send this.",
                actionLabel: "Send to Mac",
                isDisabled: true,
                carriesNarrowing: true
            )

        case .commitNoDescriptor:
            Entry(
                body: """
                Neither index says how this server runs, so there's nothing for your Mac to review.
                """,
                actionLabel: "Send to Mac",
                isDisabled: true,
                carriesNarrowing: true
            )

        case .commitQueuedReachable:
            // Success is an in-place state change. macOS does not toast a click and neither does
            // this (`DESIGN.md` §5, §7).
            Entry(
                body: "Waiting for review on {mac}.",
                actionLabel: "Queued for your Mac",
                isDisabled: true,
                carriesNarrowing: true
            )

        case .commitQueuedNotReachable:
            // A21: says where the item is and how it goes, never that it will go on its own. No
            // item owns flush-on-reachable, so copy promising one would promise nothing.
            Entry(
                body: "Send it from Queue when {mac} is back.",
                actionLabel: "Saved on this phone",
                isDisabled: true,
                carriesNarrowing: true
            )

        case .commitAlreadyDeclared:
            // A23: rendered as the name match it is. The router compares `displayName` against
            // locally declared server keys, which both false-positives on a shared last path
            // segment and misses on case — so the copy may not assert an identity the comparison
            // cannot establish.
            Entry(
                body: "A server called {name} is already declared on {mac}.",
                actionLabel: "Already on your Mac",
                isDisabled: true,
                carriesNarrowing: true
            )
        }
    }
}
