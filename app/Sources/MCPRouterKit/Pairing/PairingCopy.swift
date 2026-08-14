import Foundation

// swiftlint:disable cyclomatic_complexity function_body_length type_body_length file_length
//
// The four rules above are *metric* rules, and this file is a data table rather than logic.
//
// They are disabled here, and nowhere else in this repo, because the alternative is worse in a
// specific way. `entry(_:)` is one exhaustive `switch` over `Key`, and that exhaustiveness is the
// point: a tenth state added to a surface fails to **compile** until someone writes its copy,
// rather than shipping a blank pane or a string assembled at a call site where the mock-parity
// check cannot see it. A switch over a 39-case enum has a cyclomatic complexity of 39 by
// construction, so complexity ≤ 10 and compile-time exhaustiveness cannot both hold. Splitting the
// switch into per-surface functions would satisfy the metric by returning `Entry?` and chaining
// with `??`, which is exactly how the compile-time guarantee is lost — a missing key would become
// a runtime nil instead of a build failure.
//
// There is no branching here to be complex: every case is a `return`, the cases carry no
// conditions, and nothing in the function can fail. The rules that catch real defects — the
// force-unwrap, line-length and naming rules — remain on.
//
// Scope note: this exemption covers this file only. It is not a licence to silence a metric rule
// on a file that genuinely computes something.

/// Every user-facing string in the phone shell and the pairing flow, keyed by **surface × state**.
///
/// Why a manifest at all, and why keyed this way. `ControlCopyTests` already pins the control
/// client's copy by asserting the literals and then finding them in the design mock, and that
/// catches two of the three drifts: a reword in code, and a reword in the design that never reached
/// the code. It cannot catch the third — copy that exists, matches the mock, and is rendered on the
/// **wrong surface or in the wrong state**. A flat list has nowhere to record where a string
/// belongs, so "the narrowing appears on the surfaces that need it" stays an intention.
///
/// Keying by state makes placement assertable, and `Key` is an enum rather than a string so the
/// `switch` below must stay exhaustive: a tenth state added to a surface fails to **compile** until
/// someone writes its copy, rather than shipping a blank pane.
public enum PairingCopy {
    /// The narrowing, once. `DESIGN.md` §9 and the product's standing constraint: the phone queues
    /// and never installs, and every surface must reflect that rather than implying otherwise.
    ///
    /// One constant rather than one sentence per surface, because three surfaces say this and three
    /// paraphrases of a permission boundary is how a user ends up believing the loosest one.
    public static let neverInstalls = """
    This app queues items for review on your Mac. It cannot install, update or remove anything — \
    that happens only at your Mac.
    """

    /// A rendered piece of copy. `headline` is nil where the state is inline beside a control
    /// rather than a whole pane.
    public struct Entry: Sendable, Equatable {
        public let headline: String?
        public let body: String
        public let actionLabel: String?
        public let secondaryActionLabel: String?
        /// Whether this surface also carries `neverInstalls`.
        public let carriesNarrowing: Bool

        public init(
            headline: String? = nil,
            body: String,
            actionLabel: String? = nil,
            secondaryActionLabel: String? = nil,
            carriesNarrowing: Bool = false
        ) {
            self.headline = headline
            self.body = body
            self.actionLabel = actionLabel
            self.secondaryActionLabel = secondaryActionLabel
            self.carriesNarrowing = carriesNarrowing
        }

        /// Substitute the paired Mac's name into any `{mac}` placeholder.
        ///
        /// A placeholder rather than string interpolation at the call site: the copy that names a
        /// Mac is exactly the copy that must not be assembled ad hoc, or two surfaces end up
        /// saying "Can't reach Luke's MacBook Pro" and "Luke's MacBook Pro is unreachable".
        public func resolved(macName: String?) -> Entry {
            let name = macName ?? "your Mac"
            return Entry(
                headline: headline?.replacingOccurrences(of: "{mac}", with: name),
                body: body.replacingOccurrences(of: "{mac}", with: name),
                actionLabel: actionLabel,
                secondaryActionLabel: secondaryActionLabel,
                carriesNarrowing: carriesNarrowing
            )
        }
    }

    /// Which surface a piece of copy belongs to. Used for grouping in the completeness check.
    public enum Surface: String, Sendable, CaseIterable {
        case shell
        case settings
        case scan
        case camera
        case typedEntry
        case verifying
        case outcome
        case unpair
        case sending
    }

    /// Every surface-and-state that renders copy in this feature.
    public enum Key: String, Sendable, CaseIterable {
        /// The four tabs whose content another item owns.
        case discoverAwaiting, triageAwaiting, queueAwaiting, libraryAwaiting

        // Settings, the feature's data surface — the nine states of `DESIGN.md` §5.
        case settingsNeverPaired
        case settingsReachable
        case settingsLoading
        case settingsPartial
        case settingsUnreadable
        case settingsJustPaired
        case settingsMacUnreachable

        // Pairing.
        case scanReady, scanCaution, scanNoCode
        case cameraNotDetermined, cameraDenied, cameraRestricted
        case typedEntryReady, typedEntryNotRecognised, typedEntryExpired
        case verifyingScanned, verifyingTyped
        case pairedSuccess

        // The outcomes that get a whole pane.
        case outcomeAlreadyUsed
        case outcomeVersionMismatch
        case outcomeUnreachable
        case outcomeRefused
        case outcomeNotAPairingCode
        case outcomeMalformedPayload

        case unpairConfirm
        case sendingBlocked

        /// The connection banner's three states.
        ///
        /// They are manifest entries rather than sentences built in the view, and the distinction
        /// is not academic: the banner previously assembled its own reachable line by interpolating
        /// the Mac's name, which drifted from the approved "Reachable — items you send arrive now."
        /// without any of the three copy checks being able to see it. A string written at the call
        /// site is a string the mock-parity check cannot reach.
        case bannerReachable, bannerNotReachable, bannerNeverPaired

        // Chrome and inline strings. They are here for the same reason the pane copy is: a string
        // written at the call site is a string the mock-parity check cannot see, and a section
        // label or a placeholder is exactly the kind of copy that drifts unnoticed.
        case settingsSectionPairedMac, settingsSectionAbout, settingsUnpairAction
        case scanInstruction, typedEntryHelper
        case cameraPlaceholderIdle, cameraPlaceholderUnavailable
        case pairedCapabilities

        public var surface: Surface {
            switch self {
            case .discoverAwaiting, .triageAwaiting, .queueAwaiting, .libraryAwaiting: .shell
            case .settingsNeverPaired, .settingsReachable, .settingsLoading, .settingsPartial,
                 .settingsUnreadable, .settingsJustPaired, .settingsMacUnreachable: .settings
            case .scanReady, .scanCaution, .scanNoCode: .scan
            case .cameraNotDetermined, .cameraDenied, .cameraRestricted: .camera
            case .typedEntryReady, .typedEntryNotRecognised, .typedEntryExpired: .typedEntry
            case .verifyingScanned, .verifyingTyped: .verifying
            case .pairedSuccess, .outcomeAlreadyUsed, .outcomeVersionMismatch, .outcomeUnreachable,
                 .outcomeRefused, .outcomeNotAPairingCode, .outcomeMalformedPayload: .outcome
            case .unpairConfirm: .unpair
            case .sendingBlocked: .sending
            case .bannerReachable, .bannerNotReachable, .bannerNeverPaired: .sending
            case .settingsSectionPairedMac, .settingsSectionAbout, .settingsUnpairAction: .settings
            case .scanInstruction, .cameraPlaceholderIdle, .cameraPlaceholderUnavailable: .scan
            case .typedEntryHelper: .typedEntry
            case .pairedCapabilities: .outcome
            }
        }
    }

    /// The copy. Exhaustive by construction.
    public static func entry(_ key: Key) -> Entry {
        switch key {
        // MARK: The shell's awaiting states

        case .discoverAwaiting:
            Entry(
                headline: "Nothing to browse yet",
                body: "Browsing arrives in a later update. Pairing and your library are here now."
            )
        case .triageAwaiting:
            Entry(
                headline: "Nothing to triage yet",
                body: "Capabilities you have not decided on will collect here once browsing arrives."
            )
        case .queueAwaiting:
            Entry(
                headline: "You have not sent anything yet",
                body: "Items you send to your Mac appear here with what happened to them at the Mac."
            )
        case .libraryAwaiting:
            // Library carries the narrowing too: it is the surface most likely to be mistaken for
            // an install surface, since it lists what *is* installed.
            Entry(
                headline: "Your library lives on your Mac",
                body: "What is installed there will be listed here, read-only.",
                carriesNarrowing: true
            )

        // MARK: Settings
        case .settingsNeverPaired:
            Entry(
                headline: "No Mac paired yet",
                body: "Pair with the Mac running MCP Router to send it capabilities to review.",
                actionLabel: "Pair Mac",
                carriesNarrowing: true
            )
        case .settingsReachable:
            Entry(body: "Reachable — items you send arrive now.")
        case .settingsLoading:
            Entry(body: "Checking whether your Mac is reachable.")
        case .settingsPartial:
            Entry(
                body: """
                Reachable, but it hasn't reported since this app opened, so "last seen" is unknown \
                rather than guessed.
                """
            )
        case .settingsUnreadable:
            // Describes what was observed and names no cause. An earlier draft blamed a backup
            // restore — but a restore to a different device leaves this Keychain item **absent**,
            // which is `settingsNeverPaired`, not this. Naming an unobserved cause is the same
            // fabrication as naming an unobserved number.
            Entry(
                headline: "Can't read this phone's pairing",
                body: """
                The stored pairing couldn't be opened, so this phone can't reach your Mac. \
                Pair with your Mac again to fix it.
                """,
                actionLabel: "Pair Mac"
            )
        case .settingsJustPaired:
            Entry(body: "Paired. Items you send arrive now.")
        case .settingsMacUnreachable:
            Entry(
                body: """
                Can't reach it right now. It may be asleep, on another network, or MCP Router may \
                not be running. Anything you send waits here until it's back.
                """
            )

        // MARK: Scanning
        case .scanReady:
            Entry(
                headline: "Pair Mac",
                body: "Point at the code on your Mac",
                actionLabel: "Can't scan? Type the code"
            )
        case .scanCaution:
            // Stated *before* the camera is useful, not after. A pairing code lets a remote party
            // put executable code on a laptop.
            Entry(
                headline: "Before you scan",
                body: """
                Treat that code like a password. Anyone who scans it can queue items on your Mac \
                until it expires.
                """
            )
        case .scanNoCode:
            Entry(
                body: """
                No code on your Mac? Check MCP Router is running there and that both devices are \
                on the same network.
                """
            )

        // MARK: Camera permission
        case .cameraNotDetermined:
            Entry(
                headline: "Why the camera",
                body: """
                It reads the pairing code on your Mac's screen and nothing else. No image is stored \
                or sent anywhere.
                """,
                actionLabel: "Allow camera access",
                secondaryActionLabel: "Enter the code instead"
            )
        case .cameraDenied:
            Entry(
                headline: "Camera access is off",
                body: """
                MCP Router can't open the camera, so it can't scan the code. Turn it on in iOS \
                Settings, or type the code instead.
                """,
                actionLabel: "Open iOS Settings",
                secondaryActionLabel: "Enter the code instead"
            )
        case .cameraRestricted:
            // Restricted is not denied. The user may be unable to change it — a device policy or
            // Screen Time set it — so "Open iOS Settings" would be a dead end, and the typed path
            // is the primary recovery rather than the fallback.
            Entry(
                headline: "Camera access isn't available",
                body: """
                Something on this device prevents camera use, and it may not be yours to change. \
                You can still pair by typing the code your Mac is showing.
                """,
                actionLabel: "Enter the code instead"
            )

        // MARK: Typed entry
        case .typedEntryReady:
            Entry(
                headline: "Enter the code",
                body: "Type the eight characters your Mac is showing.",
                actionLabel: "Pair Mac"
            )
        case .typedEntryNotRecognised:
            Entry(
                body: """
                That code isn't one your Mac is showing. Check it against your Mac and type it \
                again — the code changes when it expires.
                """,
                actionLabel: "Pair Mac"
            )
        case .typedEntryExpired:
            Entry(
                body: """
                That code has expired. Your Mac is already showing a new one — type that, or scan it.
                """,
                actionLabel: "Scan instead"
            )

        // MARK: Verifying
        case .verifyingScanned:
            // The one surface where a countdown is honest: the scanned payload carried the expiry.
            Entry(
                headline: "Checking with {mac}",
                body: "Confirming the code and exchanging keys."
            )
        case .verifyingTyped:
            // The same moment without a fabricated number.
            Entry(
                headline: "Checking the code",
                body: "Confirming it with your Mac."
            )

        // MARK: Outcomes
        case .pairedSuccess:
            Entry(
                headline: "Paired with {mac}",
                body: "You can send capabilities to it for review.",
                actionLabel: "Done",
                carriesNarrowing: true
            )
        case .outcomeAlreadyUsed:
            Entry(
                headline: "That code has already been used",
                body: """
                Each code pairs one device once. Ask your Mac for a new one — MCP Router → \
                Settings → Pair iPhone.
                """,
                actionLabel: "Scan a new code"
            )
        case .outcomeVersionMismatch:
            Entry(
                headline: "{mac} is running an older MCP Router",
                body: """
                That version pairs differently, so this app can't complete it. Update MCP Router \
                on your Mac, then pair again.
                """,
                actionLabel: "Try again"
            )
        case .outcomeUnreachable:
            Entry(
                headline: "Can't reach {mac}",
                body: """
                The code is fine, but nothing answered. Your Mac may be asleep, on another \
                network, or MCP Router may not be running there.
                """,
                actionLabel: "Try again"
            )
        case .outcomeRefused:
            // A refusal is a decision someone made at the Mac, not an error — so retry is not the
            // primary action, and the copy does not alarm.
            Entry(
                headline: "{mac} declined the pairing",
                body: """
                Someone dismissed the request at the Mac. Start pairing again there if that \
                wasn't intended.
                """,
                actionLabel: "Back to Settings"
            )
        case .outcomeNotAPairingCode:
            Entry(
                body: """
                That isn't an MCP Router pairing code. Scan the code your Mac is showing under \
                Settings → Pair iPhone.
                """,
                actionLabel: "Scan again"
            )
        case .outcomeMalformedPayload:
            Entry(
                body: "That code couldn't be read. Ask your Mac for a new one and scan it again.",
                actionLabel: "Scan again"
            )

        // MARK: Unpair
        case .unpairConfirm:
            // A named consequence, not "Are you sure": what stops, and what survives.
            Entry(
                headline: "Unpair {mac}?",
                body: """
                This phone will stop being able to queue items. Anything already waiting at the Mac \
                stays there. You can pair again with a new code.
                """,
                actionLabel: "Unpair",
                secondaryActionLabel: "Cancel"
            )

        // MARK: A surface that offers to send, and cannot
        case .sendingBlocked:
            Entry(
                headline: "Can't reach {mac}.",
                body: "They'll go on their own as soon as your Mac is reachable."
            )

        // MARK: The connection banner
        // Reachable names no Mac. The banner sits on a surface that has already said which Mac is
        // paired, and repeating the name here is the sentence the spec's state matrix rejected.
        case .bannerReachable:
            Entry(body: "Reachable — items you send arrive now.")
        case .bannerNotReachable:
            Entry(body: "Can't reach {mac}. Anything you send waits here until it's back.")
        case .bannerNeverPaired:
            Entry(body: "No Mac paired. Pair one to send anything.")

        // MARK: Chrome and inline strings
        case .settingsSectionPairedMac:
            Entry(body: "Paired Mac")
        case .settingsSectionAbout:
            Entry(body: "About")
        case .settingsUnpairAction:
            Entry(body: "Unpair this Mac")
        case .scanInstruction:
            Entry(
                body: """
                On your Mac, open MCP Router → Settings → Pair iPhone, then point this camera at \
                the code it shows.
                """
            )
        case .typedEntryHelper:
            Entry(body: "The code expires. Your Mac is showing how long is left.")
        case .cameraPlaceholderIdle:
            Entry(body: "Camera not started")
        case .cameraPlaceholderUnavailable:
            Entry(body: "Camera unavailable")
        case .pairedCapabilities:
            Entry(
                headline: "What this phone can do",
                body: """
                Queue items for review, and read your library. It cannot install, update or \
                remove anything.
                """
            )
        }
    }

    /// Every key with its copy, for the completeness and mock-parity checks.
    public static var all: [(Key, Entry)] {
        Key.allCases.map { ($0, entry($0)) }
    }

    /// The keys whose surfaces also render `neverInstalls`.
    ///
    /// Named here rather than discovered by reading the views, so the placement claim in the spec
    /// has something to assert against that is not the thing under test.
    public static var narrowingKeys: Set<Key> {
        Set(Key.allCases.filter { entry($0).carriesNarrowing })
    }

    /// The copy for a pairing outcome, so the outcome and its rendering cannot drift apart.
    public static func key(for outcome: PairingOutcome) -> Key? {
        switch outcome {
        case .paired: .pairedSuccess
        case .notRecognised: .typedEntryNotRecognised
        case .expired: .typedEntryExpired
        case .alreadyUsed: .outcomeAlreadyUsed
        case .versionMismatch: .outcomeVersionMismatch
        case .unreachable: .outcomeUnreachable
        case .refused: .outcomeRefused
        case .notAPairingCode: .outcomeNotAPairingCode
        case .malformedPayload: .outcomeMalformedPayload
        }
    }
}

// swiftlint:enable cyclomatic_complexity function_body_length type_body_length
