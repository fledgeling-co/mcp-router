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

    /// The authored-not-inverted claim, asserted rather than asserted-about.
    ///
    /// If light were an inversion, every token would differ from its dark counterpart by a
    /// mechanical rule. It is not: the four indicator hues are re-solved, and the tiers carry
    /// different alphas precisely so they land on the same *measured ratio*. This test holds the
    /// two properties that would break first if someone "simplified" light into a flip.
    ///
    /// `--onAccent` is the one token that is legitimately identical in both, and it is exempted by
    /// name rather than by a rule — the exemption list used to also carry `--raised`, which is
    /// `#2C2C2E` dark and `#FFFFFF` light and so never needed it. A blanket exemption nothing
    /// currently relies on is a hole waiting for the value that walks into it.
    @Test("light is authored, not derived from dark")
    func lightIsAuthored() {
        for token in ColorToken.allCases where token != .onAccent {
            #expect(
                !(token.hex == token.lightHex && token.opacity == token.lightOpacity),
                "\(token.rawValue) is identical in both appearances — light was not authored for it"
            )
        }
        // The four indicator hues must be genuinely different colours, not the same hue dimmed:
        // reused unchanged they measure 1.71–2.91:1 on the light ground, against 4.5:1 for a label.
        for token in [ColorToken.accent, .live, .attention, .fail] {
            #expect(
                token.hex != token.lightHex,
                "\(token.rawValue) reuses its dark value in light, where it is unreadable"
            )
        }
    }

    /// The exemption above, held to its reason.
    ///
    /// `--onAccent` is white in *both* appearances because every native filled accent control on
    /// macOS carries a white label. Asserting it positively is what stops the exemption from
    /// becoming a place a token can quietly change: without this, `--onAccent` could drift to any
    /// value at all — in both appearances at once — and every test here would stay green.
    @Test("onAccent is white in both appearances, which is why it is exempt")
    func onAccentIsWhiteInBoth() {
        #expect(ColorToken.onAccent.hex == "#FFFFFF")
        #expect(ColorToken.onAccent.lightHex == "#FFFFFF")
        #expect(ColorToken.onAccent.opacity == 1.0)
        #expect(ColorToken.onAccent.lightOpacity == 1.0)
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
    /// It therefore fails in both useful directions: a light value edited without re-measuring, and
    /// a ratio written down that the value never actually had.
    ///
    /// Tolerance is 0.05 — the document records two decimal places, and the arithmetic that
    /// produced them rounds. Anything looser would admit a real regression; the largest live
    /// divergence is 0.02.
    @Test("every documented light contrast ratio is the one the shipped value actually measures")
    func lightContrastMatchesTheDocument() throws {
        let rows = try DesignDocParser.colorRows(in: Self.documentText())
        let ground = ColorToken.ground.lightHex
        var checked = 0

        for row in rows {
            guard let documented = row.documentedLightContrast else { continue }
            // `--onAccent` is the label drawn *on* the accent fill, so it is the one token measured
            // against something other than the window ground.
            let background = row.name == ColorToken.onAccent.rawValue
                ? ColorToken.accent.lightHex
                : ground
            let measured = Contrast.ratio(
                Contrast.compositedLuminance(
                    hex: row.lightHex,
                    alpha: row.lightOpacity,
                    over: background
                ),
                Contrast.relativeLuminance(background)
            )
            #expect(
                abs(measured - documented) <= 0.05,
                "\(row.name) light measures \(Self.two(measured)):1, document says \(documented):1"
            )
            checked += 1
        }

        // A parser change that stopped finding the column would otherwise turn this into a test
        // that checks nothing and reports success.
        #expect(checked >= 17, "only \(checked) tokens carried a documented ratio — expected 17+")
    }

    /// The deviation that is recorded *against* us, held to its number.
    ///
    /// `--onAccent` on `--accent` measures 3.23:1 in dark — under the 4.5:1 a 13pt semibold label
    /// wants. It stands because every native filled accent control on macOS carries a white label
    /// and the kit wins where it and this document disagree. Asserting the measurement is what
    /// keeps it a *known* deviation rather than one that quietly drifts further.
    @Test("the dark onAccent shortfall is still exactly the shortfall that was accepted")
    func darkOnAccentDeviationIsPinned() {
        let measured = Contrast.ratio(
            Contrast.relativeLuminance(ColorToken.onAccent.hex),
            Contrast.relativeLuminance(ColorToken.accent.hex)
        )
        #expect(
            abs(measured - 3.23) <= 0.05,
            "dark onAccent measures \(Self.two(measured)):1; 3.23:1 was the accepted deviation"
        )
        #expect(measured < 4.5, "the deviation is recorded as a shortfall; it is no longer one")
    }
}
