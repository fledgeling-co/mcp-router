import Foundation

/// The Signal Path's construction, as values rather than as a drawing.
///
/// The Signal Path is the app's signature element and `DESIGN.md` §1 says so: one jack per declared
/// server, showing what is plugged into the router right now. Its geometry lives here, in the
/// headless target, for the reason the outgoing signature's did — **the invariants below have to be
/// testable without a UI harness**, and a defect that only a running app can catch is a defect that
/// ships.
///
/// It replaces `BreakerGeometry` one for one: same shape, same `documentedValues` contract, same
/// parity suite reading `DESIGN.md` as its oracle. What changed is which element the document
/// specifies.
///
/// **Two of these numbers are constraints the mock's author measured rather than chose**, and they
/// are the reason this is a value type instead of a handful of literals in a view:
///
/// 1. `jackMinimum` is the grid track's minimum. Laid out as a single column, eleven upstreams ran
///    the band 500pt deep and pushed the table off the board, so the field packs to the width
///    available and `columns(inJackFieldWidth:)` is the arithmetic that says how many fit.
/// 2. The label column — what is left of a jack once the plug, the gap and the two insets are
///    taken — has to carry a countdown like `3:41 left` without clipping it. Truncating that to
///    `3:41 …` removes the only part of the label that was carrying information.
///
/// The lane height is **not** a value here: it is `MetricToken.jackLane`, which the mock publishes
/// in its own `mac-craft:metrics` block and which `planning/fidelity/token-register.json` already
/// matches. A second spelling of it here would be the same value in two places, which is the defect
/// `DESIGN.md` §2's own note about `card radius 10–14` is about.
public struct SignalPathGeometry: Sendable, Equatable {
    /// The band's inner padding.
    public let cardPadding: Double

    // The jack.
    /// The grid track's minimum width — the direct translation of `minmax(132px, 1fr)`.
    public let jackMinimum: Double
    public let jackInset: Double
    /// Between the plug and the label column.
    public let jackGap: Double

    // The plug, on a jack and on a row.
    public let plugDiameter: Double
    public let plugRing: Double
    /// The same mark at the size a table row and a legend draw it.
    public let rowPlugDiameter: Double

    // The rail.
    public let hubWidth: Double
    public let flowArrowWidth: Double

    /// How long the plug takes to light or go dark, in seconds.
    ///
    /// `DESIGN.md` §7 authors the app's own motion as springs; this element's motion is the mock's,
    /// stated there as a duration and a curve, and the mock is the design of record.
    public let plugTransitionSeconds: Double

    public static let standard = SignalPathGeometry(
        cardPadding: 12,
        jackMinimum: 132, jackInset: 10, jackGap: 9,
        plugDiameter: 16, plugRing: 3, rowPlugDiameter: 8,
        hubWidth: 76, flowArrowWidth: 20,
        plugTransitionSeconds: 0.2
    )

    // MARK: - Derived

    /// The lane a jack sits on. The mock's own published metric, read rather than restated.
    public var laneHeight: Double { MetricToken.jackLane.leadingScalar }

    /// The gutter between tracks, in both axes. The grid unit, so the field is on the same grid as
    /// everything around it.
    public var gutter: Double { MetricToken.gridUnit.leadingScalar }

    /// What is left of a jack for its name and its condition.
    public var labelWidth: Double {
        jackMinimum - jackInset * 2 - plugDiameter - jackGap
    }

    /// The plug plus both sides of its ring — the mark's real footprint.
    public var plugFootprint: Double { plugDiameter + plugRing * 2 }

    // MARK: - The invariants, as values a test can read

    /// A ring that overflows the lane clips against the track above. This is the outgoing
    /// signature's third failure — a lamp drawn outside its housing — in a new shape.
    public var plugFitsTheLane: Bool { plugFootprint <= laneHeight }

    /// The label column has to be the larger half of the jack, or the countdown clips and the jack
    /// becomes a plug with a name beside it.
    public var theLabelHasRoom: Bool { labelWidth >= jackMinimum / 2 }

    /// A ring at or beyond the plug's own radius reads as a second plug rather than as a halo.
    public var theRingIsThinnerThanThePlug: Bool { plugRing < plugDiameter / 2 }

    // MARK: - Packing, as arithmetic rather than as a hope

    /// How many jacks fit across a field of this width.
    ///
    /// This is CSS `repeat(auto-fill, minmax(jackMinimum, 1fr))` written out: a track plus its
    /// gutter divides the width plus one gutter, because the last track carries no trailing gutter.
    /// `LazyVGrid(columns: [.adaptive(minimum:)])` packs the same way, so this predicts what the
    /// view does rather than describing it.
    ///
    /// It is here rather than in the view because the brief's constraint — *"the rail's gutters are
    /// tight enough that two jacks fit beside an open inspector"* — is a claim about a number, and
    /// a claim only a screenshot can settle is a claim nobody re-checks.
    public func columns(inJackFieldWidth width: Double) -> Int {
        guard width > 0 else { return 1 }
        return max(1, Int((width + gutter) / (jackMinimum + gutter)))
    }

    /// How wide the jack field is inside a board of this width, once the band's padding, the hub,
    /// the arrow and the rail's own gutters are taken out.
    public func jackFieldWidth(inBoardWidth width: Double) -> Double {
        width - cardPadding * 2 - hubWidth - flowArrowWidth - gutter * 2
    }

    // MARK: - Motion, as a decision rather than as a view

    /// How long the plug's transition runs, or `nil` when motion is suppressed.
    ///
    /// A **pure function on purpose**, for the reason `BreakerGeometry.spring(raised:reduceMotion:)`
    /// gave: the choice used to live inside a view body reading `@Environment(\.accessibilityReduceMotion)`,
    /// where it cannot be exercised without a host — so "Reduce Motion removes the animation and
    /// keeps the state change" was a claim no test could settle.
    ///
    /// `nil` removes the *animation*. The state change is applied by the caller regardless, which is
    /// what `DESIGN.md` §7 requires: the motion goes, never the meaning.
    public func plugTransition(reduceMotion: Bool) -> Double? {
        reduceMotion ? nil : plugTransitionSeconds
    }

    // MARK: - Parity

    /// Every dimension, keyed by the name `DESIGN.md` records it under.
    ///
    /// Built from the stored properties rather than written out as a list a test keeps its own copy
    /// of: the parity suite compares this key set against the document's row set in both directions,
    /// so a dimension added here without a row — or a row added without a dimension — is a failure
    /// rather than something nobody notices.
    public var documentedValues: [String: Double] {
        [
            "Signal Path padding": cardPadding,
            "Jack minimum width": jackMinimum,
            "Jack inset": jackInset,
            "Jack gap": jackGap,
            "Jack plug diameter": plugDiameter,
            "Jack plug ring": plugRing,
            "Row plug diameter": rowPlugDiameter,
            "Hub width": hubWidth,
            "Flow arrow width": flowArrowWidth,
            "Plug transition": plugTransitionSeconds
        ]
    }
}
