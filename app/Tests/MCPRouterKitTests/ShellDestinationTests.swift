import Foundation
import Testing
@testable import MCPRouterKit

/// The sidebar's model, held to `DESIGN.md` and to the product's central honesty rule.
@Suite("Shell destinations")
struct ShellDestinationTests {
    @Test("the two groups carry exactly the destinations the design specifies, in order")
    func groupsAreCorrect() {
        #expect(Destination.inGroup(.running) == [.activity, .servers, .skills])
        #expect(Destination.inGroup(.library) == [.discover, .inbox, .evals, .cleanup])
        #expect(Destination.inGroup(nil) == [.settings])
        // Declaration order is sidebar order, and the groups partition it exactly — a destination
        // in no group and not the tail would silently never render.
        #expect(
            Destination.inGroup(.running) + Destination.inGroup(.library) + Destination.inGroup(nil)
                == Destination.ordered
        )
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

        for destination in [Destination.activity, .discover, .evals, .settings] {
            #expect(destination.badgeSource == nil, "\(destination.title) has no observed source")
        }
    }

    @Test("exactly seven destinations carry a selection digit, numbered 1 through 7")
    func selectionDigitsAreContiguous() {
        let digits = Destination.ordered.compactMap(\.selectionDigit)
        #expect(digits == [1, 2, 3, 4, 5, 6, 7])
        // Settings is reached by ⌘, and must not also carry a digit: two shortcuts for one command
        // teaches two habits for the same thing.
        #expect(Destination.settings.selectionDigit == nil)
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
}
