import Foundation
import Testing
@testable import MCPRouterKit

/// The breaker's dimensions against the design authority.
///
/// The invariants in `BreakerGeometryTests` prove the construction *holds together* — the slot
/// bounds the toggle, the lamp sits inside the housing. They say nothing about whether the numbers
/// are the ones that were designed: every dimension could be doubled and every invariant would
/// still pass. This is the other half, and it is the half that was missing.
@Suite("Breaker geometry parity with DESIGN.md")
struct BreakerGeometryParityTests {
    private static func documentText() throws -> String {
        let url = try DesignDocParser.designDocURL()
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("the documented breaker dimensions and the geometry's own are the same set")
    func nameSetsMatchExactly() throws {
        let documented = try Set(DesignDocParser.breakerRows(in: Self.documentText()).map(\.element))
        let inCode = Set(BreakerGeometry.standard.documentedValues.keys)
        #expect(!documented.isEmpty, "parsed no breaker rows — the document changed shape")
        #expect(
            documented.symmetricDifference(inCode).isEmpty,
            "breaker geometry and DESIGN.md disagree on: \(documented.symmetricDifference(inCode).sorted())"
        )
    }

    @Test("every documented breaker dimension is the value the code ships")
    func valuesMatchTheDocument() throws {
        let rows = try DesignDocParser.breakerRows(in: Self.documentText())
        let values = BreakerGeometry.standard.documentedValues
        #expect(rows.count >= 19, "expected 19 breaker rows, parsed \(rows.count)")

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

    /// Reduce Motion, as a decision that can be checked without a running app.
    ///
    /// This used to be unreachable: the choice lived in a `@Environment`-reading computed property
    /// inside the view, so "the animation goes and the state change stays" was a claim with no
    /// test behind it. `spring(raised:reduceMotion:)` is the same decision as a pure function.
    @Test("reduce motion removes the animation and nothing else")
    func reduceMotionDropsOnlyTheAnimation() {
        let g = BreakerGeometry.standard
        #expect(g.spring(raised: true, reduceMotion: true) == nil)
        #expect(g.spring(raised: false, reduceMotion: true) == nil)

        // With motion allowed, each direction takes its own documented spring.
        let rising = g.spring(raised: true, reduceMotion: false)
        #expect(rising?.response == g.riseResponse)
        #expect(rising?.damping == g.riseDamping)
        let falling = g.spring(raised: false, reduceMotion: false)
        #expect(falling?.response == g.fallResponse)
        #expect(falling?.damping == g.fallDamping)
    }
}
