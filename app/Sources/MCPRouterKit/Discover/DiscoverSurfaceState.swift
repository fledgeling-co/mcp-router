import Foundation

/// The states Discover's two surfaces can be in, as values a test can construct and enumerate.
///
/// `DESIGN.md` §5 requires nine states per data surface, and the reliable failure in AI-generated
/// UI is shipping only the populated one. Driving each surface from an enum rather than from a
/// scatter of optionals is what makes that checkable: a test enumerates the cases, renders each,
/// and a tenth state added without copy fails to compile rather than shipping blank.
///
/// **Where a state is absent, its absence is deliberate and commented.** An omission that reads as
/// an oversight is worse than a stub, so each one names the criterion it follows from.

// MARK: - Why a search failed

/// The closed set of renderings for `DiscoverCopy.Token.reason`.
///
/// A28 requires `{reason}` to be a closed enum rather than a passthrough of the router's error
/// body. Two reasons, and both matter. The router's message is free text written for a developer,
/// so it can be a stack frame or a URL; and it is attacker-influenced in the sense that it can
/// carry whatever a third-party index returned, which is not something to interpolate into a
/// sentence the user is asked to trust.
public enum DiscoverFailureReason: String, Sendable, Equatable, CaseIterable {
    case unauthorized
    case malformedResponse
    case routerRefused
    case transport

    /// The one place a `ControlAPIError` becomes a user-facing reason.
    ///
    /// `routerNotRunning` is deliberately **not** a case: it is its own surface state (A27,
    /// `SWIFT_PRACTICES.md` §3), and folding it in here would render "the router isn't running" as
    /// one more error string inside an error banner.
    public static func from(_ error: ControlAPIError) -> DiscoverFailureReason? {
        switch error {
        case .routerNotRunning: nil
        case .unauthorized: .unauthorized
        case .malformedResponse: .malformedResponse
        case .server: .routerRefused
        case .transport: .transport
        }
    }

    public var text: String {
        switch self {
        case .unauthorized: "This phone isn't authorised to search through your Mac"
        case .malformedResponse: "Your Mac sent a response this version doesn't understand"
        case .routerRefused: "Your Mac couldn't complete the search"
        case .transport: "Couldn't reach your Mac"
        }
    }
}

// MARK: - Warnings

/// The three classes of warning `/registry/search` can report, plus everything else.
///
/// **Classification is by prefix match on free text, and that is fragile — stated here rather than
/// discovered later.** The wire carries `warnings: string[]` with no code, and the four producing
/// strings live in `src/registry.ts`: `official registry unreachable: …` (:301),
/// `Smithery unreachable: …` (:306), and two GitHub rate-limit strings (:251-255). A reword on the
/// router side silently reclassifies a warning to `.unrecognised`, which is why that case carries
/// the text verbatim and renders it rather than dropping it — a degraded surface that loses the
/// explanation for its own degradation is worse than one that shows an unpolished sentence.
///
/// Because `searchRegistries` catches per index and returns partial results rather than throwing,
/// **warnings are the realistic degraded surface for this feature** — the 502 path is nearly
/// unreachable, and the GitHub rate limit is the likeliest of the three by a wide margin (60
/// requests an hour unauthenticated, against a budget of 10 per search).
public enum WarningClass: Sendable, Equatable, Hashable {
    case officialDown
    case smitheryDown
    case githubLimited
    case unrecognised(String)

    private static let officialPrefix = "official registry unreachable"
    private static let smitheryPrefix = "Smithery unreachable"
    private static let githubPrefixes = ["GitHub rate limit", "GitHub allows"]

    public static func classify(_ warning: String) -> WarningClass {
        if warning.hasPrefix(officialPrefix) { return .officialDown }
        if warning.hasPrefix(smitheryPrefix) { return .smitheryDown }
        if githubPrefixes.contains(where: warning.hasPrefix) { return .githubLimited }
        return .unrecognised(warning)
    }

    public static func classify(_ warnings: [String]) -> [WarningClass] {
        warnings.map(classify)
    }

    public var copyKey: DiscoverCopy.Key {
        switch self {
        case .officialDown: .listPartialOfficialDown
        case .smitheryDown: .listPartialSmitheryDown
        case .githubLimited: .listPartialGitHubLimited
        case .unrecognised: .listPartialUnrecognised
        }
    }
}

// MARK: - The list

/// The list's states.
///
/// **`success` is absent by construction**: the list has no commit, so it has nothing to succeed
/// at. Recorded rather than invented — a `case success` here would need copy, and any copy written
/// for it would describe something the surface cannot do.
///
/// `disabled` and `overflow` are likewise absent as *surface* states: both are conditions of
/// individual controls and rows rather than of the list. The window control's disabled state is
/// `DiscoverCopy.Key.windowDisabledInSearch` and is rendered inline (A10); overflow is a row-level
/// truncation rule (A29). `DESIGN.md` §5 asks for nine states per data surface, and these two are
/// present as behaviours on the elements that have them rather than as whole-pane states, which is
/// what the design document means by "every control additionally carries default / hover /
/// focus-visible / active / disabled".
public enum DiscoverListState: Sendable, Equatable {
    /// Two bands, populated.
    case populated
    /// The search is in flight. Renders skeleton rows at the real row's height, never a spinner.
    case loading
    /// Both indexes answered and neither listed anything, with no query narrowing it.
    case emptyNoQuery
    /// A query matched nothing.
    case emptyQuery(String)
    /// Results arrived, and something about the search was degraded.
    case partial([WarningClass])
    /// The search failed outright.
    case failed(DiscoverFailureReason)
    /// The router is not running on the paired Mac. Its own state, never a generic error (A27).
    case offline
}

// MARK: - Detail

/// Detail's states.
///
/// **Three of the nine are structurally unreachable here, and are absent rather than stubbed.**
/// Detail performs no fetch of its own (A11) — every field it renders arrived inside the search
/// row:
///
/// - **Empty** — Detail opens only from a row that exists, so there is no empty Detail.
/// - **Loading** — nothing is being fetched, so nothing can be skeletoned. A skeleton here would
///   animate a wait that is not happening.
/// - **Error** — a row cannot exist without a successful search, so Detail has no error of its
///   own. Its errors are the list's, surfaced on the list.
///
/// The remaining states are here. `success` is the commit's in-place change and lives on
/// `CommitState`; `disabled` is the commit with no install descriptor, likewise.
public enum DetailState: Sendable, Equatable {
    /// Artwork, name, description, chips, the capability plate, the commit.
    case populated
    /// A Smithery-hosted entry, whose repository activity was never fetched because its repository
    /// URL is a smithery.ai homepage rather than a parseable GitHub repo (A26). A **fact**, not a
    /// failure: Partial is reserved for the case where GitHub was asked and refused.
    case noRepositoryData
    /// GitHub was asked and refused, so this entry's repository fields are missing this time.
    case githubLimited
    /// The router is not running on the paired Mac. Detail still allows a local save (A18).
    case offline
}

// MARK: - The commit

/// The seven states of the one commit this feature offers.
///
/// Sending to the Mac is the **only** commit available (A16). There is no install action, nothing
/// that could be read as installing, and no second channel — the phone queues capabilities for
/// review on the Mac, which is deliberately narrower than remote install (`DESIGN.md` §9).
public enum CommitState: Sendable, Equatable, CaseIterable {
    /// The Mac answered. "Send to Mac".
    case reachable
    /// Paired and nothing answered. **Live, and relabelled** "Save for your Mac" (A18).
    case notReachable
    /// No Mac is paired, so there is nowhere to send. Disabled.
    case neverPaired
    /// Neither index says how this server runs, so there is nothing to queue. Disabled.
    case noDescriptor
    /// Already queued, and the Mac is reachable.
    case queuedReachable
    /// Already queued, and the Mac is not.
    case queuedNotReachable
    /// A server with this display name is already declared on the Mac (A23).
    case alreadyDeclared

    public var copyKey: DiscoverCopy.Key {
        switch self {
        case .reachable: .commitReachable
        case .notReachable: .commitNotReachable
        case .neverPaired: .commitNeverPaired
        case .noDescriptor: .commitNoDescriptor
        case .queuedReachable: .commitQueuedReachable
        case .queuedNotReachable: .commitQueuedNotReachable
        case .alreadyDeclared: .commitAlreadyDeclared
        }
    }

    /// Whether tapping does anything. Read from the copy, so a state whose button is dimmed and
    /// whose note says why cannot disagree with the predicate that dims it.
    public var isActionable: Bool {
        !DiscoverCopy.entry(copyKey).isDisabled
    }

    /// The one place the commit's state is decided.
    ///
    /// **This deliberately does not read `ConnectionState.canSend`**, and A19 exists because the
    /// obvious implementation does. `canSend` answers "may a surface commit *right now*", which
    /// `SendCommitBar` binds `.disabled()` to and is right to — that control sends a batch over the
    /// network. This control writes one item to a local queue, which succeeds with the Mac asleep,
    /// so it reads `canQueue`. One property must not answer two questions, or this ships I1's
    /// behaviour while looking correct.
    public static func resolve(
        connection: ConnectionState,
        hasInstallDescriptor: Bool,
        isAlreadyQueued: Bool,
        isAlreadyDeclared: Bool
    ) -> CommitState {
        // Order is the precedence. Never-paired and no-descriptor come first because they are the
        // only two states that disable the commit (A17), and neither is recoverable by tapping.
        guard connection.canQueue else { return .neverPaired }
        guard hasInstallDescriptor else { return .noDescriptor }
        if isAlreadyDeclared { return .alreadyDeclared }
        if isAlreadyQueued {
            return connection == .reachable ? .queuedReachable : .queuedNotReachable
        }
        return connection == .reachable ? .reachable : .notReachable
    }
}
