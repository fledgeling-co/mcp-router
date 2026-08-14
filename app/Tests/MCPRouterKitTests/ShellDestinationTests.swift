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

    /// The clause this suite exists for. `DESIGN.md` §6: no number the router does not observe.
    ///
    /// The prototype draws a badge on Skills and on Inbox. `ControlAPIClient` exposes no skills
    /// endpoint at all, and Inbox means the phone's review queue (§9), which the router does not
    /// serve. A count on either would have to be invented, so both must stay sourceless — and this
    /// test is what stops one being added because it looked plausible.
    @Test("only destinations with a router-observed source may carry a badge")
    func badgeSourcesAreOnlyWhatTheRouterObserves() {
        #expect(Destination.servers.badgeSource == .serversNeedingAttention)
        #expect(Destination.cleanup.badgeSource == .serversNeverUsed)

        #expect(Destination.skills.badgeSource == nil, "the control API exposes no skills endpoint")
        #expect(
            Destination.inbox.badgeSource == nil,
            "the inbox is the phone's queue; the router serves none"
        )

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
