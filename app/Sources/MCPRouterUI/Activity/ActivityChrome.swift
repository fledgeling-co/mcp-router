#if os(macOS)
    import Foundation
    import MCPRouterKit
    import SwiftUI

    /// How a row enters this list, held as data so §7's rule is checkable rather than asserted.
    ///
    /// **A `ForEach` row with no `.transition(_:)` is not "no animation".** SwiftUI applies its
    /// default insertion transition, which is `.opacity` — so an inserted row fades in from nothing,
    /// which is precisely what §7 and B35 forbid, and it happens without any opacity appearing in
    /// the source. That is why this is a named value with a test rather than a comment claiming the
    /// list does not fade: the previous version of `ActivityBoard` carried exactly such a comment
    /// directly above the row that was fading.
    public enum ActivityMotion {
        /// A row arriving on the live feed. **Transform only**: it slides down from the top edge,
        /// which is where a newest-first log puts it, and its opacity is never touched.
        ///
        /// Reduce Motion removes the movement and keeps the row — `.identity` means the row is
        /// simply there on the next frame, which is the setting's own rule: remove the effect, never
        /// the information.
        public static func rowInsertion(reduceMotion: Bool) -> AnyTransition {
            reduceMotion ? .identity : .move(edge: .top)
        }
    }

    /// What the Activity board is allowed to draw an exclusive indicator colour in, and why.
    ///
    /// The same shape `ShellChrome` uses, for the same reason: "no indicator colour is used
    /// decoratively" is not checkable, because *decoratively* is supplied by whoever is defending the
    /// code. A closed list with a documented justification per entry is checkable in both directions
    /// — every listed use must match `DESIGN.md`'s own wording for its token, and every token drawn
    /// in a file of this board must appear on the list.
    ///
    /// `--live` is absent, and that is the whole of D4: it means "a child process is running", and a
    /// call that has finished is not a running process. A green dot on every successful row would
    /// spend the one token that makes a green dot mean something.
    public enum ActivityChrome {
        public static let indicatorUses: [IndicatorUse] = [
            IndicatorUse(
                element: "the row's mark, when the call failed",
                token: .fail,
                justification: "failed"
            ),
            IndicatorUse(
                element: "the inspector's outcome and error fields, when the call failed",
                token: .fail,
                justification: "failed"
            ),
            IndicatorUse(
                element: "the error state's icon",
                token: .fail,
                justification: "failed"
            ),
            IndicatorUse(
                element: "the feed banner's icon, and the offline and unauthorised icons",
                token: .attention,
                justification: "wants a human decision"
            ),
            IndicatorUse(
                element: "the selected row's server name",
                token: .accent,
                justification: "selection"
            ),
            IndicatorUse(
                element: "the Clear filters button",
                token: .accent,
                justification: "the one primary action"
            )
        ]

        public static var indicatorTokensUsed: Set<ColorToken> {
            Set(indicatorUses.map(\.token))
        }

        /// Every token this board is permitted to draw at all, indicator or otherwise.
        ///
        /// B42's allowlist. Asserting "every token resolves in both appearances" would re-test
        /// `ColorToken`, which F2 already covers; the board-specific claim is *which* tokens it
        /// reaches for, and this is that list.
        public static let tokensUsed: Set<ColorToken> = [
            .panel, .raised, .raised2, .line, .lineStrong, .f1, .f2, .f3,
            .t1, .t2, .t3, .t4,
            .accent, .attention, .fail
        ]
    }

    /// Every string a row renders, and the `CallRecord` field behind it.
    ///
    /// This exists so B4 has an oracle. "No number appears that the router does not observe" cannot
    /// be checked by surveying a view — a survey passes by whatever the surveyor chose to look at.
    /// It can be checked by making the row's text come from one mapping and asserting that
    /// mapping's field set against the table in `planning/specs/spec-M2.md`, which is written by a
    /// human and is not this code.
    public enum ActivityRowField: String, CaseIterable, Sendable {
        case when
        case server
        case tool
        case project
        case session
        case took
        case coldMark = "cold mark"
        case failureMark = "failure mark"

        /// The `CallRecord` field this reads. Two fields for the failure mark, because the mark and
        /// the message behind it are one fact reported in two places on the wire.
        public var recordFields: [String] {
            switch self {
            case .when: ["ts"]
            case .server: ["server"]
            case .tool: ["tool"]
            case .project: ["project", "cwd"]
            case .session: ["pid"]
            case .took: ["ms"]
            case .coldMark: ["cold"]
            case .failureMark: ["ok", "err"]
            }
        }

        /// What this field renders for one record, or nil where the field draws nothing.
        ///
        /// The row calls through here for its text, so a field that renders something this mapping
        /// does not know about cannot exist without the test noticing.
        public func text(for record: CallRecord, age: String) -> String? {
            switch self {
            case .when: age
            case .server: record.server
            case .tool: record.tool
            case .project: projectLabel(cwd: record.cwd, project: record.project)
            case .session: ActivityCopy.sessionColumn(pid: record.pid)
            case .took: ActivityCopy.duration(ms: record.ms)
            // Marks, not text. They are in the enum because they are things the row renders from a
            // record, and leaving them out would let a mark appear with no named source.
            case .coldMark, .failureMark: nil
            }
        }
    }
#endif
