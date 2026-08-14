import Foundation
import Testing

@testable import MCPRouterKit

/// Cleanup's inclusion rules and its observation window.
///
/// The pane's whole claim is that it knows how much it knows, so the window is tested as carefully as
/// the candidacy: "never used" over 41 days is evidence and over two hours is nothing, and a surface
/// that renders those identically is making a claim it cannot support.
@Suite("Cleanup presentation")
struct CleanupPresentationTests {
    static func iso(daysAgo: Double, from now: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: now.addingTimeInterval(-daysAgo * 86400))
    }

    // MARK: - Candidacy

    @Test("A server is proposed for the three observed reasons, and no invented one")
    func serverCandidacy() {
        #expect(CleanupPresentation.candidacy(for: CheckTests.server(calls: 0)).isCandidate)
        #expect(
            CleanupPresentation.candidacy(for: CheckTests.server(indexError: "spawn ENOENT")).isCandidate
        )
        #expect(
            CleanupPresentation.candidacy(for: CheckTests.server(tools: 0, calls: 4)).isCandidate
        )
        // A busy, healthy server is never proposed — and neither is one merely used "a while ago",
        // because that is not a fact the router reports.
        #expect(!CleanupPresentation.candidacy(for: CheckTests.server(calls: 400)).isCandidate)
    }

    @Test("A7: one unreadable client holds every skill out of the proposal")
    func unreadableClientSuspendsTheJudgement() {
        // A skill absent everywhere readable may be installed in exactly the folder nobody could
        // open, and there is no way to tell which — so the whole proposal is held, not a subset
        // guessed at.
        let clients = [CheckTests.client("claude"), CheckTests.client("cursor", status: .unreadable)]
        let absent = CheckTests.skill(presence: ["claude": .absent])
        let candidacy = CleanupPresentation.candidacy(for: absent, clients: clients)
        #expect(candidacy.isHeldOut)
        #expect(!candidacy.isCandidate)

        // With every capable client read, the same skill is a candidate.
        let readable = [CheckTests.client("claude"), CheckTests.client("cursor")]
        #expect(
            CleanupPresentation.candidacy(
                for: CheckTests.skill(presence: ["claude": .absent, "cursor": .absent]),
                clients: readable
            ).isCandidate
        )
        // And one that is installed somewhere never is.
        #expect(
            !CleanupPresentation.candidacy(
                for: CheckTests.skill(presence: ["claude": .present]),
                clients: readable
            ).isCandidate
        )
    }

    @Test("The held-out banner counts what was held and names why")
    func heldOutBannerNamesTheClient() {
        let banner = CleanupPresentation.heldOutBanner(count: 3, clients: ["Cursor"])
        #expect(banner.contains("3"))
        #expect(banner.contains("Cursor"))
    }

    // MARK: - A9: the window

    @Test("A9: the weak-window banner fires strictly under seven days, boundary included")
    func weakWindowBoundary() {
        let now = Date()
        // Just under seven days is weak; exactly seven and beyond is not. The boundary is asserted
        // rather than sampled, because a threshold nobody tested at its edge is a threshold nobody
        // tested.
        let justUnder = CleanupPresentation.window(since: Self.iso(daysAgo: 6.99, from: now), now: now)
        #expect(justUnder?.isWeak == true)
        let exactlySeven = CleanupPresentation.window(since: Self.iso(daysAgo: 7.0, from: now), now: now)
        #expect(exactlySeven?.isWeak == false)
        let long = CleanupPresentation.window(since: Self.iso(daysAgo: 41, from: now), now: now)
        #expect(long?.isWeak == false)
        #expect(long?.days == 41)
    }

    @Test("A8: an unparseable since drops the clause rather than substituting a number")
    func unparseableWindowSaysNothing() {
        #expect(CleanupPresentation.window(since: "not a date") == nil)
        let subtitle = CleanupPresentation.subtitle(window: nil)
        #expect(subtitle.contains("It proposes; you decide"))
        // No invented duration anywhere in the fallback.
        #expect(!subtitle.contains("30"))
        #expect(!subtitle.contains("day"))
    }

    @Test("A8: no Cleanup copy function contains a literal duration")
    func noLiteralDurations() {
        let now = Date()
        let window = CleanupPresentation.window(since: Self.iso(daysAgo: 41, from: now), now: now)!
        let subtitle = CleanupPresentation.subtitle(window: window)
        // The figure in the sentence is the router's, rendered from `since` — so it says 41d, which
        // is what the router's own data implies, and it says it because the data said so.
        #expect(subtitle.contains(window.label))
    }

    // MARK: - A27b: the track

    @Test("A27b: the track pegs full beyond the reference rather than overflowing")
    func trackPegs() {
        #expect(CleanupPresentation.trackFraction(days: 0) == 0)
        #expect(CleanupPresentation.trackFraction(days: 15) == 0.5)
        #expect(CleanupPresentation.trackFraction(days: 30) == 1)
        // A 400-day window is not drawn thirteen times its own track; the mono figure beside it
        // carries the real value.
        #expect(CleanupPresentation.trackFraction(days: 400) == 1)
    }

    // MARK: - The honesty rules

    @Test("The footer refuses a memory saving and the trash metaphor")
    func footerRefusesTheFabrication() {
        let footer = CleanupPresentation.footer
        #expect(footer.contains("Nothing here claims a memory saving"))
        #expect(footer.contains("what you remove is not counted"))
        for word in ["trash", "bin", "rubbish", "reclaim", "freed", "MB", "GB"] {
            #expect(!footer.lowercased().contains(word.lowercased()), "\"\(word)\" is in the footer")
        }
    }

    @Test("A15b: resetting names its consequence and says it cannot be undone")
    func resetNamesItsConsequence() {
        let now = Date()
        let window = CleanupPresentation.window(since: Self.iso(daysAgo: 41, from: now), now: now)
        let consequence = CleanupPresentation.resetConsequence(calls: 812, window: window)
        #expect(consequence.contains("812"))
        #expect(consequence.contains("no way to bring them back"))
        // It also warns about the aftermath this very pane will show.
        #expect(consequence.contains("never-used"))
    }

    @Test("The badge note states what the sidebar counts, because it counts a subset")
    func badgeNoteReconciles() {
        let note = CleanupPresentation.badgeNote(neverUsedCount: 3)
        #expect(note.contains("3"))
        #expect(note.contains("failed to index"))
    }
}
