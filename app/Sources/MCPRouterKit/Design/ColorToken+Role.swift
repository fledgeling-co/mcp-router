import Foundation

/// What job a colour does, and therefore which pair its contrast has to be measured as.
///
/// A cross-product of every token against every ground reports failures that are not failures and
/// hides one that is. `--shield-good` in the dark increased-contrast context measures 2.58:1
/// against the ground and 6.60:1 under white, because it is a fill and never text — read as text it
/// is a defect, read as what it is it is comfortable. So each token declares one role and
/// `ContrastFloorTests` measures the pairing that role implies.
///
/// Two of the roles have no floor. They are named cases carrying the clause they claim rather than
/// rows the test quietly skips, because a skipped check and a passed check are the same shade of
/// green — which is the failure this whole shape exists to avoid.
public enum ContrastRole: String, Sendable, CaseIterable {
    /// Text on a ground. Measured against `--ground`, `--chrome`, `--panel` and `--raised` in the
    /// same appearance context.
    case text

    /// A filled surface that carries `--on-accent`. Measured with white composited over it.
    case fill

    /// The label drawn on a fill. It has no measurement of its own here because every pair it
    /// takes part in is already measured from the `fill` side; measuring both ends would report
    /// the same ratio twice and make the census look like twice the coverage it is.
    case fillLabel

    /// A ring, plug, dot or border that carries meaning but no text. WCAG 2.2 **1.4.11**
    /// (non-text contrast) asks 3:1 of these, not 4.5:1.
    case nonText

    /// An indicator hue that never carries its meaning alone. `DESIGN.md` §6 and §2 require a word
    /// beside every state that has a colour, and **1.4.11** reaches a graphical object only where
    /// it is *required* to understand the content — so these are measured and recorded rather than
    /// gated. Recorded, because the ratio is the reason the ink twins exist: on the light ground
    /// `--live` measures 2.22:1 and `--attn` 2.31:1, which is a fine dot and an unreadable label.
    case pairedWithAWord

    /// Text dimmed because the control is unavailable. **Exempt under WCAG 2.2 1.4.3**, which does
    /// not apply to text that is part of an inactive user interface component. Claimed here by
    /// name so a reader sees the claim rather than an absent row.
    case disabled

    /// A hairline, a track or a wash — a modification of the ground rather than a mark on it. The
    /// ratio is recorded rather than gated: there is no floor a 6%-alpha fill is supposed to clear,
    /// and inventing one would either be unmeetable or meaningless.
    case hairline

    /// The tonal ladder itself. These *are* the background other things are measured against, so
    /// they have no pair of their own.
    case ground

    /// Painted furniture that carries neither text nor a label — the scrim, an unplugged jack, the
    /// window's own three buttons at the system's hues.
    case chrome

    /// The ratio this role requires, or nil where the role records rather than gates.
    public var floor: Double? {
        switch self {
        case .text, .fill: 4.5
        case .nonText: 3.0
        case .fillLabel, .pairedWithAWord, .disabled, .hairline, .ground, .chrome: nil
        }
    }

    /// Why a role with no floor has none, in the words of the clause it stands on. Printed by the
    /// floor test so an ungated role appears in the output as a claim rather than as silence.
    public var claim: String {
        switch self {
        case .text: "4.5:1 — WCAG 1.4.3, text on its ground"
        case .fill: "4.5:1 — WCAG 1.4.3, --on-accent composited over the fill"
        case .nonText: "3:1 — WCAG 1.4.11, a mark that carries meaning without text"
        case .fillLabel: "measured from the fill side; both ends would be the same ratio twice"
        case .pairedWithAWord: "WCAG 1.4.11 exempt — never the only carrier of its meaning (DESIGN.md §6)"
        case .disabled: "WCAG 1.4.3 exempt — text in an inactive component"
        case .hairline: "no floor applies to a modification of the ground; the ratio is recorded"
        case .ground: "the background other tokens are measured against"
        case .chrome: "neither a text nor a fill pair"
        }
    }
}

public extension ColorToken {
    /// The one job this colour does, and so the pairing its contrast is measured as.
    ///
    /// Declared on the token rather than kept in the test file, so the role is a contract the
    /// document and the suite can both read. It is also the machine-readable answer to the naming
    /// trap in `--accent-ink`: the suffix says "ink" and the role says `fill`, and the role is the
    /// one with a measurement behind it.
    var contrastRole: ContrastRole {
        switch self {
        case .t1, .t2, .t3, .accentText, .liveInk, .attentionInk, .failInk: .text
        case .accentInk, .shieldGood, .badgeBackground: .fill
        case .onAccent: .fillLabel
        case .accent, .focus: .nonText
        case .live, .attention, .fail: .pairedWithAWord
        case .t4: .disabled
        case .line, .lineStrong, .f1, .f2, .f3: .hairline
        case .jackRing, .accentWash, .accentWashLine, .focusHalo: .hairline
        case .desktop, .ground, .chrome, .menubar, .panel, .raised, .raised2, .sunken: .ground
        case .scrim, .jackOff, .trafficOff: .chrome
        case .trafficClose, .trafficMinimise, .trafficZoom: .chrome
        }
    }

    /// The four surfaces a label can land on, in the order the document lists them. The floor test
    /// measures every `text` token against all four rather than against `--ground` alone, because
    /// the ground is the most forgiving of them and a check that only reads the easy pair reports
    /// a floor the app does not actually hold.
    static var textGrounds: [ColorToken] { [.ground, .chrome, .panel, .raised] }
}
