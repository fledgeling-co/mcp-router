import Foundation

/// What a notification is allowed to do, as a closed set.
///
/// **There is no install case, and its absence is the enforcement.** A `UNNotificationAction` press
/// is a human at the Mac acting, so an install action would not cross `DESIGN.md` §9's stated
/// boundary — it is rejected on a narrower ground: a notification is the least deliberate press
/// available on a Mac. It appears over whatever the user was doing, unrequested, positioned where
/// muscle memory dismisses things. Installing from it moves the
/// one-press-from-remote-request-to-running-code failure off the phone and into Notification Center,
/// which is the queue's own failure mode wearing different clothes.
///
/// The asymmetry is `DESIGN.md` §9's *"friction scales to blast radius"* read literally. Declining
/// costs a resend and is reversible in one press; installing declares executable code on this laptop
/// from a request that arrived over a network. So decline can be pressed anywhere and install can be
/// pressed in one place — the review sheet, where what it runs is on screen.
///
/// A closed enum rather than a string switch so a case added later has to be decided rather than
/// falling through a `default` into whatever the last branch did.
public enum InboxNotificationAction: String, Sendable, Equatable, CaseIterable {
    /// Route to the item and put the review in front of the user. Opens no install.
    case review
    /// Decline in place. Calls the router nothing, and is reversible through the single-slot undo.
    case decline

    /// The action taken when the body of the notification is pressed rather than one of its buttons.
    public static let `default` = InboxNotificationAction.review

    /// Resolve a `UNNotificationResponse`'s action identifier.
    ///
    /// Here rather than in the delegate for the reason every decision in this app is in the Kit:
    /// `app/MCPRouter` is not a SwiftPM target, so a mapping written beside the delegate is a
    /// mapping `swift test` cannot reach.
    ///
    /// - Parameters:
    ///   - identifier: the response's `actionIdentifier`.
    ///   - isDefaultAction: whether the system reported its default-action identifier.
    ///   - isDismissAction: whether the system reported its dismiss identifier.
    /// - Returns: `nil` for a dismissal — closing a banner is not a decision about the item, and
    ///   treating it as one would make ignoring a notification mean something.
    public static func resolve(
        identifier: String,
        isDefaultAction: Bool,
        isDismissAction: Bool
    ) -> InboxNotificationAction? {
        if isDismissAction { return nil }
        if isDefaultAction { return .default }
        return InboxNotificationAction(rawValue: identifier)
    }
}

/// One banner, built as a value so what it says is assertable without a notification centre.
public struct InboxAnnouncement: Sendable, Equatable {
    /// The notification's own identifier. For a single item this is its envelope id, so the delivered
    /// banner can be withdrawn the moment that item is dispositioned.
    public let id: String
    public let title: String
    public let subtitle: String
    public let body: String
    /// The actions this banner offers. **Never contains an install.**
    public let actions: [InboxNotificationAction]
    /// The item ids this banner covers, so a disposition knows what to withdraw.
    public let itemIDs: [String]

    public init(
        id: String,
        title: String,
        subtitle: String,
        body: String,
        actions: [InboxNotificationAction],
        itemIDs: [String]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.actions = actions
        self.itemIDs = itemIDs
    }

    /// The identifier a multi-item banner uses. One at a time: a second delta replaces the first
    /// rather than stacking, because two "N items are waiting" banners disagree about N.
    public static let manyIdentifier = "inbox.many"

    /// Build the announcement for one delta.
    ///
    /// **One banner per delta, never one per item.** Three arriving together is one banner, for the
    /// reason the status item carries no count: an instrument that fires constantly is one the eye
    /// learns to skip, and then it skips the one that mattered.
    ///
    /// - Returns: `nil` when nothing arrived, so "no arrivals" cannot be announced as an event.
    public static func make(arrivals: [InboxItem], device: String?) -> InboxAnnouncement? {
        guard let first = arrivals.first else { return nil }
        let sender = device ?? first.envelope.deviceName

        guard arrivals.count == 1 else {
            return InboxAnnouncement(
                id: manyIdentifier,
                title: InboxCopy.Arrival.manyTitle(arrivals.count),
                subtitle: InboxCopy.Arrival.subtitle(device: sender),
                body: InboxCopy.Arrival.manyBody,
                // No decline: there is no single item for it to act on, and "decline all" is a bulk
                // destructive action nobody asked for.
                actions: [.review],
                itemIDs: arrivals.map(\.id)
            )
        }

        return InboxAnnouncement(
            id: first.id,
            // What the Mac resolved, or the phone's name only where the entry could not be read —
            // `InboxItem.title`'s existing rule, not a second one.
            title: first.title,
            subtitle: InboxCopy.Arrival.subtitle(device: first.envelope.deviceName),
            // The material fact, derived by this Mac from the registry. A banner that says only
            // "something arrived" makes the reader open the app to learn whether it matters, which
            // is the friction this item exists to remove.
            body: first.resolved.map { RegistryCapability.statement(for: $0).headline }
                ?? InboxCopy.Arrival.partialBody,
            actions: [.review, .decline],
            itemIDs: [first.id]
        )
    }
}

/// The seam between the inbox and whatever announces an arrival.
///
/// A protocol for the same reason `InboxService` is one, plus a harder one: constructing
/// `UNUserNotificationCenter.current()` in a process with no bundle identifier **traps**, and every
/// `swift test` run is such a process. A concrete dependency here would take the suite down rather
/// than fail a test.
public protocol ArrivalNotifier: Sendable {
    /// Ask once. Implementations are expected to be idempotent — macOS prompts a user once and
    /// answers from its stored decision afterwards.
    func requestAuthorization() async -> Bool
    func announce(_ announcement: InboxAnnouncement) async
    /// Withdraw delivered banners covering these item ids. Called the moment an item is
    /// dispositioned by any surface, which is what closes the race between a banner and the window.
    func withdraw(itemIDs: [String]) async
}

/// The notifier of a build that cannot announce anything.
///
/// **Not a fixture**, in the sense `NoTransportInboxService` is not one: it is the correct and
/// complete implementation for a process with no notification centre to talk to, which is every test
/// run and any host without a bundle identifier.
public struct SilentArrivalNotifier: ArrivalNotifier {
    public init() {}
    public func requestAuthorization() async -> Bool {
        false
    }

    public func announce(_: InboxAnnouncement) async {}
    public func withdraw(itemIDs _: [String]) async {}
}

/// Which item ids have already been announced, and the rule about what counts as an arrival.
///
/// Its own type rather than two fields on the board model, because both rules below are the kind
/// that get re-derived wrongly by a later edit and neither is obvious from a call site.
public struct ArrivalTracker: Sendable, Equatable {
    private var announced: Set<String> = []
    private var seeded = false

    public init() {}

    /// Whether any snapshot has been seen yet.
    public var hasSeeded: Bool { seeded }

    public var announcedIDs: Set<String> { announced }

    /// Feed one snapshot in and get back what genuinely arrived.
    ///
    /// **The first snapshot of a session announces nothing and seeds its ids.** A queue that was
    /// already waiting when you logged in is not an arrival, and five banners at login is the
    /// behaviour that teaches people to turn notifications off — after which the feature is worse
    /// than absent, because it is absent and believed present.
    ///
    /// **The announced set only ever grows, and that is deliberate.** An id is minted once by the
    /// phone, so the only way a seen id can reappear is if the item came back — which is exactly
    /// what undoing a decline does. Re-announcing a row the user just put back is the app arguing
    /// with them.
    public mutating func arrivals(in items: [InboxItem]) -> [InboxItem] {
        guard seeded else {
            seeded = true
            announced.formUnion(items.map(\.id))
            return []
        }
        let new = items.filter { !announced.contains($0.id) }
        announced.formUnion(new.map(\.id))
        return new
    }
}
