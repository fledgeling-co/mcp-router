import Foundation
import Testing
@testable import MCPRouterKit

/// A26: the nine designed states, with real copy for every unhappy path.
///
/// `DESIGN.md` §5 names nine states each surface must answer for. The requirement that bites is not
/// "a state exists" — it is that the **unhappy** ones carry a sentence a person can act on, because
/// those are the ones a build without them silently renders as a blank pane.
///
/// This asserts the copy layer, which is where the sentences live and where they can be compared
/// exhaustively. The rendered half of the same rule — that the offline and partial panes actually
/// speak — is in `scripts/acceptance/m7-evals-cleanup.sh`, and is recorded in
/// `planning/evidence/M7-acceptance.md`.
@Suite("A26 — the nine designed states carry real copy")
struct M7DesignedStateTests {
    /// A sentence that is present but useless is the failure this guards, so "non-empty" is not the
    /// bar. Placeholder text, a bare noun and a lorem stub all fail.
    private static func assertUsable(_ text: String, _ label: String) {
        #expect(!text.isEmpty, "\(label) has no copy at all")
        #expect(text.count >= 12, "\(label) is too short to say anything: '\(text)'")
        for placeholder in ["TODO", "TBD", "lorem", "FIXME", "isn't built yet", "Coming soon"] {
            #expect(
                !text.lowercased().contains(placeholder.lowercased()),
                "\(label) is a placeholder, not copy: '\(text)'"
            )
        }
    }

    @Test("Evals answers every unhappy state with a usable sentence")
    func evalsUnhappyStatesSpeak() {
        Self.assertUsable(CheckCopy.evalsEmptyTitle, "Evals empty title")
        Self.assertUsable(CheckCopy.evalsEmptyDetail, "Evals empty detail")
        Self.assertUsable(CheckCopy.evalsSubtitle, "Evals subtitle (the standing disclosure)")
        Self.assertUsable(CheckCopy.evalsFooter, "Evals footer")
        Self.assertUsable(CheckCopy.unstampableDetail, "Evals unstampable detail")
        Self.assertUsable(CheckCopy.historyEmpty, "Evals empty history")

        // Disabled, and the two reasons a control can be dim on this pane.
        Self.assertUsable(CheckCopy.skillRemoveDisabled, "the skill-removal disabled reason")
        Self.assertUsable(CheckCopy.runChecksNeedsSelection, "the re-check disabled reason")
        Self.assertUsable(CheckCopy.removeNeedsServer, "the remove disabled reason")

        // Empty-in-filter is a different state from empty, and must not reuse its words: "nothing
        // to check yet" told to someone who has filtered to "not met" is simply wrong.
        let filtered = CheckCopy.evalsEmptyInFilter("Not met")
        Self.assertUsable(filtered.title, "Evals empty-in-filter title")
        Self.assertUsable(filtered.detail, "Evals empty-in-filter detail")
        #expect(
            filtered.title != CheckCopy.evalsEmptyTitle,
            "an empty filter reuses the empty-board sentence, which is a different claim"
        )
    }

    @Test("Cleanup answers every unhappy state with a usable sentence")
    func cleanupUnhappyStatesSpeak() {
        Self.assertUsable(CleanupPresentation.emptyTitle, "Cleanup empty title")
        Self.assertUsable(CleanupPresentation.emptyDetail, "Cleanup empty detail")
        Self.assertUsable(CleanupPresentation.emptyInFilterTitle, "Cleanup empty-in-filter title")
        Self.assertUsable(CleanupPresentation.emptyInFilterDetail, "Cleanup empty-in-filter detail")
        Self.assertUsable(CleanupPresentation.consequenceUnavailable, "the unstatable-consequence sentence")
        Self.assertUsable(CleanupPresentation.resetTitle, "the reset dialog title")

        #expect(
            CleanupPresentation.emptyInFilterTitle != CleanupPresentation.emptyTitle,
            "an empty filter reuses the empty-board sentence, which is a different claim"
        )
    }

    /// The empty state on Cleanup is the one that is easy to get backwards.
    ///
    /// An empty Cleanup pane is **good news** — nothing is unused — and phrasing it as an absence
    /// ("No results") reads as a failure to find something. It is asserted rather than trusted
    /// because it is a one-word edit away from being wrong.
    @Test("an empty Cleanup pane reads as good news rather than as a failed search")
    func cleanupEmptyIsNotPhrasedAsAbsence() {
        let title = CleanupPresentation.emptyTitle.lowercased()
        for absence in ["no results", "nothing found", "not found", "no matches", "empty"] {
            #expect(!title.contains(absence), "the empty state reads as a failed search: '\(title)'")
        }
        #expect(title.contains("used"), "the empty state does not say why there is nothing here")
    }

    /// Every sentence across both panes is distinct.
    ///
    /// Two states sharing a sentence is two states the reader cannot tell apart, which defeats the
    /// point of having nine of them.
    @Test("no two designed states share a sentence")
    func everyStateSentenceIsDistinct() {
        let sentences = [
            CheckCopy.evalsEmptyTitle, CheckCopy.evalsEmptyDetail,
            CheckCopy.unstampableDetail, CheckCopy.historyEmpty,
            CheckCopy.skillRemoveDisabled, CheckCopy.runChecksNeedsSelection,
            CheckCopy.removeNeedsServer,
            CleanupPresentation.emptyTitle, CleanupPresentation.emptyDetail,
            CleanupPresentation.emptyInFilterTitle, CleanupPresentation.emptyInFilterDetail,
            CleanupPresentation.consequenceUnavailable
        ]
        #expect(
            Set(sentences).count == sentences.count,
            "two designed states speak the same sentence, so a reader cannot tell them apart"
        )
    }
}
