import Foundation
import Testing
@testable import MCPRouterKit

/// The Signal Path's construction, tested as values.
///
/// Headless, in the same suite as everything else, because what these hold is what a screenshot
/// comparison cannot: the band's two hard constraints were *measured* by the mock's author — a
/// single-column field ran 500pt deep at eleven upstreams, and a clipped `3:41 left` loses the only
/// part of the label carrying information — and a constraint nobody can re-check is a constraint
/// that comes back.
@Suite("Signal Path construction")
struct SignalPathGeometryTests {
    let g = SignalPathGeometry.standard

    @Test("the plug and both sides of its ring fit inside the lane")
    func plugFitsTheLane() {
        #expect(
            g.plugFitsTheLane,
            "plug footprint \(g.plugFootprint) against a \(g.laneHeight)pt lane — the ring clips"
        )
    }

    @Test("the label column is the larger half of the jack")
    func labelHasRoom() {
        #expect(
            g.theLabelHasRoom,
            "label column \(g.labelWidth) of a \(g.jackMinimum)pt jack — the condition would clip"
        )
    }

    @Test("the ring reads as a halo rather than as a second plug")
    func ringIsThinnerThanThePlug() {
        #expect(g.theRingIsThinnerThanThePlug, "ring \(g.plugRing) against radius \(g.plugDiameter / 2)")
    }

    /// The brief's first measured constraint: laid out as one column, eleven upstreams pushed the
    /// table off the board. The acceptance criterion is two or more columns at the window the app
    /// actually opens at.
    @Test("the field packs to two or more columns at the board's own width")
    func packsAtTheBoardWidth() {
        // The measured surface's width, which is what MeasureDump renders and what the gate reads.
        let field = g.jackFieldWidth(inBoardWidth: 1280)
        #expect(
            g.columns(inJackFieldWidth: field) >= 2,
            "one column at 1280pt is the failure the brief measured"
        )
    }

    /// The brief's second: *"the rail's gutters are tight enough that two jacks fit beside an open
    /// inspector."* The inspector is `MetricToken.sidebar` plus two table units, and it sits inside
    /// the content zone, so it comes off the board's own width.
    @Test("two jacks still fit beside an open inspector")
    func packsBesideTheInspector() {
        let inspector = MetricToken.sidebar.leadingScalar + MetricToken.tableRows.leadingScalar * 2
        let field = g.jackFieldWidth(inBoardWidth: 1280 - inspector)
        #expect(
            g.columns(inJackFieldWidth: field) >= 2,
            "\(g.columns(inJackFieldWidth: field)) column(s) beside a \(inspector)pt inspector"
        )
    }

    /// The arithmetic itself, at the boundaries rather than in the middle — one track exactly, one
    /// track plus a gutter minus a point, and the width at which the second track lands.
    @Test("the packing arithmetic is the grid's, at its boundaries")
    func packingBoundaries() {
        #expect(g.columns(inJackFieldWidth: g.jackMinimum) == 1)
        #expect(g.columns(inJackFieldWidth: g.jackMinimum * 2 + g.gutter - 1) == 1)
        #expect(g.columns(inJackFieldWidth: g.jackMinimum * 2 + g.gutter) == 2)
        // Never zero: a field narrower than one track still draws one, clipped, rather than none.
        #expect(g.columns(inJackFieldWidth: 0) == 1)
        #expect(g.columns(inJackFieldWidth: -100) == 1)
    }

    @Test("the lane is the mock's own published metric rather than a second spelling of it")
    func laneComesFromTheChromeLadder() {
        #expect(g.laneHeight == MetricToken.jackLane.leadingScalar)
        #expect(g.gutter == MetricToken.gridUnit.leadingScalar)
    }
}
