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

    // MARK: - Dispositions, and their undo

    public static func declined(_ name: String) -> String {
        "Declined \(name)."
    }

    public static func accepted(_ name: String) -> String {
        "Installed \(name)."
    }

    public static let undoAction = "Undo"

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
