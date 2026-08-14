import MCPRouterKit
import SwiftUI

/// The phone layout's spacing scale, and **the only file under `Phone/` allowed to write one**.
///
/// The same argument the design system makes for `ColorToken+SwiftUI.swift` and
/// `TypeToken+SwiftUI.swift`: a value has to be written down somewhere, so it is written down in one
/// readable place and forbidden everywhere else. `PhoneSourceGuardTests` enforces that, and the
/// exemption is this file by name rather than by pattern.
///
/// It is a separate scale from `MetricToken` rather than an extension of it because `MetricToken`
/// carries **macOS chrome geometry** — titlebar, sidebar, the control ladder — which `DESIGN.md`
/// marks `(specified)` against Apple's macOS kit. A phone has no titlebar and no sidebar, and
/// stretching those values over an iOS layout would be exactly the "Mac app's chrome on a phone"
/// the brief rules out. Where a value *does* have a token — radii, control heights — this reads the
/// token instead of restating it.
enum PhoneMetric {
    /// The 44pt minimum touch target. Not a taste value: it is the floor every interactive element
    /// in this feature is asserted against.
    static let minimumTarget: Double = 44

    /// Row height for a list row carrying a tile, a title and a subtitle. Equal to `minimumTarget`
    /// so a row is always tappable, and **the skeleton uses this same constant** — which is what
    /// stops the board jumping when data lands.
    static let row: Double = 44

    /// The tile a row carries. `DESIGN.md` §4: row tiles are 30pt at radius 7.
    static let tile: Double = 30
    static let tileRadius: Double = 7

    // Spacing scale. Four steps, because a layout with nine spacings has none.
    static let tight: Double = 4
    static let snug: Double = 8
    static let normal: Double = 12
    static let loose: Double = 16
    static let section: Double = 24

    /// Card and banner radius. Concentric with the tile per `DESIGN.md` §2.
    static let cardRadius: Double = 11

    /// A control's corner radius at the phone's touch height.
    ///
    /// Derived rather than picked, using the exact formula `ControlScale` applies on the Mac —
    /// `selectionRadius × (height / 32)` — so a phone control and a Mac control are the same shape
    /// rule evaluated at two heights, not two unrelated radii that happen to look similar.
    static let controlRadius: Double =
        MetricToken.selectionRadius.leadingScalar * (minimumTarget / 32)

    /// A control's horizontal padding, read from the same token the Mac ladder reads.
    static let controlPadding: Double = MetricToken.selectionInset.leadingScalar * 2

    /// The code field's boxes.
    static let codeBox: Double = 34
    static let codeBoxHeight: Double = 44
    static let codeBoxRadius: Double = 8

    /// The scanner viewfinder.
    static let finder: Double = 210
    static let finderRadius: Double = 18
    static let bracket: Double = 26
    static let bracketWeight: Double = 2

    /// The illustration glyph in an empty or awaiting state.
    static let emptyGlyph: Double = 34

    /// The success mark.
    static let successMark: Double = 40

    /// The connection banner's dot.
    static let dot: Double = 8

    /// Hairline width. A hairline is a hairline; the *colour* carries the weight, per §2.
    static let hairline: Double = 1

    /// The two skeleton bars, sized so the loading row reads as the row it replaces rather than as
    /// two arbitrary rectangles. Named rather than written as a fraction at the call site, because
    /// `finder / 2` is a geometry value wearing a division sign.
    static let skeletonTitle: Double = 105
    static let skeletonSubtitle: Double = 70

    /// The tinted card's border strength.
    ///
    /// The design representation carries `--attnWash` at 8% and `--attnLine` at 28% for exactly
    /// this card. Neither made it into `ColorToken` when F2 ported the palette, and adding them is
    /// a change to a shared surface rather than this feature's — so the border alpha lives here,
    /// traced to the value it came from, and the missing tokens are reported instead.
    static let tintedBorderOpacity: Double = 0.28

    /// The wash behind a tinted card, the other half of the pair above.
    static let tintedWashOpacity: Double = 0.08

    // MARK: - Discover (I2)

    /// The detail tile. `DESIGN.md` §4: detail tiles are 64pt at radius 14.
    static let detailTile: Double = 64
    static let detailTileRadius: Double = 14

    /// A fact chip's height.
    ///
    /// Half the touch target, and derived rather than picked: a chip is **not** interactive — it
    /// states a fact about the entry — so the 44pt floor does not apply to it, and half is the one
    /// relation to the floor that says "deliberately not a control".
    static let chipHeight: Double = minimumTarget / 2

    /// A chip's corner radius, from the same formula `controlRadius` uses, evaluated at the chip's
    /// height. One shape rule at three heights rather than three unrelated radii.
    static let chipRadius: Double =
        MetricToken.selectionRadius.leadingScalar * (chipHeight / 32)

    /// The capability plate is a card, so it takes the card radius.
    static let plateRadius: Double = cardRadius

    /// The invocation block sits inside the plate. `DESIGN.md` §2: concentric corners throughout —
    /// child radius = parent radius − padding.
    static let invocationRadius: Double = plateRadius - tight
}
