import Foundation

/// Every user-facing string on the Inbox pane and the Mac's pairing sheet.
///
/// Held as data, in the Kit, for the reason `SkillCopy` and `PairingCopy` are: a string built inside
/// a `body` cannot be asserted without a host, so the mock-parity and wording checks would have
/// nothing to read. Everything here is sentence case (`DESIGN.md` §6), states what happened and what
/// to do, sits next to the thing it is about, and does not emote.
public enum InboxCopy {
    // MARK: - The pane

    public static let title = "Inbox"

    /// The subtitle, assembled from state rather than written as a constant.
    ///
    /// The prototype hardcodes "paired with Luke's iPhone". A build with no pairing must not claim
    /// one, so the device name is an optional and its absence has its own sentence rather than a
    /// default string standing in for a device nobody observed.
    public static func subtitle(waiting: Int, device: String?) -> String {
        let left = waiting > 0 ? "\(waiting) waiting" : "Nothing waiting"
        guard let device else { return "\(left) · no phone paired" }
        return waiting > 0 ? "\(waiting) waiting from \(device)" : "\(left) · paired with \(device)"
    }

    public static let pairingButton = "Pairing…"
    public static let reviewAction = "Review…"
    public static let declineAction = "Decline"

    /// What a row says about when it arrived and who sent it.
    public static func provenance(queued: String, device: String) -> String {
        "queued \(queued) · \(device)"
    }

    // MARK: - Empty

    public static let emptyTitle = "Nothing waiting"

    /// The product's own argument, and the reason this pane exists at all. `DESIGN.md` §5 wants an
    /// illustration, one sentence and one action rather than a bare "No items"; the action here is
    /// pairing, because an unpaired Mac has nothing that could ever arrive.
    public static let emptyDetail = """
    Things you send from your phone land here. The phone can queue and nothing else — a lost or \
    unlocked phone still cannot install code on this Mac.
    """

    // MARK: - Loading, partial, error

    public static let loadingDetail = "Reading what is waiting…"

    /// The Partial state. Said about the item rather than about the pane, because one unreadable
    /// entry does not make the rest of the list untrue.
    public static let partialTitle = "This entry could not be read"
    public static let partialDetail = """
    The registry has no entry with this id, so what it would run cannot be shown — and nothing can \
    be accepted without that.
    """

    /// The queue itself could not be read — this Mac's own storage, not the router.
    public static let unreadableTitle = "The inbox could not be read"

    public static func readFailure(detail: String) -> String {
        "The queue could not be read: \(detail)."
    }

    public static let registryFailureDetail = """
    The queue is intact, but the registry that describes these items could not be reached, so none \
    of them can be reviewed yet.
    """

    // MARK: - The offline case

    /// The router being down does not empty the inbox — it stops anything being installed from it.
    /// Two different facts, and collapsing them would either hide the queue or claim it is gone.
    public static let routerOfflineTitle = "The router is not running"
    public static let routerOfflineDetail = """
    What is waiting is still here. Nothing can be installed until the router is running again.
    """

    // MARK: - Review

    /// The tense is the guarantee the whole queue exists to make.
    public static let provenanceNote = """
    Sent from your iPhone. It has been sitting in the inbox and has not run.
    """

    public static let acceptAction = "Install on this Mac"

    /// The entry resolved but describes no way to install it — so there is nothing to send, and
    /// nothing the router could have refused. Said about the entry rather than about the router.
    public static let notInstallableDetail = """
    This entry does not say how it would be installed, so there is nothing to run. Nothing was sent \
    to the router.
    """

    // MARK: - Dispositions, and their undo

    /// Declining is fully reversible, so this line is paired with an Undo control.
    public static func declined(_ name: String) -> String {
        "Declined \(name)."
    }

    /// Accepting is **not** reversible from here, and the sentence says where it is reversible
    /// instead of offering a control that would not do it.
    ///
    /// The earlier wording was "Installed \(name)." beside an Undo button, and the Phase D critic
    /// was right that this is the worst kind of dishonest affordance: pressing it returned the row
    /// to the queue and left the server installed, so the one word on the control described neither
    /// half of what happened. Removing a server is `DESIGN.md` §8's own undoable operation on the
    /// Servers board, with its own confirmation and its own consequences for stored secrets;
    /// reaching across to perform it from here would be a second implementation of a destructive
    /// action. So the report stays and the control goes.
    public static func accepted(_ name: String) -> String {
        "Installed \(name). Removing it is done on Servers."
    }

    public static let undoAction = "Undo"

    /// A route arrived for an item that is no longer waiting.
    ///
    /// Reachable only in the microseconds between a disposition and its banner being withdrawn, and
    /// it renders in the report slot `declined` and `accepted` already use rather than in a banner
    /// of its own — a new surface for a state measured in microseconds would be furniture. It does
    /// not blame and does not ask anything: the item was handled, which is the outcome the user
    /// wanted anyway.
    public static let alreadyHandled = "That item was already handled."

    // MARK: - The menu-bar band

    public enum Band {
        /// The row that stands for everything past the popover's cap.
        ///
        /// The band's header line already states the true total, so this states the remainder and
        /// names where the rest of them are. `DESIGN.md` §6: verb-first, and it names the
        /// destination rather than saying "more".
        public static func overflow(_ remaining: Int) -> String {
            "\(remaining) more waiting · open Inbox"
        }

        /// What a row whose entry could not be read says in place of a capability line.
        ///
        /// Shorter than the pane's `partialDetail` because the popover has no room for the
        /// paragraph, and it says the same thing: nothing about what it runs can be shown, so
        /// nothing can be accepted.
        public static let partialCapability = "This entry could not be read"
    }

    // MARK: - The arrival notification

    public enum Arrival {
        /// Names the sender. The device name is the **one** phone-supplied string that reaches a
        /// notification, and it is a label rather than a claim about what anything does — everything
        /// this app says about capability comes from the registry entry the Mac resolved itself.
        public static func subtitle(device: String) -> String {
            "Queued from \(device)"
        }

        /// An item whose registry entry could not be read. The banner says so rather than saying
        /// nothing, because a banner with no body reads as a thing with no consequences.
        public static let partialBody = """
        This entry could not be read, so what it would run cannot be shown.
        """

        public static func manyTitle(_ count: Int) -> String {
            "\(count) items are waiting"
        }

        /// The tense is the same guarantee the review sheet's provenance note makes.
        public static let manyBody = "Nothing has run. Open the inbox to review them."

        public static let reviewAction = "Review"
        public static let declineAction = "Decline"

        /// What being denied notifications costs, said once, adjacent to the thing, at the moment it
        /// becomes relevant — the paired state of the pairing sheet.
        ///
        /// Nothing nags and nothing retries. It names what still works, because the menu-bar dot is
        /// a real fallback rather than a consolation.
        public static let notificationsOff = """
        Notifications are off, so nothing will announce an arrival. The menu-bar item still takes \
        its dot. Turn them on in System Settings › Notifications.
        """
    }

    // MARK: - Pairing

    public enum Pairing {
        public static let title = "Pair iPhone"

        /// Names the path on the phone. Matched to what I1 actually shipped rather than to the
        /// mock's wording, because a lede that names a screen the phone does not have sends the
        /// reader looking for it.
        public static let lede = "On your phone: Conduit → Settings → Pair Mac, then scan this."

        /// `--attn`, because it is asking for a human decision rather than reporting a failure.
        public static let warning = """
        Treat this code like a password. Anyone who scans it can put items in your inbox until it \
        expires.
        """

        public static let typeInstead = "Can't scan? Type a code"
        public static let doneAction = "Done"

        public static func expiresIn(_ remaining: TimeInterval) -> String {
            let whole = Int(remaining.rounded(.down))
            return "expires in \(whole / 60):\(String(format: "%02d", whole % 60))"
        }

        public static let expiredTitle = "That code has expired"
        public static let expiredDetail = "A new one is on screen. Scan or type that one instead."

        /// The state a Release build reaches, and the whole reason `PairingEndpoint` is an input.
        ///
        /// Names what is missing and what will provide it. It does not apologise and does not blame
        /// the reader, and it offers no action, because there is nothing this app can do about it
        /// today — an action control here would be a button with nothing behind it.
        public static let noEndpointTitle = "Pairing is not available in this build"
        public static let noEndpointDetail = """
        Pairing needs the Mac to be reachable from your phone, and this build ships no way to \
        listen for one. Nothing is wrong with your phone or your network.
        """

        public static let preparing = "Preparing a code…"

        public static func paired(with name: String) -> String {
            "Paired with \(name)."
        }
    }

    // MARK: - Refusals

    /// One sentence per refusal, in the Mac's own voice.
    ///
    /// Exhaustive over `PairingRefusal` rather than defaulted, so a refusal added later fails to
    /// compile until someone decides what the Mac says about it — the same discipline
    /// `FixturePairingService.refusalOutcome` uses on the phone side.
    public static func refusal(_ refusal: PairingRefusal) -> String {
        switch refusal {
        case .notRecognised:
            "That code is not the one on screen. Check the eight characters and try again."
        case .expired:
            "That code had expired. A new one is on screen."
        case .alreadyUsed:
            "That code has already paired a device. Each one works once."
        case let .unsupportedVersion(found):
            "That phone speaks pairing version \(found), which this Mac does not. Update the phone app."
        case .declined:
            "You dismissed that request. Nothing was paired."
        }
    }
}
