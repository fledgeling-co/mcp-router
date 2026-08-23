import Foundation
import Testing
@testable import MCPRouterKit

/// The sidebar's model, held to `DESIGN.md` and to the product's central honesty rule.
@Suite("Shell destinations")
struct ShellDestinationTests {
    @Test("the two groups carry exactly the destinations the design specifies, in order")
    func groupsAreCorrect() {
        #expect(Destination.inGroup(.running) == [.activity, .servers, .skills, .harnesses])
        #expect(Destination.inGroup(.library) == [.discover, .inbox, .evals, .cleanup, .insights])
        // Declaration order is sidebar order, and the two groups partition it **exactly**. There is
        // no ungrouped tail any more — it held Settings alone, and Settings is a window — so this is
        // now a total partition rather than a partition plus a remainder, which is why `group` is
        // no longer optional.
        #expect(
            Destination.inGroup(.running) + Destination.inGroup(.library) == Destination.ordered
        )
        #expect(DestinationGroup.allCases.flatMap(Destination.inGroup).count
            == Destination.allCases.count)
    }

    /// `DESIGN.md` §3.2 — sentence case, and the fix for tracked uppercase is to remove it.
    @Test("group headers and titles are sentence case, never upper case")
    func headersAreSentenceCase() {
        for group in DestinationGroup.allCases {
            #expect(group.rawValue != group.rawValue.uppercased(), "\(group.rawValue) is upper case")
            #expect(group.rawValue.first?.isUppercase == true)
        }
        for destination in Destination.allCases {
            #expect(destination.title != destination.title.uppercased())
            #expect(!destination.title.isEmpty)
        }
    }

    /// The clause this suite exists for. `DESIGN.md` §6: no number nobody observed.
    ///
    /// **Inbox's source changed in M6, and the reason it was `nil` is why.** The prototype draws a
    /// badge on Skills and on Inbox. It stays forbidden on Skills — `ControlAPIClient` exposes no
    /// skills endpoint at all, so a count there would be invented outright. Inbox was forbidden on
    /// the same grounds *while nothing counted the queue*; M6 builds the queue into the app, so the
    /// count is now an observation the app makes directly. That is a change of provenance, not a
    /// relaxation, and the assertion below is stronger than the one it replaces: the source must be
    /// the app-held queue specifically, so a later edit cannot quietly point Inbox at a server field.
    @Test("only destinations with an observed source may carry a badge")
    func badgeSourcesAreOnlyWhatIsObserved() {
        #expect(Destination.servers.badgeSource == .serversNeedingAttention)
        #expect(Destination.cleanup.badgeSource == .serversNeverUsed)
        #expect(
            Destination.inbox.badgeSource == .queuedFromPhone,
            "the inbox counts the app's own queue, never anything the router serves"
        )

        #expect(Destination.skills.badgeSource == nil, "the control API exposes no skills endpoint")

        for destination in [Destination.activity, .discover, .evals] {
            #expect(destination.badgeSource == nil, "\(destination.title) has no observed source")
        }
    }

    /// **Contiguous *and* in sidebar order**, which is the half M22 made load-bearing. The View
    /// menu lists destinations in declaration order and labels each with its digit, so a digit that
    /// does not follow the list prints `⌘1 ⌘2 ⌘3 ⌘8 ⌘4 …` down one menu. Comparing against a
    /// literal sequence catches a renumbering; comparing `digits` against `1...count` would not
    /// catch a *permutation*, which is the mistake actually available here.
    @Test("exactly nine destinations carry a selection digit, numbered 1 through 9 in sidebar order")
    func selectionDigitsAreContiguous() {
        let digits = Destination.ordered.compactMap(\.selectionDigit)
        #expect(digits == [1, 2, 3, 4, 5, 6, 7, 8, 9])
        // Every destination carries one now, because the one that did not was Settings and Settings
        // is a window. The digit stays optional on the type so the filter that keeps a digit-less
        // destination out of the View menu survives; what is asserted here is that nothing is
        // currently being filtered out silently.
        #expect(digits.count == Destination.allCases.count)
    }

    /// **The observation this makes flips at M15 without a line of `restoring` moving**, which is
    /// what that path was written for. At `4de2080` a stored `"settings"` restored to the Settings
    /// board, because the case existed; the same stored value now restores to Activity, because the
    /// `guard let` fails. Anyone who had the Settings board selected when they last quit gets
    /// Activity, not a blank pane.
    @Test("a UserDefaults domain holding the retired Settings destination restores to Activity")
    func retiredSettingsDestinationRestoresToActivity() {
        #expect(Destination.restoring("settings") == .activity)
        #expect(!Destination.allCases.contains { $0.rawValue == "settings" })
    }

    @Test("a stored destination this build no longer has falls back rather than blanking")
    func restorationFallsBack() {
        #expect(Destination.restoring("servers") == .servers)
        #expect(Destination.restoring("a-destination-that-was-removed") == .activity)
        #expect(Destination.restoring(nil) == .activity)
        #expect(Destination.fallback == .activity)
    }

    @Test("every destination names an icon, and no two share one")
    func iconNamesAreDistinct() {
        let names = Destination.allCases.map(\.iconName)
        #expect(Set(names).count == names.count, "two destinations draw the same icon")
        #expect(names.allSatisfy { !$0.isEmpty })
    }

    /// **The label reads `Checks`; the identifier stays `evals`. Both halves are deliberate, and
    /// until now neither was pinned.**
    ///
    /// M9 renamed the one word in this app that promised a graded verdict the product cannot
    /// produce — there is no eval runner in it, in any form. What a user reads moved. What a machine
    /// matches did not: the `rawValue` is persisted by frame restoration and used by the prototype's
    /// `?pane=evals` deep link, so aligning it would silently break restoration for anyone who had
    /// already run the app, and every mock link with it.
    ///
    /// Nothing in the suite held either fact. An out-of-family critic pointed out that the
    /// acceptance script forbids the *old* word without ever asserting the *current* strings agree,
    /// so a third spelling — `Health`, say, on the pane heading alone — would have left the sidebar
    /// and the pane it opens disagreeing with every gate green. `CheckCopy.evalsTitle` is now
    /// derived from this property rather than spelled again, and this is the guard for anyone who
    /// re-inlines the literal.
    @Test("the destination reads Checks, and its restoration key is still evals")
    func evalsReadsAsChecksWithoutMovingItsKey() {
        #expect(Destination.evals.title == "Checks")
        #expect(CheckCopy.evalsTitle == Destination.evals.title)

        // The identifier half. `restoring` is the path a relaunch actually takes.
        #expect(Destination.evals.rawValue == "evals")
        #expect(Destination.restoring("evals") == .evals)

        // And the word is gone from every label a user reads, rather than from this one only.
        #expect(!Destination.allCases.contains { $0.title == "Evals" })
    }
}
