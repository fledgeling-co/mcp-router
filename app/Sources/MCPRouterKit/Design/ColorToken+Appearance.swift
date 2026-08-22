import Foundation

/// The two base appearances, value by value.
///
/// Split from `ColorToken.swift` for the file-length reason `MockTokenLiterals.swift` gives: forty
/// tokens across four contexts do not fit one file under the 400-line ceiling, and the seam is the
/// obvious one — the enum declares what the palette *is*, this file says what each token *is worth*
/// in the two appearances a user picks between, and `ColorToken+IncreasedContrast.swift` says what
/// changes when they ask for more contrast.
///
/// **Light is authored, never inverted.** What light reproduces is not dark's alpha but its job:
/// the tiers are solid hexes in this direction rather than an alpha over the ground, because a
/// tier that composites is a tier whose contrast changes with whatever surface it lands on, and
/// this palette has seven surfaces. Lines and fills stay `rgba` — a hairline genuinely is a
/// modification of the ground beneath it — so `opacity` remains load-bearing for `--line`,
/// `--line-strong`, `--f1`–`--f3`, `--scrim`, `--jack-ring` and the two accent washes.
public extension ColorToken {
    // MARK: - Dark

    /// The base colour in the dark appearance, always in canonical six-digit upper-case form.
    ///
    /// `DESIGN.md` writes white and black as `#FFF` and `#000`; three-digit and six-digit forms are
    /// the same colour, so the parity test expands both before comparing rather than treating
    /// `#FFF` and `#FFFFFF` as a drift.
    var hex: String {
        switch self {
        case .desktop: "#2A3140"
        case .ground: "#1C1C1E"
        case .chrome: "#262629"
        case .menubar: "#1F1F22"
        case .panel: "#232326"
        case .raised: "#2C2C2E"
        case .raised2, .trafficOff: "#3A3A3C"
        case .sunken: "#161618"
        case .scrim: "#000000"
        case .line, .lineStrong, .f1, .f2, .f3, .jackRing, .t1, .onAccent: "#FFFFFF"
        case .jackOff: "#3C3C40"
        case .trafficClose: "#FF5F57"
        case .trafficMinimise: "#FEBC2E"
        case .trafficZoom: "#28C840"
        case .focus, .focusHalo, .accent: "#0091FF"
        case .accentWash, .accentWashLine: "#0071E3"
        case .t2: "#B8B8C0"
        case .t3: "#98989F"
        case .t4: "#6E6E76"
        case .live, .liveInk: "#30D158"
        case .attention, .attentionInk: "#FF9230"
        case .fail: "#FF4245"
        case .accentInk: "#0A6FD6"
        case .accentText: "#6FB6FF"
        case .failInk: "#FF5A5D"
        case .shieldGood: "#1B7A38"
        case .badgeBackground: "#B85400"
        }
    }

    /// Alpha as a fraction in the dark appearance. `DESIGN.md` states these as percentages (`@9%`).
    var opacity: Double {
        switch self {
        case .scrim: 0.52
        case .line: 0.09
        case .lineStrong, .jackRing: 0.16
        case .f1, .accentWash: 0.10
        case .f2: 0.07
        case .f3: 0.05
        case .focusHalo: 0.42
        case .accentWashLine: 0.22
        default: 1.0
        }
    }

    // MARK: - Light

    /// The base colour in the light appearance, and the primary one: this direction is light-first,
    /// so `:root` in the design of record is this column and dark is the override.
    ///
    /// The four hues are the platform's own published light values rather than re-solved ones, and
    /// that is the whole reason the ink family exists. `--accent` at `#0088FF` measures 3.52:1 on
    /// white — Apple's own blue, under the floor for a 13pt label — so the fix is a second token
    /// with a different job rather than a darker accent that stops being the system colour.
    var lightHex: String {
        switch self {
        case .desktop: "#8A9BB4"
        case .ground, .raised, .onAccent: "#FFFFFF"
        case .chrome: "#F1F1F4"
        case .menubar: "#F6F6F8"
        case .panel: "#F7F7F9"
        // The one direction reversal in the whole system. Emphasis moves *away* from the ground;
        // in light the resting surface is already white, so the only direction left is darker.
        case .raised2: "#E8E8EC"
        case .sunken: "#EDEDF0"
        case .scrim, .line, .lineStrong, .f1, .f2, .f3, .jackRing: "#000000"
        case .jackOff: "#D6D6DC"
        case .trafficClose: "#FF5F57"
        case .trafficMinimise: "#FEBC2E"
        case .trafficZoom: "#28C840"
        case .trafficOff: "#D2D2D6"
        case .focus, .focusHalo, .accent: "#0088FF"
        case .accentWash, .accentWashLine, .accentInk: "#0071E3"
        case .t1: "#17171A"
        case .t2: "#55555C"
        case .t3: "#63636B"
        case .t4: "#9A9AA2"
        case .live: "#34C759"
        case .attention: "#FF8D28"
        case .fail: "#FF383C"
        case .accentText: "#0060C4"
        case .liveInk, .shieldGood: "#14682F"
        case .attentionInk: "#8A5000"
        case .failInk: "#C8102E"
        case .badgeBackground: "#B34700"
        }
    }

    /// Alpha as a fraction in the light appearance.
    ///
    /// These are **not** the dark alphas. A dark hairline on a light ground and a light hairline on
    /// a dark ground are not equally visible at the same opacity, so each value is the one that
    /// reproduces its dark counterpart's separation: `--line` 9% → 10%, `--line-strong` 16% → 18%,
    /// `--f1` 10% → 6%. The scrim moves furthest — 52% → 28% — because a dim room behind a sheet
    /// and a bright one need different amounts of black to read as the same recession.
    var lightOpacity: Double {
        switch self {
        case .scrim: 0.28
        case .line, .accentWash: 0.10
        case .lineStrong: 0.18
        case .f1: 0.06
        case .f2: 0.04
        case .f3: 0.03
        case .jackRing: 0.14
        case .focusHalo: 0.35
        case .accentWashLine: 0.22
        default: 1.0
        }
    }
}
