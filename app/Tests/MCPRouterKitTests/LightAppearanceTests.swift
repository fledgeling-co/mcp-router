import Foundation
import Testing
@testable import MCPRouterKit

/// The light appearance, held to the claim that it was authored rather than derived.
///
/// Split from `DesignTokenParityTests` because these are a different kind of assertion. That suite
/// proves the code and the document say the same thing; this one proves the values *mean* what the
/// document says they mean — that the ratios recorded per token are the ratios those values
/// actually measure. A palette can agree with its documentation perfectly and still be unreadable.
@Suite("The authored light appearance")
struct LightAppearanceTests {
    private static func documentText() throws -> String {
        let url = try DesignDocParser.designDocURL()
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Two decimal places, so a failure message reads like the document it disagrees with.
    private static func two(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// The six tokens that are legitimately identical in both appearances, exempted **by name**.
    ///
    /// The list used to hold `--onAccent` alone, with its own docstring arguing that a blanket
    /// exemption nothing currently relies on is a hole waiting for the value that walks into it.
    /// Growing the palette to forty is that value walking in, so the list grows by name and with a
    /// reason each rather than by relaxing the rule.
    ///
    /// - `--on-accent` is white in every context, because every native filled accent control on
    ///   macOS carries a white label.
    /// - The three traffic lights are the system's own hues, which do not change with appearance on
    ///   the platform itself.
    /// - The two accent washes are a 10% and a 22% tint of `--accent-ink`; a tint is defined by what
    ///   it modifies, so the ground underneath does the appearance-switching for it.
    ///
    /// The design of record authors all six once in `:root` and re-declares none of them in its
    /// dark block, so this is the cascade's own answer rather than a value invented here.
    static let sameInBothAppearances: [ColorToken] = [
        .onAccent, .trafficClose, .trafficMinimise, .trafficZoom, .accentWash, .accentWashLine
    ]

    /// The authored-not-inverted claim, asserted rather than asserted-about.
    ///
    /// If light were an inversion, every token would differ from its dark counterpart by a
    /// mechanical rule. It is not. This test holds the two properties that would break first if
    /// someone "simplified" light into a flip.
    @Test("light is authored, not derived from dark")
    func lightIsAuthored() {
        for token in ColorToken.allCases where !Self.sameInBothAppearances.contains(token) {
            #expect(
                !(token.hex == token.lightHex && token.opacity == token.lightOpacity),
                "\(token.rawValue) is identical in both appearances — light was not authored for it"
            )
        }
        // The four indicator hues must be genuinely different colours, not the same hue dimmed:
        // reused unchanged they measure 2.22–3.57:1 on the light ground, against 4.5:1 for a label.
        for token in [ColorToken.accent, .live, .attention, .fail] {
            #expect(
                token.hex != token.lightHex,
                "\(token.rawValue) reuses its dark value in light, where it is unreadable"
            )
        }
    }

    /// The same claim one axis further in: increased contrast is authored per appearance.
    ///
    /// A token that re-solves must re-solve in **both** appearances, because the whole reason the
    /// design of record carries two `prefers-contrast` blocks rather than one is that a single
    /// shared override paints low-contrast ink in whichever appearance it was not written for.
    /// Nine tokens override; each is checked in both directions.
    @Test("increased contrast is authored per appearance, not once for both")
    func increasedContrastIsAuthoredPerAppearance() {
        let overriding = ColorToken.allCases.filter(\.overridesForIncreasedContrast)
        #expect(overriding.count == 9, "expected 9 overriding tokens, found \(overriding.count)")
        for token in overriding {
            #expect(
                !(token.contrastHex == token.hex && token.contrastOpacity == token.opacity),
                "\(token.rawValue) re-solves in light only — dark inherits, which is the failure"
            )
            #expect(
                !(token.lightContrastHex == token.lightHex
                    && token.lightContrastOpacity == token.lightOpacity),
                "\(token.rawValue) re-solves in dark only — light inherits, which is the failure"
            )
        }
        // And the other thirty-one genuinely take their base, rather than a value nobody checked.
        for token in ColorToken.allCases where !token.overridesForIncreasedContrast {
            for dark in [true, false] {
                #expect(
                    token.value(dark: dark, increasedContrast: true)
                        == token.value(dark: dark, increasedContrast: false),
                    "\(token.rawValue) reports no override but resolves differently under contrast"
                )
            }
        }
    }

    /// The exemptions above, held to their reasons.
    ///
    /// Asserting them positively is what stops an exemption from becoming a place a token can
    /// quietly change: without this, `--on-accent` could drift to any value at all — in every
    /// context at once — and every test here would stay green.
    @Test("each token exempt from the authored-per-appearance rule is exempt for its stated reason")
    func theExemptionsHoldTheirReasons() {
        for token in Self.sameInBothAppearances {
            #expect(
                token.hex == token.lightHex && token.opacity == token.lightOpacity,
                "\(token.rawValue) is on the exemption list but its two appearances now differ"
            )
        }
        // `--on-accent` is white specifically, not merely the same twice.
        #expect(ColorToken.onAccent.hex == "#FFFFFF")
        #expect(ColorToken.onAccent.lightHex == "#FFFFFF")
        #expect(ColorToken.onAccent.opacity == 1.0)
        #expect(ColorToken.onAccent.lightOpacity == 1.0)
        // The two washes are a tint of the accent fill, which is what makes the ground do the work.
        for wash in [ColorToken.accentWash, .accentWashLine] {
            #expect(wash.hex == ColorToken.accentInk.lightHex, "\(wash.rawValue) is no longer an accent tint")
            #expect(wash.opacity < 1.0, "\(wash.rawValue) is opaque, so it is a fill rather than a wash")
        }
    }

    /// The one direction reversal in the system, pinned so it cannot be "fixed" by someone
    /// making light consistent with dark.
    ///
    /// Measured with real relative luminance rather than the red byte. The byte was a stand-in that
    /// happens to order these four correctly, but it ranks `#00FF00` below `#800000` — so a future
    /// pair with ordered red channels and reversed actual luminance would have passed.
    @Test("emphasis moves away from the ground: lighter in dark, darker in light")
    func hoverPolarityReverses() {
        #expect(
            Contrast.relativeLuminance(ColorToken.raised2.hex)
                > Contrast.relativeLuminance(ColorToken.raised.hex),
            "in dark, the emphasized surface must be lighter than the resting one"
        )
        #expect(
            Contrast.relativeLuminance(ColorToken.raised2.lightHex)
                < Contrast.relativeLuminance(ColorToken.raised.lightHex),
            "in light, the resting surface is white, so emphasis can only darken"
        )
    }

    /// The authored-light claim, as a measurement.
    ///
    /// Triage's binding assumption is that light reproduces dark's *measured contrast*, not its
    /// opacity numbers — copying the alphas lands somewhere else entirely. That claim was recorded
    /// in `DESIGN.md` as a ratio per token and then checked by nobody: the parity suite compared
    /// hexes and alphas, so the column stating what those values are *for* was documentation the
    /// gate never opened.
    ///
    /// This computes the WCAG 2.x ratio from the shipped values and holds it to the documented one.
    /// It therefore fails in both useful directions: a value edited without re-measuring, and a
    /// ratio written down that the value never actually had.
    ///
    /// **Both columns, because light is now the primary appearance.** A ratio documented in one
    /// direction is a ratio checked in one direction, and the palette this replaced carried its
    /// measurement for light only while dark was the shipped appearance.
    ///
    /// Tolerance is 0.05 — the document records two decimal places, and the arithmetic that
    /// produced them rounds. Anything looser would admit a real regression.
    @Test("every documented contrast ratio is the one the shipped value actually measures")
    func contrastRatiosMatchTheDocument() throws {
        let rows = try DesignDocParser.colorRows(in: Self.documentText())
        var checked = 0

        for row in rows {
            // `--on-accent` is the label drawn *on* an accent fill, so it is the one token measured
            // against something other than the window ground. It is measured on `--accent` rather
            // than on `--accent-ink` deliberately: `--accent` is the fill this app still draws
            // under it, and the column has to report the pairing that ships.
            let onAccent = row.name == ColorToken.onAccent.rawValue
            for dark in [true, false] {
                let documented = dark ? row.documentedDarkContrast : row.documentedLightContrast
                guard let documented else { continue }
                let background = onAccent
                    ? ColorToken.accent.value(dark: dark, increasedContrast: false).hex
                    : ColorToken.ground.value(dark: dark, increasedContrast: false).hex
                let measured = Contrast.ratio(
                    Contrast.compositedLuminance(
                        hex: dark ? row.hex : row.lightHex,
                        alpha: dark ? row.opacity : row.lightOpacity,
                        over: background
                    ),
                    Contrast.relativeLuminance(background)
                )
                #expect(
                    abs(measured - documented) <= 0.05,
                    """
                    \(row.name) \(dark ? "dark" : "light") measures \(Self.two(measured)):1, \
                    document says \(documented):1
                    """
                )
                checked += 1
            }
        }

        // A parser change that stopped finding either column would otherwise turn this into a test
        // that checks nothing and reports success. Thirty-nine of the forty tokens carry a ratio in
        // both appearances — `--ground` is what the others are measured against and has none.
        #expect(checked == 78, "\(checked) documented ratios were checked — expected 78")
    }

    /// The deviation that is recorded *against* us, **ported rather than replaced**.
    ///
    /// `--on-accent` on `--accent` measures 3.23:1 in dark and 3.52:1 in light — both under the
    /// 4.5:1 a 13pt semibold label wants. It stands because every native filled accent control on
    /// macOS carries a white label and the kit wins where it and `DESIGN.md` disagree.
    ///
    /// **This test nearly did not survive M21, and the reason it did is the point.** The plan
    /// proposed replacing it with an assertion about `--accent-ink`, on the grounds that the split
    /// resolves the shortfall. It resolves it *in the palette*: M21 authored `--accent-ink` and
    /// migrated no call site, so `--accent` is still the fill under `--on-accent` on every surface
    /// until M16–M22 move them. Deleting this would have removed the only automated measurement of
    /// the pairing that actually ships, during exactly the window it still ships in.
    @Test("the onAccent shortfall is still exactly the shortfall that was accepted")
    func darkOnAccentDeviationIsPinned() {
        for (dark, expected) in [(true, 3.23), (false, 3.52)] {
            let label = ColorToken.onAccent.value(dark: dark, increasedContrast: false)
            let fill = ColorToken.accent.value(dark: dark, increasedContrast: false)
            let measured = Contrast.ratio(
                Contrast.relativeLuminance(label.hex),
                Contrast.relativeLuminance(fill.hex)
            )
            let name = dark ? "dark" : "light"
            #expect(
                abs(measured - expected) <= 0.05,
                "\(name) onAccent measures \(Self.two(measured)):1; \(expected):1 was the accepted deviation"
            )
            #expect(measured < 4.5, "\(name) is recorded as a shortfall; it is no longer one")
        }
    }

    /// The resolution the split makes available, measured — and named as not yet applied.
    ///
    /// `--accent-ink` is the fill the design of record puts under a white label, and it clears the
    /// floor in both appearances. Asserting it here is what makes the claim in `DESIGN.md` §2 a
    /// measurement rather than a promise, and what will keep it true when a surface finally takes
    /// it.
    @Test("the accent fill that carries text clears the floor in both appearances")
    func accentInkClearsTheFloorUnderItsLabel() {
        for (dark, expected) in [(true, 4.93), (false, 4.70)] {
            let fill = ColorToken.accentInk.value(dark: dark, increasedContrast: false)
            let label = ColorToken.onAccent.value(dark: dark, increasedContrast: false)
            let measured = Contrast.ratio(
                Contrast.compositedLuminance(hex: label.hex, alpha: label.opacity, over: fill.hex),
                Contrast.relativeLuminance(fill.hex)
            )
            let name = dark ? "dark" : "light"
            #expect(
                abs(measured - expected) <= 0.05,
                "\(name) on-accent over accent-ink measures \(Self.two(measured)):1, expected \(expected):1"
            )
            #expect(measured >= 4.5, "\(name) accent-ink no longer clears the floor under its label")
        }
    }
}
