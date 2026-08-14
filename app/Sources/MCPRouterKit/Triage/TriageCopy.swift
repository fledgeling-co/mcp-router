import Foundation

/// Every string the Triage surface renders.
///
/// A **sibling** of `PairingCopy` and `DiscoverCopy`, never an extension of either. Growing a merged
/// shared manifest from inside a feature is how two features come to disagree about what it
/// contains, and this phone already carries two manifests that other items own.
///
/// Three manifests ship rather than one, **split before they grew rather than after**: Triage, Queue
/// and Library are three surfaces with three vocabularies, which is a real seam.
///
/// The precedent is I1's, and it is worth citing correctly. `PairingCopy.swift:3` carries a
/// **four**-rule file-scope suppression — `cyclomatic_complexity`, `function_body_length`,
/// `type_body_length`, `file_length` — rather than a split. I2 then did the opposite and split
/// `DiscoverCopy` into six files with no suppressions at all. This item follows I2.
///
/// Substitution follows `DiscoverCopy`'s enumerated-token mechanism rather than `PairingCopy`'s
/// single-value one: a token that no case declares fails a test, where free interpolation renders a
/// typo'd `{mack}` straight to the user.
public enum TriageCopy {
    // MARK: - Substitution

    /// The complete set of substitutions any template in this file may carry.
    public enum Token: String, Sendable, CaseIterable {
        /// The paired Mac's name. Renders `"your Mac"` when none is paired — which is what the
        /// shipped app currently gets, because `MCPRouterIOSApp` passes no `macName`.
        case mac
        /// A count that is the size of a locally-held set: a bucket, or the selection.
        case count
        /// A registry entry's display name.
        case name
        /// The host a remote server's requests go to.
        case host
        /// A warning the router sent that matched no known class, carried verbatim.
        case warning

        public var placeholder: String { "{\(rawValue)}" }
    }

    /// A rendered piece of copy. Same shape as `DiscoverCopy.Entry`, deliberately — two manifests on
    /// one phone with two different entry shapes is a seam nobody asked for.
    public struct Entry: Sendable, Equatable {
        public let headline: String?
        public let body: String
        public let actionLabel: String?
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

        /// Substitute values in. A token with no supplied value is **left as its placeholder**
        /// rather than silently emptied: a visible `{mac}` is a bug report, and a sentence that
        /// quietly loses its subject is not.
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
                isDisabled: isDisabled,
                carriesNarrowing: carriesNarrowing
            )
        }
    }

    // MARK: - Keys

    /// The controls and the standing hint.
    public enum ControlKey: String, Sendable, CaseIterable {
        case hint
        case bucketUndecided
        case bucketQueued
        case bucketDismissed
        case selectAll
        case clearSelection
        case restore
        case expandedHeading
    }

    /// The commit bar. Label and note are one entry because a button whose label and note disagree
    /// is the defect keeping them adjacent prevents.
    public enum CommitKey: String, Sendable, CaseIterable {
        case ready
        case neverPaired
        case undoQueued
        case undoDismissed
        case undo
        case dismiss
        /// A batch where some items were refused by the store. A partial batch reports what did and
        /// did not land — it never reports success for items it did not save (A14).
        case partialWrite
        case writeFailed
    }

    /// The seven short clauses of the row's capability line, mirroring `CapabilitySummary.Clause`.
    ///
    /// Short by design: this line must never truncate, and the only way to guarantee that against
    /// arbitrary entries is a closed vocabulary of brief clauses.
    public enum ClauseKey: String, Sendable, CaseIterable {
        case runsLocally
        case remote
        case remoteUnknownHost
        case credential
        case credentialSmithery
        case archived
        case noInstall
    }

    /// The list's states — `DESIGN.md` §5's nine, in the three buckets' shapes.
    public enum StateKey: String, Sendable, CaseIterable {
        case emptyUndecided
        case emptyQueued
        case emptyDismissed
        case partialOfficialDown
        case partialSmitheryDown
        case partialGitHubLimited
        case partialUnrecognised
        case failed
        case offline
        /// A9: the dismissal file exists and will not decode. Its own state, because a dismissal
        /// set silently read as empty re-offers everything the user turned down.
        case dismissalsUnreadable
    }

    /// The sum. One switch per element type, each total over its own type.
    public enum Key: Sendable, Equatable, Hashable {
        case control(ControlKey)
        case commit(CommitKey)
        case clause(ClauseKey)
        case state(StateKey)

        public static var allCases: [Key] {
            ControlKey.allCases.map(Key.control)
                + CommitKey.allCases.map(Key.commit)
                + ClauseKey.allCases.map(Key.clause)
                + StateKey.allCases.map(Key.state)
        }
    }

    /// The copy. Exhaustive by construction.
    public static func entry(_ key: Key) -> Entry {
        switch key {
        case let .control(k): control(k)
        case let .commit(k): commit(k)
        case let .clause(k): clause(k)
        case let .state(k): state(k)
        }
    }

    // MARK: - Controls

    static func control(_ key: ControlKey) -> Entry {
        switch key {
        case .hint:
            Entry(body: "Tap a name to read what it can do. Tick what is worth your Mac's attention.")
        case .bucketUndecided:
            Entry(body: "Undecided")
        case .bucketQueued:
            Entry(body: "Queued")
        case .bucketDismissed:
            Entry(body: "Not for me")
        case .selectAll:
            Entry(body: "Select all")
        case .clearSelection:
            Entry(body: "Clear")
        case .restore:
            Entry(body: "Move back to Undecided")
        case .expandedHeading:
            Entry(body: "What it would be able to do")
        }
    }

    /// Which keys carry `PairingCopy.neverInstalls`. Asserted against, so the placement claim has
    /// something to check that is not the thing under test.
    public static var narrowingKeys: Set<Key> {
        Set(Key.allCases.filter { entry($0).carriesNarrowing })
    }
}
