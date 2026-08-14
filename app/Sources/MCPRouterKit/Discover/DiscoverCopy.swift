import Foundation

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
///
/// ## Why the key is nested rather than flat
///
/// The guarantee this manifest exists to provide is a **compile-time** one: a tenth state added to
/// a surface fails to build until someone writes its copy, rather than shipping a blank pane. That
/// guarantee comes from `switch` exhaustiveness, and a flat 47-case key makes it come from *one*
/// switch — one function with a cyclomatic complexity of 47 and a 200-line body.
///
/// `PairingCopy` answers that by disabling the metric rules for its whole file and re-enabling them
/// on the last line, which satisfies the linter without changing the shape. This file does not,
/// because the shape is what was wrong. `Key` is instead a sum over one small key type **per UI
/// element** — the band header, the window control, the units, the list, detail, the plate, the
/// commit — so `entry(_:)` is a seven-arm dispatch and each element's copy is a total switch over
/// its own type. Exhaustiveness is not weakened anywhere: adding a case to `ListKey` still fails to
/// compile until `ListKey.entry` handles it.
///
/// The seam is the one the file already had. `Surface` existed before this split, every key already
/// carried its element's name as a prefix, and `DiscoverBand.titleKey`, `RecencyWindow.copyKey` and
/// `CommitState.copyKey` were already returning keys drawn from exactly these groups. What changed
/// is that the grouping is now structural rather than a naming convention plus a hand-written
/// 47-case `surface` switch that had to be kept in step with it by hand.
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

    /// Every surface-and-state that renders copy in this feature, as a sum over one key type per
    /// UI element. The element types themselves are in `DiscoverCopyKeys.swift`.
    public enum Key: Hashable, Sendable, CaseIterable {
        case band(BandKey)
        case window(WindowKey)
        case unit(UnitKey)
        case list(ListKey)
        case detail(DetailKey)
        case plate(PlateKey)
        case commit(CommitKey)

        /// Hand-written because `CaseIterable` is not synthesised for an enum with associated
        /// values. `DiscoverCopyTests` pins the total and asserts every case of every element type
        /// is reachable from here, so a group dropped from this list fails a test rather than
        /// quietly shrinking the set every completeness check runs over.
        public static var allCases: [Key] {
            BandKey.allCases.map(Key.band)
                + WindowKey.allCases.map(Key.window)
                + UnitKey.allCases.map(Key.unit)
                + ListKey.allCases.map(Key.list)
                + DetailKey.allCases.map(Key.detail)
                + PlateKey.allCases.map(Key.plate)
                + CommitKey.allCases.map(Key.commit)
        }

        /// The surface this key renders on.
        ///
        /// Structural now rather than a hand-maintained switch over every key: the band header, the
        /// window control and the units are all chrome around the list, and the remaining four
        /// element types map one-to-one onto the surfaces they name.
        public var surface: Surface {
            switch self {
            case .band, .window, .unit: .controls
            case .list: .list
            case .detail: .detail
            case .plate: .plate
            case .commit: .commit
            }
        }

        /// A stable identifier for this key, for test failure messages and nothing else. Not a wire
        /// format and not persisted — no copy key is ever written to disk or sent anywhere.
        public var name: String {
            switch self {
            case let .band(key): "band.\(key.rawValue)"
            case let .window(key): "window.\(key.rawValue)"
            case let .unit(key): "unit.\(key.rawValue)"
            case let .list(key): "list.\(key.rawValue)"
            case let .detail(key): "detail.\(key.rawValue)"
            case let .plate(key): "plate.\(key.rawValue)"
            case let .commit(key): "commit.\(key.rawValue)"
            }
        }
    }

    /// The seven commit states, which are the seven keys that must carry the narrowing (A20).
    ///
    /// Derived from `CommitKey` rather than written out a second time, so the set cannot drift from
    /// the enum it describes — a hand-maintained list would be a second source of truth about
    /// something the type system already knows.
    public static var narrowingKeys: Set<Key> {
        Set(CommitKey.allCases.map(Key.commit))
    }

    // MARK: - The copy

    /// The one entry point every surface reads its strings through.
    ///
    /// Seven arms, each delegating to a switch that is total over one element's key type. The
    /// compile-time guarantee lives in those seven switches, unchanged: a case added to any element
    /// type fails to build until its copy is written.
    public static func entry(_ key: Key) -> Entry {
        switch key {
        case let .band(key): key.entry
        case let .window(key): key.entry
        case let .unit(key): key.entry
        case let .list(key): key.entry
        case let .detail(key): key.entry
        case let .plate(key): key.entry
        case let .commit(key): key.entry
        }
    }
}
