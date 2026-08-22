import Foundation

/// The two increased-contrast contexts: what `prefers-contrast: more` re-solves, per appearance.
///
/// **Nine of the forty tokens override, and which nine is itself the assertion.** `DESIGN.md` §2's
/// `### Increased contrast` table carries exactly these rows, and
/// `DesignTokenParityTests.contrastOverlayNameSetsMatchExactly` holds the two sets equal in both
/// directions — so a token that starts overriding in code without a documented row is red, and a
/// documented row that overrides nothing is red too.
///
/// **Authored per appearance rather than once.** A single scheme-agnostic override block is the
/// failure mode this shape exists to rule out: `--t2` has to go *darker* in light and *lighter* in
/// dark, so one shared value paints low-contrast ink in whichever of the two it was not written
/// for — the opposite of what the user asked for, in exactly the mode they asked for it.
///
/// The thirty-one tokens that do not override return their base from the `default:` arm of each
/// switch. That is a deliberate arm rather than a computed fallback elsewhere, so the parity test
/// compares four columns for every token and nothing inherits unwatched.
public extension ColorToken {
    // MARK: - Dark + increased contrast

    /// The colour in the dark appearance under `prefers-contrast: more`.
    var contrastHex: String {
        switch self {
        case .t2, .t3: "#F2F2F5"
        case .accentText: "#9CCDFF"
        case .liveInk: "#6BE38B"
        case .attentionInk: "#FFB566"
        case .failInk: "#FF8A8C"
        case .shieldGood: "#166B31"
        default: hex
        }
    }

    /// Alpha in the dark appearance under `prefers-contrast: more`.
    ///
    /// Only the two hairlines move, and they move a long way — 9% → 30% and 16% → 48%. A divider
    /// asked to be higher-contrast cannot get there by changing hue, because it is already white on
    /// graphite; the only axis left is how much of the ground it covers.
    var contrastOpacity: Double {
        switch self {
        case .line: 0.30
        case .lineStrong: 0.48
        default: opacity
        }
    }

    // MARK: - Light + increased contrast

    /// The colour in the light appearance under `prefers-contrast: more`.
    ///
    /// `--t2` and `--t3` collapse onto one value here, in both appearances. That is deliberate and
    /// it is what a contrast request means: the tier separation that distinguishes secondary from
    /// tertiary text is exactly the low-contrast gradation the user has asked to stop paying for,
    /// and hierarchy still reads from weight, position and size.
    var lightContrastHex: String {
        switch self {
        case .t2, .t3: "#2A2A30"
        case .accentText: "#004E9E"
        case .liveInk: "#0F4F24"
        case .attentionInk: "#6B3E00"
        case .failInk: "#9E0C24"
        case .shieldGood: "#0E4F23"
        default: lightHex
        }
    }

    /// Alpha in the light appearance under `prefers-contrast: more`.
    var lightContrastOpacity: Double {
        switch self {
        case .line: 0.30
        case .lineStrong: 0.46
        default: lightOpacity
        }
    }

    /// The pair that will actually be drawn in one of the four contexts.
    ///
    /// One selector rather than four call sites choosing between eight properties: the SwiftUI
    /// binding, the register's mock comparison and the floor test all need the same four-way read,
    /// and three spellings of it would be three places for the axes to get crossed.
    func value(dark: Bool, increasedContrast: Bool) -> (hex: String, opacity: Double) {
        switch (dark, increasedContrast) {
        case (true, false): (hex, opacity)
        case (true, true): (contrastHex, contrastOpacity)
        case (false, false): (lightHex, lightOpacity)
        case (false, true): (lightContrastHex, lightContrastOpacity)
        }
    }

    /// Whether this token re-solves under `prefers-contrast: more` in either appearance.
    ///
    /// The set this reports is the set `DESIGN.md`'s overlay table has to carry, so it is computed
    /// from the values rather than declared as a second list — a declared list could agree with the
    /// document while disagreeing with the values, which is the drift the overlay exists to catch.
    var overridesForIncreasedContrast: Bool {
        contrastHex != hex
            || contrastOpacity != opacity
            || lightContrastHex != lightHex
            || lightContrastOpacity != lightOpacity
    }
}
