import Foundation
import Testing
@testable import MCPRouterKit

/// The breaker's construction, tested as values.
///
/// These run headless, in the same suite as everything else, because the invariant they hold is
/// what two prototype rounds got wrong — and a defect only a running app can catch is a defect
/// that ships. `BreakerGeometry` lives in the UI-free target for exactly this reason.
@Suite("Breaker construction")
struct BreakerGeometryTests {
    let g = BreakerGeometry.standard

    @Test("the slot is at least as wide as the toggle")
    func slotWideEnough() {
        #expect(
            g.slotIsAtLeastAsWideAsToggle,
            "slot \(g.slotWidth) vs toggle \(g.toggleWidth) — the lever would cover the track"
        )
    }

    @Test("the slot is strictly taller than the toggle")
    func slotTallEnough() {
        #expect(
            g.slotIsStrictlyTallerThanToggle,
            "slot \(g.slotHeight) vs toggle \(g.toggleHeight) — nothing would read as a recess"
        )
    }

    /// The failure that makes a dormant row stop reading as a switch, which is most rows most of
    /// the time. Checked at both ends of the travel rather than only at rest.
    @Test("a recess stays visible at both ends of the travel")
    func recessVisibleThroughout() {
        #expect(g.toggleStaysWithinSlot)
        let visibleAbove = g.slotInsetBottom + g.slotHeight - (g.toggleRestingOffset + g.toggleHeight)
        let visibleBelow = g.toggleRaisedOffset - g.slotInsetBottom
        #expect(visibleAbove > 0, "nothing shows above the toggle when it is down")
        #expect(visibleBelow > 0, "nothing shows below the toggle when it is up")
    }

    /// The lamp used to sit at `top:-9px`, outside a 40pt housing — 1pt beyond a 56pt row, which
    /// SwiftUI clips in most containers.
    @Test("the lamp sits inside the housing, so it cannot clip")
    func lampContained() {
        #expect(
            g.lampIsInsideHousing,
            "lamp boss \(g.lampBossHeight) vs slot top inset \(g.slotInsetTop)"
        )
        #expect(g.housingHeight >= g.lampBossHeight + g.slotHeight + g.slotInsetBottom)
    }

    @Test("rising overshoots and is fast; falling does neither")
    func springsMatchTheDocument() {
        #expect(g.risesWithOvershoot)
        #expect(g.fallsWithoutOvershoot)
        #expect(g.risesFasterThanItFalls)
    }

    @Test("exactly one dormant state and three lit ones, each bound to its own meaning")
    func statesMapToReservedTokens() {
        #expect(BreakerState.allCases.count == 4)
        #expect(BreakerState.dormant.indicator == nil)
        let lit = BreakerState.allCases.compactMap(\.indicator)
        #expect(lit.count == 3)
        #expect(Set(lit).count == 3, "two states share an indicator colour")
        for token in lit {
            #expect(token.isReservedMeaning, "\(token.rawValue) is not one of the exclusive hues")
        }
        // The lever is only up when something is actually running.
        #expect(BreakerState.allCases.filter(\.isRaised) == [.running])
    }
}
