import Foundation

/// The last reversible act on Triage, and everything needed to reverse it.
///
/// **There is no confirmation dialog anywhere on this surface**, and this type is why.
/// `DESIGN.md` §9 is explicit — undo over confirm — and the commit bar has already stated what will
/// happen before the act runs, so a dialog afterwards asks the same question twice. The swipe deck
/// this surface replaces had neither: no dialog *and* no undo.
public enum TriageUndo: Sendable, Equatable {
    /// Entries were queued for the Mac. Reversing removes them from the queue again.
    case queued([String])
    /// Entries were dismissed. Reversing restores them to Undecided.
    case dismissed([String])

    public var ids: [String] {
        switch self {
        case let .queued(ids), let .dismissed(ids): ids
        }
    }

    public var copyKey: TriageCopy.Key {
        switch self {
        case .queued: .commit(.undoQueued)
        case .dismissed: .commit(.undoDismissed)
        }
    }
}

/// A batch that did not fully land.
///
/// **A partial batch reports what did and did not land, and never reports success for an item it
/// did not save.** The precedent is I1's, where two `try?` sites made a refused Keychain write
/// render the "Paired." surface while nothing had been written — a failure that looked exactly like
/// a success until the next launch.
public struct TriageWriteFailure: Sendable, Equatable {
    /// How many items of the batch actually reached storage.
    public let saved: Int
    /// The ids that did not. They stay in Undecided, because that is where they are.
    public let refused: [String]

    public init(saved: Int, refused: [String]) {
        self.saved = saved
        self.refused = refused
    }

    /// Nothing landed at all, which reads differently from "three of five landed".
    public var isTotal: Bool { saved == 0 }

    public var copyKey: TriageCopy.Key {
        isTotal ? .commit(.writeFailed) : .commit(.partialWrite)
    }
}
