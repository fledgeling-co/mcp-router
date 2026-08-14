import Foundation

/// Every sentence the two boards say about a check.
///
/// One place, deliberately. The naming discipline this item exists to hold is testable only if the
/// strings live somewhere a test can read them: `CheckCopyTests` asserts that no function here
/// returns a bare verdict word, that the Evals subtitle carries its disclosure unconditionally, and
/// that the four phrases that would promise a graded test suite appear nowhere.
///
/// **The rule the copy is built around.** The unit is a *check* — something MCP Router performed and
/// can show you the input to. It is not a graded test of whether a capability does its job well. A
/// verdict therefore never appears without the statement it judges, and the aggregate is a tally of
/// segments rather than a single word: "4 passed · 1 failed · 1 unknown" is a description, where
/// "passed" alone is a claim about the whole subject that no check here supports.
public enum CheckCopy {
    // MARK: - Statements

    /// What each check asserts, phrased as the thing being judged rather than as a result.
    ///
    /// Present tense and specific: a reader who sees only this line and a verdict should know what
    /// was observed. "Its calls come back without error" says what was looked at; "healthy" does not.
    ///
    /// Split along `CheckID.subjectKind` rather than held as one eleven-armed switch. The split is
    /// the domain's, not the linter's: a server statement is about a process the router spawns and a
    /// skill statement is about a file on disk that several clients may or may not be able to read,
    /// and the two sets never mix at a call site.
    ///
    /// The two `default` arms are unreachable, and two independent things keep them so. Adding a
    /// case to `CheckID` fails to compile against `subjectKind`, whose switch has no default; and
    /// A17 asserts a non-empty statement for every case, so a case routed to a kind but forgotten
    /// here goes red rather than rendering a blank line beside a verdict.
    public static func statement(for check: CheckID) -> String {
        switch check.subjectKind {
        case .server: serverStatement(for: check)
        case .skill: skillStatement(for: check)
        }
    }

    private static func serverStatement(for check: CheckID) -> String {
        switch check {
        case .indexes: "The router can start it and read its tool surface"
        case .declaresTools: "It offers at least one tool"
        case .authorized: "Its credentials are current"
        case .surfaceApproved: "No tool description is waiting for review"
        case .operative: "It carries no placard"
        case .callsSucceed: "Its calls come back without error"
        default: ""
        }
    }

    private static func skillStatement(for check: CheckID) -> String {
        switch check {
        case .reachable: "At least one client can load it"
        case .versioned: "It carries a version a result can be stamped against"
        case .originUnchanged: "Its marketplace still resolves where the router first saw it"
        case .updateWantsNoMore: "Any newer version held asks for nothing extra"
        case .described: "Its SKILL.md declares a description an agent can route on"
        default: ""
        }
    }

    // MARK: - Reasons

    /// The reason line for a check that did not pass.
    ///
    /// Named observations, never adjectives. Each of these is composed at the call site from a value
    /// the router actually sent, which is why they take parameters rather than being constants.
    public static let neverIndexed = "The router has never started it, so its tool surface is unread."

    public static func indexFailed(_ detail: String) -> String {
        "The router could not read its tool surface — \(detail)"
    }

    public static let noToolsDeclared =
        "It indexed without error and declared no tools, so it adds nothing to a session's tool list."

    public static let toolsUnknownUntilIndexed =
        "Its tool surface has not been read, so how many tools it offers is unobserved."

    public static let credentialsMissing =
        "It supports authorization and the router holds no current credentials for it."

    public static let credentialsNotApplicable =
        "This transport carries no credentials, so there are none to be current."

    public static func surfaceHeld(count: Int, seenAt: String) -> String {
        let noun = count == 1 ? "description" : "descriptions"
        return "\(count) tool \(noun) changed and are held for review, first seen \(seenAt)."
    }

    public static func placarded(_ reason: String) -> String {
        "It carries a placard — \(reason)"
    }

    /// **The load-bearing one.** Zero calls with zero errors is arithmetically a clean record and is
    /// not a pass: a check that reports success for something nobody has ever done is the same
    /// defect as a fabricated number. It reports `unknown`, and this is what it says.
    public static let neverExercised =
        "Never exercised — the router has recorded no calls to it, so whether its calls succeed "
            + "is unobserved."

    public static func callsFailed(errors: Int, calls: Int) -> String {
        let noun = errors == 1 ? "call" : "calls"
        return "\(errors) of \(calls) recorded \(noun) came back with an error."
    }

    public static func notLoadableAnywhere(clientCount: Int) -> String {
        let noun = clientCount == 1 ? "client" : "clients"
        return "Every one of the \(clientCount) skills-capable \(noun) was read, and none has it installed."
    }

    public static func reachabilityUnknown(clients: [String]) -> String {
        let names = clients.sorted().joined(separator: ", ")
        let verb = clients.count == 1 ? "directory could not be read" : "directories could not be read"
        return "It is installed in no client the router could read, and \(names)'s skills \(verb) — "
            + "so it may be installed exactly where nobody could look."
    }

    public static let standaloneUnversioned =
        "It was placed in a client's directory by hand, so it has no version anywhere on disk and "
            + "no result about it can be stamped against one."

    /// A standalone skill has no marketplace, so an unmoved origin is not something that can be true
    /// of it. Reporting a confirmation here would assert a fact about an entity that does not exist.
    public static let standaloneNoOrigin =
        "It was placed in a client's directory by hand rather than supplied by a marketplace, so "
            + "there is no origin for it to have moved from."

    /// No newer version is offered, so the question does not arise. Most skills are in this state,
    /// and reporting a confirmation for every one of them would be a pass for a question nobody asked.
    public static let noVersionHeld =
        "No newer version of its plugin is being held, so there is nothing waiting to ask for more."

    public static func originMoved(firstSeen: String, current: String, at: String) -> String {
        "The router first saw it at \(firstSeen) and it now resolves to \(current), first observed \(at)."
    }

    public static func heldVersionWantsMore(version: String, capabilities: [String]) -> String {
        let list = capabilities.sorted().joined(separator: ", ")
        return "Version \(version) is held and asks for \(list)."
    }

    public static let noDescription =
        "Its SKILL.md declares no description, so an agent has nothing to route on when choosing it."

    public static let descriptionUnreadable =
        "Its directory could not be read, so whether it declares a description is unobserved."

    // MARK: - The Evals pane

    public static let evalsTitle = "Evals"

    /// **Permanent, and present even while loading.** It is a statement about the product rather
    /// than about the data, so a loading pane that omitted it would be the one moment a user forms
    /// their first impression of what this pane claims. Returned unconditionally.
    public static let evalsSubtitle =
        "The checks MCP Router runs itself, stamped to the version each was run against. "
            + "No model-graded evaluation exists in this product."

    public static let evalsFooter =
        "A check is something MCP Router performed and can show you the input to. It is not a graded "
            + "test of whether a capability does its job well. Skills are never executed by the "
            + "router, so nothing here reports how one behaved when an agent used it."

    /// **"Re-check", not "Run checks".** For a server the call is `POST /servers/:name/reindex`,
    /// which really does re-perform the handshake; for a skill it is `GET /skills`, which re-reads
    /// directories. *Re-check* is true of both — it names re-running the checks over a fresh reading
    /// and claims no execution. A pane whose entire defence is verb discipline cannot afford a
    /// primary button whose verb is false for half its subjects.
    public static let runAllLabel = "Re-check all…"
    public static let runChecksLabel = "Re-check"

    public static let evalsEmptyTitle = "Nothing to check yet"
    public static let evalsEmptyDetail =
        "MCP Router checks the servers and skills it can see. Declare a server and its checks appear here."
    public static let evalsEmptyAction = "Add a server…"

    public static func evalsEmptyInFilter(_ filterTitle: String) -> StateMessageCopy {
        StateMessageCopy(
            title: "Nothing is \(filterTitle.lowercased())",
            detail: "Every subject the router can see falls outside this filter. Clearing it shows them all.",
            action: "Show all"
        )
    }

    // MARK: - Stamps

    public static func checkedAgainst(stamp: String, ago: String) -> String {
        "\(stamp) · \(ago) ago"
    }

    /// A history row gathered against a version that is no longer the live one.
    ///
    /// Rendered at `--t3`, never `--t4`: `DESIGN.md` §2 binds `--t4` to "disabled controls only —
    /// never live text", and a history row is live text. The row is **kept** — invalidation is not
    /// deletion, and evidence gathered against an older version is still evidence of what was
    /// observed then.
    ///
    /// This form is for a **skill**, whose stamp is a readable version like `0.4.1`.
    public static func invalidatedLabel(stored: String, live: String) -> String {
        "gathered against \(stored) · now \(live)"
    }

    /// The same, for a **server**, whose stamp is 16 characters of sha256 over its declaration.
    ///
    /// Two hex prefixes in one sentence is 45 characters of noise that does not say the thing the
    /// reader needs. What a moved server stamp actually means is precise and short, so it is said:
    /// the entry's command line or URL was edited after this evidence was gathered.
    public static let invalidatedServerLabel =
        "gathered before this entry was edited"

    /// Said where a stamp would be, for a subject nothing can be stamped against.
    public static let unstampable = "No version to stamp against"

    public static let unstampableDetail =
        "These checks ran and are shown, and nothing is stored: there is no version here for a later "
            + "reading to be measured against, so a stored result could never be known to be out of date."

    public static let neverChecked = "Not checked"

    // MARK: - Tally

    /// The word one verdict is shown as.
    ///
    /// **Observation vocabulary, not grading vocabulary, and this is the item's single most
    /// load-bearing copy decision.** `passed` / `failed` are the words of a test suite: use them and a
    /// re-tabulation of data the router already served reads as a grade, however carefully the
    /// subtitle is worded. `confirmed` / `not met` / `not observed` are the words of an observation,
    /// which is what these actually are.
    ///
    /// The filter segments reuse these same words, so nothing on screen carries two names for one
    /// state — an earlier draft had a segment reading "Unchecked" beside a tally reading "unknown",
    /// one letter apart and meaning different things (`DESIGN.md` §6: one name per state).
    public static func tallyNoun(for verdict: CheckVerdict) -> String {
        switch verdict {
        case .passed: "confirmed"
        case .failed: "not met"
        case .unknown: "not observed"
        case .notApplicable: "not applicable"
        }
    }

    /// The four words, for a test that asserts none of them is a grading verb.
    public static var verdictVocabulary: [String] {
        CheckVerdict.allCases.map(tallyNoun(for:))
    }

    // MARK: - Disabled reasons

    public static let skillRemoveDisabled =
        "The control API is read-only for skills: removing one means writing files the client "
            + "applications hold open, which wants preconditions and an undo this surface does not have."

    public static let runChecksNeedsSelection = "Select a subject to run its checks."

    public static let removeNeedsServer =
        "Only a server can be removed from here — the control API is read-only for skills."

    public static let historyEmpty = "No stored runs yet."

    public static let historyUnreadable =
        "The stored history could not be read, so nothing earlier is shown. The checks above are current."

    /// A small carrier so a state's three strings travel together rather than as three parameters.
    public struct StateMessageCopy: Sendable, Equatable {
        public let title: String
        public let detail: String
        public let action: String?

        public init(title: String, detail: String, action: String? = nil) {
            self.title = title
            self.detail = detail
            self.action = action
        }
    }
}
