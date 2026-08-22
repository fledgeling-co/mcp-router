import Foundation
import Testing
@testable import MCPRouterKit

/// Every colour held to the floor its **role** implies, in all four appearance contexts.
///
/// `DesignTokenParityTests` proves the code and the document say the same thing;
/// `LightAppearanceTests` proves the ratios the document records are the ratios the values measure.
/// Neither asks the question this suite asks: is the palette actually readable.
///
/// **Measured by role, not as a cross-product.** Every token against every ground reports failures
/// that are not failures and hides one that is — `--shield-good` in the dark increased-contrast
/// context measures 2.58:1 against the ground and 6.60:1 under white, because it is a fill and
/// never text. So each token declares one `ContrastRole` and this suite measures the pairing that
/// role implies.
///
/// **Three roles have no floor, and they are printed rather than skipped.** A skipped check and a
/// passed check are the same shade of green, so an ungated role appears in the output as its own
/// claim — the WCAG clause it stands on — with the ratio it actually measures beside it.
@Suite("The contrast floor, measured across four contexts")
struct ContrastFloorTests {
    /// One appearance context, named the way a failure message should read.
    struct Context: Sendable {
        let dark: Bool
        let increasedContrast: Bool
        let name: String
    }

    static let contexts: [Context] = [
        Context(dark: false, increasedContrast: false, name: "light"),
        Context(dark: true, increasedContrast: false, name: "dark"),
        Context(dark: false, increasedContrast: true, name: "light+contrast"),
        Context(dark: true, increasedContrast: true, name: "dark+contrast")
    ]

    /// A token composited over a ground at its own alpha, measured against that ground.
    static func ratio(of token: ColorToken, over ground: ColorToken, in context: Context) -> Double {
        let fore = token.value(dark: context.dark, increasedContrast: context.increasedContrast)
        let back = ground.value(dark: context.dark, increasedContrast: context.increasedContrast)
        return Contrast.ratio(
            Contrast.compositedLuminance(hex: fore.hex, alpha: fore.opacity, over: back.hex),
            Contrast.relativeLuminance(back.hex)
        )
    }

    private static func two(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    /// The tokens carrying a given role, so a role that lost all its members is visible.
    static func tokens(with role: ContrastRole) -> [ColorToken] {
        ColorToken.allCases.filter { $0.contrastRole == role }
    }

    // MARK: - The two gated text floors

    @Test("every text token clears 4.5:1 on all four grounds, in all four contexts")
    func textClearsTheFloorOnEveryGround() {
        let texts = Self.tokens(with: .text)
        #expect(texts.count == 7, "expected 7 text tokens, found \(texts.count)")
        for token in texts {
            for context in Self.contexts {
                for ground in ColorToken.textGrounds {
                    let measured = Self.ratio(of: token, over: ground, in: context)
                    #expect(
                        measured >= 4.5,
                        """
                        \(token.rawValue) on \(ground.rawValue) in \(context.name) measures \
                        \(Self.two(measured)):1, under the 4.5:1 floor its role requires
                        """
                    )
                }
            }
        }
    }

    @Test("every fill clears 4.5:1 under the label it carries, in all four contexts")
    func fillsClearTheFloorUnderTheirLabel() {
        let fills = Self.tokens(with: .fill)
        #expect(fills.count == 3, "expected 3 fill tokens, found \(fills.count)")
        for token in fills {
            for context in Self.contexts {
                let measured = Self.ratio(of: .onAccent, over: token, in: context)
                #expect(
                    measured >= 4.5,
                    """
                    --on-accent over \(token.rawValue) in \(context.name) measures \
                    \(Self.two(measured)):1, under the 4.5:1 floor its role requires
                    """
                )
            }
        }
    }

    /// The third rung, and the one a two-floor table leaves out.
    ///
    /// WCAG 2.2 **1.4.11** asks 3:1 of a graphical object that carries meaning without text. A ring
    /// and a focus indicator are exactly that, and neither belongs under 4.5:1 — so without this
    /// rung `--accent` as a ring and `--focus` fall under no floor at all, and a small drift toward
    /// a lighter blue would ship a real non-text failure with nothing measuring it. The tightest
    /// live pair is `--accent` on light `--chrome` at 3.12:1, which is what makes this a ratchet
    /// rather than a formality.
    @Test("every non-text mark clears the 3:1 rung, in all four contexts")
    func nonTextMarksClearTheirRung() {
        let marks = Self.tokens(with: .nonText)
        #expect(marks.count == 2, "expected 2 non-text tokens, found \(marks.count)")
        for token in marks {
            for context in Self.contexts {
                for ground in ColorToken.textGrounds {
                    let measured = Self.ratio(of: token, over: ground, in: context)
                    #expect(
                        measured >= 3.0,
                        """
                        \(token.rawValue) on \(ground.rawValue) in \(context.name) measures \
                        \(Self.two(measured)):1, under the 3:1 WCAG 1.4.11 rung
                        """
                    )
                }
            }
        }
    }

    // MARK: - The roles that record rather than gate

    /// Every ungated role, printed with its claim and the ratio it actually measures.
    ///
    /// The output is the point. `--live` measures 2.22:1 on the light ground and that is not a
    /// defect — it is a dot beside a word, and §6 requires the word — but a number that appears
    /// nowhere is a number nobody can argue with, and the whole reason the ink twins exist is that
    /// this one is low.
    @Test("the ungated roles are measured and recorded, with the clause each one claims")
    func ungatedRolesAreRecordedRatherThanSkipped() {
        var recorded = 0
        for role in ContrastRole.allCases where role.floor == nil {
            for token in Self.tokens(with: role) {
                guard role != .ground, role != .fillLabel else { continue }
                let readings = Self.contexts.map { context in
                    "\(context.name)=\(Self.two(Self.ratio(of: token, over: .ground, in: context)))"
                }
                print(
                    "CONTRAST-FLOOR-RECORDED: \(token.rawValue) role=\(role.rawValue) "
                        + readings.joined(separator: " ") + " claim=\(role.claim)"
                )
                recorded += 1
            }
        }
        #expect(recorded >= 16, "only \(recorded) ungated tokens were recorded — expected 16+")
    }

    /// The disabled exemption, held to the fact that it is doing work.
    ///
    /// An exemption for a token that would have passed anyway is decoration. `--t4` is genuinely
    /// under the floor in both appearances — 2.79:1 light and 3.37:1 dark on `--ground` — so the
    /// WCAG 1.4.3 claim is load-bearing, and it is claimed by name in `ContrastRole.disabled`
    /// rather than by this suite quietly not measuring it.
    @Test("the disabled exemption is claimed by name and is genuinely load-bearing")
    func theDisabledExemptionIsLoadBearing() {
        let disabled = Self.tokens(with: .disabled)
        #expect(disabled == [.t4], "the disabled role is \(disabled), expected exactly --t4")
        #expect(ContrastRole.disabled.floor == nil)
        #expect(ContrastRole.disabled.claim.contains("1.4.3"))
        for context in Self.contexts {
            let measured = Self.ratio(of: .t4, over: .ground, in: context)
            #expect(
                measured < 4.5,
                """
                --t4 measures \(Self.two(measured)):1 in \(context.name) — it now clears the floor, \
                so the exemption is no longer needed and should be removed rather than kept
                """
            )
        }
    }

    /// The indicator hues, exempt under 1.4.11 because they are never the only carrier.
    ///
    /// The exemption is only honest while §6's rule holds, so this asserts the rule is still in the
    /// document rather than assuming it. If the words go, the exemption goes with them.
    @Test("the indicator hues claim 1.4.11 on a rule the document still states")
    func theIndicatorExemptionRestsOnARuleThatStillExists() throws {
        let url = try DesignDocParser.designDocURL()
        let design = try String(contentsOf: url, encoding: .utf8)
        #expect(
            design.contains("Colour is never the only signal")
                || design.contains("colour is never the only signal")
                || design.contains("every state that has a colour also has a word"),
            """
            DESIGN.md no longer states that colour is never the only signal, so the 1.4.11 \
            exemption on --live, --attn and --fail has nothing behind it
            """
        )
        #expect(Self.tokens(with: .pairedWithAWord) == [.live, .attention, .fail])
        #expect(ContrastRole.pairedWithAWord.claim.contains("1.4.11"))
    }

    // MARK: - The role assignment itself

    /// A role with no members is a role that was quietly emptied, and every one of its floors then
    /// passes vacuously. Nine roles, all populated, and forty tokens across them exactly once.
    @Test("every role has members and every token has exactly one role")
    func theRoleAssignmentIsTotal() {
        var seen: [ColorToken] = []
        for role in ContrastRole.allCases {
            let members = Self.tokens(with: role)
            #expect(
                !members.isEmpty,
                "the \(role.rawValue) role has no tokens — its floor passes vacuously"
            )
            #expect(!role.claim.isEmpty, "the \(role.rawValue) role states no claim")
            seen.append(contentsOf: members)
        }
        #expect(
            seen.count == ColorToken.allCases.count,
            "\(seen.count) role assignments for \(ColorToken.allCases.count) tokens"
        )
        #expect(Set(seen).count == seen.count, "a token appears under two roles")
    }
}
