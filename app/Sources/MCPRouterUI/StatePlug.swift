import MCPRouterKit
import SwiftUI

/// The plug — the app's signature mark, at the two sizes it is drawn.
///
/// One view rather than two, because a legend swatch, a table row's mark and a jack's plug are
/// the same statement about the same server at three sizes. Drawn twice they would be free to
/// disagree, which is how a legend comes to explain a colour the board no longer uses.
///
/// **Colour is never the only signal** (`DESIGN.md` §3 rule 10). This view is deliberately
/// wordless and carries no accessibility label of its own — every caller draws the state's word
/// beside it and owns the label for the pair. A plug that announced itself would put the state
/// in the tree twice, once as a mark and once as a word.
struct StatePlug: View {
    let state: JackState
    /// Whether this is a jack's plug, with its ring, or the bare mark a row and a legend draw.
    var ringed = false

    private var geometry: SignalPathGeometry { .standard }

    private var diameter: Double {
        ringed ? geometry.plugDiameter : geometry.rowPlugDiameter
    }

    /// An unplugged jack is `--jack-off` — a socket rather than a dimmed light. That token
    /// exists for this and for nothing else.
    private var fill: ColorToken {
        state.indicator ?? .jackOff
    }

    /// The ring is the idle countdown's own mark in the mock, and it changes with the state:
    /// `--focus-halo` while something is awake, `--jack-ring` otherwise. Both are `nonText`
    /// roles — a ring never carries a label — so neither is an indicator hue used decoratively.
    private var ring: ColorToken {
        state.isLit ? .focusHalo : .jackRing
    }

    var body: some View {
        Circle()
            .fill(fill.color)
            .frame(width: diameter, height: diameter)
            .overlay {
                if ringed {
                    Circle()
                        .strokeBorder(ring.color, lineWidth: geometry.plugRing)
                        .padding(-geometry.plugRing)
                }
            }
            .accessibilityHidden(true)
    }
}
