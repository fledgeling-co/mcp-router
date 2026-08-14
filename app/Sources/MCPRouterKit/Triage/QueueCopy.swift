import Foundation

/// Every string the Queue surface renders.
///
/// **Nothing here promises that anything sends, collects or arrives**, and that is the constraint
/// the whole manifest is written under. There is no transport: M6 shipped the Mac's inbox and the
/// wire envelope and deferred the transport itself, and the phone ships a fixture pairing service.
/// So the phone can observe no Mac-side outcome, and I2's merged A21 already forbids copy that
/// promises an automatic send.
///
/// An earlier draft of this surface read *"Waiting for {mac} to collect them"* and *"it stays here
/// until your Mac has it"*. Both assert a pending automatic transfer that nothing performs. The
/// strings below state the local fact and the manual next step instead.
public enum QueueCopy {
    // MARK: - Substitution

    public enum Token: String, Sendable, CaseIterable {
        /// The paired Mac's name; `"your Mac"` when none is paired.
        case mac
        /// A registry entry's display name.
        case name
        /// When this phone queued the item, already formatted.
        case when
        /// The host a remote server's requests go to — the row carries the same capability line the
        /// Triage row does.
        case host

        public var placeholder: String { "{\(rawValue)}" }
    }

    public struct Entry: Sendable, Equatable {
        public let headline: String?
        public let body: String
        public let actionLabel: String?
        public let carriesNarrowing: Bool

        public init(
            headline: String? = nil,
            body: String,
            actionLabel: String? = nil,
            carriesNarrowing: Bool = false
        ) {
            self.headline = headline
            self.body = body
            self.actionLabel = actionLabel
            self.carriesNarrowing = carriesNarrowing
        }

        public var tokens: Set<Token> {
            let text = (headline ?? "") + body + (actionLabel ?? "")
            return Set(Token.allCases.filter { text.contains($0.placeholder) })
        }

        public func resolved(_ values: [Token: String]) -> Entry {
            func sub(_ s: String?) -> String? {
                guard var out = s else { return nil }
                for (token, value) in values {
                    out = out.replacingOccurrences(of: token.placeholder, with: value)
                }
                return out
            }
            return Entry(
                headline: sub(headline),
                body: sub(body) ?? body,
                actionLabel: sub(actionLabel),
                carriesNarrowing: carriesNarrowing
            )
        }
    }

    // MARK: - Keys

    /// The chrome. **There is no section header key**: the list is one section, so a header would
    /// partition nothing, and the only word it could carry is "Waiting" — the badge vocabulary this
    /// surface removes, reintroduced at section scope.
    public enum ChromeKey: String, Sendable, CaseIterable {
        case subtitle
        case footer
        case stamp
        case remove
        case undoRemoved
        case undo
    }

    /// The states. **There is no Offline key and no Partial key**, and both absences are decisions
    /// rather than omissions: the queue is one local file read whole, so there is no half of it to
    /// arrive and nothing remote to be offline from. Recorded here so a later reader does not add
    /// plausible copy for a state that cannot occur.
    public enum StateKey: String, Sendable, CaseIterable {
        case empty
        case neverPaired
        /// A17, and the most important state on this surface. The file exists and will not decode.
        /// Distinct from `empty` in every respect, because a decode path whose failure mode is
        /// emptiness is the defect this repo's own TypeScript router already shipped once.
        case unreadable
        case writeRefused
        /// The app could not resolve a storage directory at all, so neither the queue nor the
        /// dismissal set has anywhere to live. Its own state because the honest `try?` alternative —
        /// falling back to in-memory stores — silently reproduces the defect the file-backed wiring
        /// exists to fix: everything the user queues vanishes at the next launch, with nothing said.
        case storageUnavailable
    }

    public enum Key: Sendable, Equatable, Hashable {
        case chrome(ChromeKey)
        case state(StateKey)

        public static var allCases: [Key] {
            ChromeKey.allCases.map(Key.chrome) + StateKey.allCases.map(Key.state)
        }
    }

    public static func entry(_ key: Key) -> Entry {
        switch key {
        case let .chrome(k): chrome(k)
        case let .state(k): state(k)
        }
    }

    // MARK: - Chrome

    private static func chrome(_ key: ChromeKey) -> Entry {
        switch key {
        case .subtitle:
            // States where the items are and what the user does next. No verb implying transfer.
            Entry(body: "On this phone. Open MCP Router on {mac} to review them.")
        case .footer:
            Entry(
                body: """
                    Your Mac decides. This list is the record of what you have queued, and it stays on \
                    this phone.
                """
            )
        case .stamp:
            Entry(body: "Queued {when}")
        case .remove:
            Entry(body: "Remove {name} from the queue")
        case .undoRemoved:
            Entry(body: "{name} removed from the queue")
        case .undo:
            Entry(body: "Undo")
        }
    }

    // MARK: - States

    private static func state(_ key: StateKey) -> Entry {
        switch key {
        case .empty:
            Entry(
                headline: "Nothing waiting",
                body: """
                    Things you send from Triage or Discover collect here until you are back at your Mac.
                """,
                actionLabel: "Go to Triage"
            )
        case .neverPaired:
            // Nothing is discarded. The state names what is missing without deleting the user's
            // work, and it does not promise the items will travel on their own once a Mac exists.
            Entry(
                headline: "No Mac is paired.",
                body: "These are kept here. Pair a Mac and you can review them there.",
                actionLabel: "Pair a Mac",
                carriesNarrowing: true
            )
        case .unreadable:
            Entry(
                headline: "The queue could not be read.",
                body: """
                    Something is saved on this phone and this version cannot decode it, so it is not being \
                    shown. Nothing has been deleted and nothing has been sent.
                """,
                actionLabel: "Try again"
            )
        case .writeRefused:
            Entry(
                headline: "That item was not saved.",
                body: "This phone refused the write, so it is not in the queue. Try again from Triage."
            )
        case .storageUnavailable:
            Entry(
                headline: "This phone has nowhere to save.",
                body: """
                    MCP Router could not open its own storage, so nothing can be queued or turned down. \
                    Reinstalling the app usually clears this.
                """,
                carriesNarrowing: true
            )
        }
    }

    public static var narrowingKeys: Set<Key> {
        Set(Key.allCases.filter { entry($0).carriesNarrowing })
    }
}
