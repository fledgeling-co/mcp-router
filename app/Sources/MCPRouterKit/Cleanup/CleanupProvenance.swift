import Foundation

/// Where the figures inside Cleanup's two destructive dialogs came from, and how loudly each dialog
/// says so.
///
/// **Its own file because the enum it extends is at its line limit**, and because everything here
/// answers one question the rest of `CleanupPresentation` does not ask: not *what does this act
/// destroy* but *when was the number in front of you observed, and is it still the number*. M7's
/// Phase D critic raised both halves (findings 4 and 8), graded both VALID, and deferred them
/// together as M12 with the reason that marking staleness inside a modal is a design decision rather
/// than a defect one item may settle alone. This file is that decision.
extension CleanupPresentation {
// MARK: - Where a destructive dialog's figures came from

/// What a dialog says about the provenance of the figures in it, and how loudly.
///
/// A value rather than a branch inside the view, so the decision *which* treatment a state gets
/// is testable without a host — the same argument `ServersBoardModel.removeConsequence` already
/// won for the wording. A view that branched on `isStale` itself would put the one thing this
/// item is about in the one layer this repo cannot assert against.
public enum Provenance: Equatable, Sendable {
    /// Nothing to disclose. Not an empty string: a caller rendering `""` draws a gap where the
    /// reader expects a sentence, and the two are different claims.
    case none
    /// A current reading — one quiet secondary sentence under the thing it qualifies
    /// (`DESIGN.md` §6).
    case quiet(String)
    /// A stale reading — the board's own marker, because the board draws one above the table for
    /// this exact state and §6 wants one wording per state rather than a second phrasing
    /// invented for the modal that covers it.
    case marked(String)

    /// The sentence, whichever treatment it takes. For `none` there is none.
    public var text: String? {
        switch self {
        case .none: nil
        case let .quiet(text), let .marked(text): text
        }
    }
}

/// The clock time a reading was taken, as a dialog states it.
///
/// **Absolute, deliberately, and this is the one design decision in the whole item worth
/// arguing.** A relative age — "taken 3m ago" — is computed when the view body runs, and a
/// modal's body does not re-run while it sits open: nothing it reads is observed state that
/// changes with the clock. So a dialog left open for a quarter of an hour would go on saying
/// "3m ago", which is a figure reading as fresher than it is — the exact defect this item exists
/// to remove, rebuilt one line lower down. An absolute stamp is equally true at every instant
/// the dialog is on screen, and "as of" is what M7's finding 8 asked for in the first place.
///
/// The date is included only when the reading is not from today, so the ordinary line stays
/// short and a reading from yesterday cannot read as one from this afternoon.
///
/// The formatter is built per call rather than cached in a `static let`. `DateFormatter` is not
/// `Sendable`, this enum has no isolation to hang one on, and `nonisolated(unsafe)` would be a
/// promise made to the compiler for a saving nobody can measure on a dialog line.
public static func asOfLabel(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    if calendar.isDate(date, inSameDayAs: now) {
        formatter.setLocalizedDateFormatFromTemplate("jmm")
    } else {
        formatter.setLocalizedDateFormatFromTemplate("MMMdjmm")
    }
    return formatter.string(from: date)
}

/// The reset dialog's provenance, or `.none` when there is no reading to date.
///
/// **Two claims, kept apart from the consequence rather than folded into it.** `resetConsequence`
/// says what the act destroys; this says when the figure in it was read, and that the figure is a
/// floor. Two boards call the first one so they cannot disagree about the same irreversible act,
/// and folding provenance in would put one board's reading model inside a sentence the other
/// board also speaks.
///
/// **The branch is `calls != nil`, never `calls > 0`.** An observed zero is a figure, and it is
/// the figure most in need of an as-of time: "there is nothing to discard" is the claim likeliest
/// to have gone false since the reading was taken. M7's Phase D finding 1 was this same trap one
/// layer down — an optional added to prevent a sentence, defeated by a `reduce` seed upstream of
/// it — and reading `> 0` here would rebuild it in the provenance layer. `calls` is taken raw,
/// rather than as a `Bool` the caller derives, so that mistake stays inside this function where a
/// test can see it.
///
/// **`.none` when a fresh reading carries no count.** The consequence already says the router has
/// not stated how many; dating a figure that does not exist would attach a provenance to nothing.
public static func resetFigureProvenance(
    observedAt: Date,
    isStale: Bool,
    calls: Int?,
    now: Date = Date()
) -> Provenance {
    let stamp = asOfLabel(observedAt, now: now)
    // One clause for every branch that has a count, so a reader comparing the fresh and stale
    // dialogs is not left wondering what the difference in wording was meant to signal.
    let accrual = "Whatever the router has recorded after that is discarded as well."
    guard isStale else {
        guard let calls else { return .none }
        let opening = calls == 0
            ? "The count was zero in the reading taken at \(stamp)."
            : "This figure is from the reading taken at \(stamp)."
        return .quiet("\(opening) \(accrual)")
    }
    let marker = staleReadingClause(stamp: stamp)
    // A stale reading whose summary never answered is a different sentence, not the same one
    // with a clause missing: "this is the last reading the router gave" sits under a consequence
    // that says the router never gave a number, and saying only that would read as a claim about
    // the count. It says what is true of the count instead.
    guard calls != nil else { return .marked("\(marker) It carried no call count.") }
    return .quiet("\(marker) \(accrual)")
}

/// The removal dialog's provenance.
///
/// **It does not enumerate what it is the provenance of.** The obvious wording — "the tool count
/// and the key names above" — is false for a server carrying neither: `removeConsequence` draws
/// *"Nothing secret is stored on this entry"* for that case and prints no key names at all, so
/// the line would claim provenance over something the reader cannot see.
///
/// Never `.none` while there is a reading: the sheet computes its two consequence paragraphs from
/// a candidate row, so a sheet with a candidate always has something to date. The candidate-less
/// branch shows `consequenceUnavailable`, states no figure, and never asks for this.
public static func removeFigureProvenance(
    observedAt: Date,
    isStale: Bool,
    now: Date = Date()
) -> Provenance {
    let stamp = asOfLabel(observedAt, now: now)
    guard isStale else {
        return .quiet("What removing it takes with it was read at \(stamp).")
    }
    return .marked(
        "\(staleReadingClause(stamp: stamp)) What removing it takes with it may have changed."
    )
}

/// The board's own sentence about a stale reading, with the time it was taken.
///
/// `StaleReadingBanner` says *"These servers are the last reading the router gave, kept rather
/// than cleared. Nothing about them is current."* above the table. This is the same state, so §6
/// wants the same words rather than a second phrasing invented for the dialog that covers it —
/// and a modal *does* cover it, which is how M7's findings 4 and 8 reached a destructive dialog
/// on a board that already discloses this.
///
/// **It carries a time where that banner deliberately does not**, and the difference is a fact
/// rather than a preference. The banner's doc comment refuses an as-of because
/// `ServerStateTracker` corrects a stale poll with any call records seen since, so a timestamp
/// would overstate what is on screen. This board runs no tracker: `Reading` is a plain snapshot
/// of one `load()`, uncorrected, so the time it was taken is exactly what it claims to be.
static func staleReadingClause(stamp: String) -> String {
    "This is the last reading the router gave, taken at \(stamp), and nothing about it is "
        + "current."
}
}
