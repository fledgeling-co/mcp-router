import Foundation

/// What an analyst finding is, as a value.
///
/// **There is no analyst, and this is the shape one would fill.** `PRD.md` §6.2–§6.3 specifies the
/// session analyst and `plan-M20.md` §8 puts it out of scope: this item builds the *delivery* — the
/// category, its three actions and the wording — so that the mock's own notification is not left
/// unbuilt indefinitely behind a subsystem nobody has started. `spec-M20.md` §2 records that
/// decision and what it beat.
///
/// The consequence is stated rather than left to be discovered: **nothing in either app target
/// constructs one of these.** No banner of this family can fire in a shipped build, because there is
/// no producer — and that is why the routes below may name a board focus that does not exist yet
/// without any surface lying to anybody. The day the analyst ships, it is the producer that arrives,
/// and `InboxBoardModel` gaining a card to focus is that item's work.
public struct AnalystFinding: Sendable, Equatable, Identifiable {
    /// The finding's own id, which is what its banner is identified by and therefore what a
    /// dismissal withdraws.
    public let id: String

    /// The registry entry the finding recommends.
    ///
    /// An entry id rather than a command line or a name the analyst composed, for the reason the
    /// inbox envelope carries one: **the recommendation names *which* entry it means and the Mac
    /// reads what that entry does.** A sentence describing capability that did not come from a
    /// resolved entry is the phone-describes-itself failure `InboxItem` was shaped to prevent, one
    /// subsystem over.
    public let entryID: String

    /// The name the banner shows for what it recommends.
    public let subject: String

    /// The one sentence carrying what was noticed. The brief's own shape: *"One sentence carrying
    /// the finding and its evidence count."*
    public let sentence: String

    /// How many observations stand behind it.
    ///
    /// Rendered as its own line rather than folded into `sentence`, so a finding cannot be delivered
    /// with the count missing from the wording — and so nothing has to parse a number back out of
    /// prose to check the two agree.
    public let evidenceCount: Int

    public init(id: String, entryID: String, subject: String, sentence: String, evidenceCount: Int) {
        self.id = id
        self.entryID = entryID
        self.subject = subject
        self.sentence = sentence
        self.evidenceCount = evidenceCount
    }
}

/// What a finding's notification is allowed to do, as a closed set.
///
/// **A second set beside `InboxNotificationAction` rather than a widening of it**, and
/// `InboxArrival.swift` is left byte-identical so that its own enforcement goes on meaning exactly
/// what it meant. `spec-M20.md` §2 states the reason as a product fact: two different things
/// arriving, two different sets of actions. The engineering half is `DEF-004`'s lesson — the
/// no-install guarantee read only half of where a notification's buttons are stated — and one set
/// carrying five cases would have made every clause about either family a clause about both.
///
/// **No case installs, and `install` is not a counter-example.** `plan-M20.md` §3.3 settles the
/// label: `Install…` carries an ellipsis, and `DESIGN.md` §3.4's grammar makes that a promise of a
/// further view rather than of a commit — the app already trains it on `Add server…`,
/// `Pair iPhone…` and `Settings…`. `PRD.md` §6.4's literal `[Install Now]` is the label that would
/// lie here, and it is deliberately not taken. What the case routes to is the board where the entry
/// and its install control are on screen, which is the same boundary
/// `InboxNotificationAction.review` holds: **the press that declares code on this Mac is made with
/// the capability statement in front of it.**
public enum FindingNotificationAction: String, Sendable, Equatable, CaseIterable {
    /// Open the recommended entry where it can be read and installed. Installs nothing itself.
    case install
    /// Open the finding's evidence — the same board, different focus.
    case details
    /// Dismiss the finding in place. Opens nothing and calls the router nothing.
    case dismiss

    /// The action taken when the body of the banner is pressed rather than one of its buttons.
    ///
    /// `details` rather than `install`, and the asymmetry with `InboxNotificationAction.default` is
    /// deliberate. There, the default press lands on a review of something the *user's own phone*
    /// queued. Here it lands on something *the app suggested unprompted*, so the default press opens
    /// the reasoning rather than the thing being recommended.
    public static let `default` = FindingNotificationAction.details

    /// Resolve a `UNNotificationResponse`'s action identifier.
    ///
    /// - Returns: `nil` for a *system* dismissal. Closing a banner by swiping it away is not a
    ///   decision about the finding, and treating it as one would make ignoring a notification mean
    ///   something. The `dismiss` **case** is the explicit button the mock draws (`:1762`), which is
    ///   a different event from the system's own dismiss identifier.
    public static func resolve(
        identifier: String,
        isDefaultAction: Bool,
        isDismissAction: Bool
    ) -> FindingNotificationAction? {
        if isDismissAction { return nil }
        if isDefaultAction { return .default }
        return FindingNotificationAction(rawValue: identifier)
    }
}

/// Where a finding press lands, as a value.
///
/// The same extraction `InboxNotificationRoute` records the reason for: a mapping written inside an
/// `NSObject` that can only be installed on a real notification centre is a mapping no clause
/// reaches, so *no path from outside the window installs anything* drove the board's methods and
/// never the mapping that chooses them.
public enum FindingNotificationRoute: Sendable, Equatable {
    /// Open the board carrying the recommendation, with the recommended entry as the subject.
    case reviewCapability(findingID: String)
    /// Open the same board at the finding's evidence.
    case explainFinding(findingID: String)
    /// Dismiss in place: no window, no activation, and nothing sent anywhere.
    case dismiss(findingID: String)
    /// A press on a banner that names several findings, which names no single one to act on.
    case openInbox

    /// Whether this route declares anything on this Mac.
    ///
    /// **Every arm is `false`, and the exhaustive switch is the enforcement.** A route added later
    /// cannot compile without being classified here, and `InboxAnnouncementTests` walks every case
    /// of both families against this — so the guarantee is a thing the compiler and a clause both
    /// hold rather than a sentence asking nobody to add an install.
    public var installs: Bool {
        switch self {
        case .reviewCapability, .explainFinding, .dismiss, .openInbox: false
        }
    }

    /// Resolve a press into what it does.
    ///
    /// - Parameters:
    ///   - action: what was pressed, already resolved from the response.
    ///   - identifier: the request's identifier — a finding id, or
    ///     ``FindingAnnouncement/manyIdentifier``.
    public static func route(
        _ action: FindingNotificationAction,
        identifier: String
    ) -> FindingNotificationRoute {
        // A banner naming several findings names no single one, so every press on it lands on the
        // board. Its category registers neither `install` nor a single subject for the same reason —
        // this is the second half of that rule, kept because a banner delivered under an older
        // build's category can still arrive with an `install` identifier on it.
        guard identifier != FindingAnnouncement.manyIdentifier else { return .openInbox }
        switch action {
        case .install: return .reviewCapability(findingID: identifier)
        case .details: return .explainFinding(findingID: identifier)
        case .dismiss: return .dismiss(findingID: identifier)
        }
    }
}

/// Which registered category a finding banner is posted under, and therefore which buttons macOS
/// actually draws on it.
///
/// `InboxNotificationCategory`'s shape and its hard-won reason: **the buttons come from the
/// `UNNotificationCategory`, not from the announcement's `actions`**, so one category serving every
/// banner puts buttons on a banner whose own value never offered them — and an assertion over the
/// value stays green against it.
public enum FindingNotificationCategory: String, Sendable, Equatable, CaseIterable {
    /// One finding: all three buttons, because there is a single entry for `Install…` to open.
    case single = "finding.analyst"
    /// Two or more: `Details` and `Dismiss`. **No `Install…`**, because there is no single entry for
    /// it to open — the same rule that keeps `Decline` off the many-item arrival banner, applied to
    /// the action whose blast radius is larger.
    case many = "finding.analyst.many"

    /// The buttons this category registers, in the order macOS draws them.
    ///
    /// **The only statement of a category's buttons.** The notifier builds its
    /// `UNNotificationCategory` from this list rather than restating it.
    public var actions: [FindingNotificationAction] {
        switch self {
        case .single: [.install, .details, .dismiss]
        case .many: [.details, .dismiss]
        }
    }

    /// The category whose registered buttons are exactly this action set.
    ///
    /// - Returns: `nil` for an action set no category draws — the honest answer rather than a nearest
    ///   match, for the reason `InboxNotificationCategory.drawing` gives.
    public static func drawing(_ actions: [FindingNotificationAction]) -> FindingNotificationCategory? {
        allCases.first { $0.actions == actions }
    }
}

/// One finding banner, built as a value so what it says is assertable without a notification centre.
public struct FindingAnnouncement: Sendable, Equatable {
    /// The banner's own identifier — the finding's id, so a delivered banner can be withdrawn the
    /// moment that finding is dismissed.
    public let id: String
    public let title: String
    public let subtitle: String
    public let body: String
    /// The actions this banner offers. **Never installs.**
    public let actions: [FindingNotificationAction]
    /// The finding ids this banner covers, so a dismissal knows what to withdraw.
    public let findingIDs: [String]

    public init(
        id: String,
        title: String,
        subtitle: String,
        body: String,
        actions: [FindingNotificationAction],
        findingIDs: [String]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.actions = actions
        self.findingIDs = findingIDs
    }

    /// The identifier a multi-finding banner uses. One at a time: a second batch replaces the first
    /// rather than stacking, because two "N things worth looking at" banners disagree about N.
    public static let manyIdentifier = "finding.many"

    /// The category this banner must be posted under, so the buttons macOS draws are the buttons
    /// ``actions`` names.
    public var category: FindingNotificationCategory? {
        FindingNotificationCategory.drawing(actions)
    }

    /// Build the announcement for one batch of findings.
    ///
    /// **One banner per batch, never one per finding** — the status item's own rule: an instrument
    /// that fires constantly is one the eye learns to skip, and then it skips the one that mattered.
    ///
    /// - Returns: `nil` for an empty batch, so "nothing was noticed" cannot be announced as an event.
    public static func make(findings: [AnalystFinding]) -> FindingAnnouncement? {
        guard let first = findings.first else { return nil }

        guard findings.count == 1 else {
            return FindingAnnouncement(
                id: manyIdentifier,
                title: FindingCopy.manyTitle(findings.count),
                subtitle: FindingCopy.evidence(findings.reduce(0) { $0 + $1.evidenceCount }),
                body: FindingCopy.manyBody,
                // No `Install…`: there is no single entry for it to open.
                actions: [.details, .dismiss],
                findingIDs: findings.map(\.id)
            )
        }

        return FindingAnnouncement(
            id: first.id,
            title: first.subject,
            subtitle: FindingCopy.evidence(first.evidenceCount),
            body: first.sentence,
            actions: [.install, .details, .dismiss],
            findingIDs: [first.id]
        )
    }
}

/// Every user-facing string on the finding notification.
///
/// Its own type rather than a nested enum on `InboxCopy`, because a finding is not an inbox arrival
/// and the two families are kept apart everywhere else in this item. Held as data, in the Kit, for
/// `InboxCopy`'s reason: a string built inside a `body` is one no clause can read.
public enum FindingCopy {
    /// The three button titles.
    ///
    /// `Install…` carries the ellipsis and the other two do not, which is `DESIGN.md` §3.4's grammar
    /// applied literally: this one opens a further view and those two do what they say where they
    /// stand. `PRD.md` §6.4's `[Install Now]` is deliberately not taken — it promises a commit, and a
    /// commit here would either be a lie or would break the no-install-from-a-notification rule.
    public static func action(_ action: FindingNotificationAction) -> String {
        switch action {
        case .install: "Install\u{2026}"
        case .details: "Details"
        case .dismiss: "Dismiss"
        }
    }

    /// The evidence line. A count of observations, and the plural is spelled rather than suffixed.
    ///
    /// It says *on this Mac* because that is the whole provenance claim of the feature the mock makes
    /// in its own words: *"Excerpts were read on this Mac and passed to a CLI you are signed into.
    /// Nothing was uploaded."*
    public static func evidence(_ count: Int) -> String {
        "\(count) \(count == 1 ? "observation" : "observations") on this Mac"
    }

    public static func manyTitle(_ count: Int) -> String {
        "\(count) things worth a look"
    }

    /// The tense is the same guarantee the inbox's own banners make: nothing has happened yet.
    public static let manyBody = "Nothing has been installed. Open the inbox to read them."
}
