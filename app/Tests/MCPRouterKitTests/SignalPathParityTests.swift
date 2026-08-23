import Foundation
import Testing
@testable import MCPRouterKit

/// The Signal Path's dimensions against the design authority.
///
/// The direct replacement for `BreakerGeometryParityTests`, and it holds the same half of the
/// argument: `SignalPathGeometryTests` proves the construction *holds together* — the ring fits the
/// lane, the label column is the larger half — and says nothing about whether the numbers are the
/// ones that were designed. Every dimension could be doubled and every invariant would still pass.
@Suite("Signal Path geometry parity with DESIGN.md")
struct SignalPathGeometryParityTests {
    private static func documentText() throws -> String {
        let url = try DesignDocParser.designDocURL()
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("the documented Signal Path dimensions and the geometry's own are the same set")
    func nameSetsMatchExactly() throws {
        let documented = try Set(DesignDocParser.signalPathRows(in: Self.documentText()).map(\.element))
        let inCode = Set(SignalPathGeometry.standard.documentedValues.keys)
        #expect(!documented.isEmpty, "parsed no Signal Path rows — the document changed shape")
        #expect(
            documented.symmetricDifference(inCode).isEmpty,
            "geometry and DESIGN.md disagree on: \(documented.symmetricDifference(inCode).sorted())"
        )
    }

    @Test("every documented Signal Path dimension is the value the code ships")
    func valuesMatchTheDocument() throws {
        let rows = try DesignDocParser.signalPathRows(in: Self.documentText())
        let values = SignalPathGeometry.standard.documentedValues
        #expect(rows.count >= 10, "expected 10 Signal Path rows, parsed \(rows.count)")

        for row in rows {
            guard let shipped = values[row.element] else {
                Issue.record("DESIGN.md documents '\(row.element)' but the geometry has no such value")
                continue
            }
            guard let documented = row.leadingScalar else {
                Issue.record("'\(row.element)' has a value in code but its documented cell is prose")
                continue
            }
            #expect(shipped == documented, "\(row.element): code \(shipped) vs doc \(documented)")
        }
    }

    /// The lane is deliberately absent from this element's own table, and this is what stops that
    /// being a hole rather than a decision.
    ///
    /// `laneHeight` is read from `MetricToken.jackLane`, which the chrome table documents and the
    /// mock publishes. If someone adds a `Jack lane` row here, the value ships from two places and
    /// the two are free to disagree — the defect `Card radius` was split out of the popover cell to
    /// end.
    @Test("the lane is documented once, in the chrome table, and read from there")
    func theLaneIsNotDocumentedTwice() throws {
        let signalPath = try Set(DesignDocParser.signalPathRows(in: Self.documentText()).map(\.element))
        #expect(!signalPath.contains("Jack lane"), "the lane is now documented in two tables")
        #expect(SignalPathGeometry.standard.laneHeight == MetricToken.jackLane.leadingScalar)
    }

    /// Reduce Motion, as a decision that can be checked without a running app.
    ///
    /// The same contract `BreakerGeometry.spring(raised:reduceMotion:)` carried: the animation goes
    /// and the state change does not. Inside a view body reading `@Environment` it is a claim no
    /// test can reach.
    @Test("reduce motion removes the animation and nothing else")
    func reduceMotionDropsOnlyTheAnimation() {
        let g = SignalPathGeometry.standard
        #expect(g.plugTransition(reduceMotion: true) == nil)
        #expect(g.plugTransition(reduceMotion: false) == g.plugTransitionSeconds)
    }
}
