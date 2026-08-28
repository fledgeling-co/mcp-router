#if os(macOS)
    import SwiftUI
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// The two button styles' state palettes, asserted without a render.
    ///
    /// `DESIGN.md`:517 — *"Every control additionally carries default / hover / focus-visible /
    /// active / disabled"* — and :443 — *"Disabled dims in place and never disappears"*. The
    /// prominent style shipped with **no disabled treatment at all**: it painted `--on-accent` on an
    /// unconditional `--accent` fill, so a disabled primary was pixel-identical to a live one. That
    /// is the defect these tests exist to keep closed, and it is the shape a compile never catches.
    @MainActor
    @Suite("Button state palettes")
    struct ButtonPaletteTests {
        private let prominent = ProminentButtonStyle()
        private let standard = StandardButtonStyle()

        @Test("a live prominent button is the accent fill under its own label, with no bezel")
        func liveProminentIsTheAccentFill() {
            let live = prominent.palette(isEnabled: true)
            #expect(live.label == .onAccent)
            #expect(live.fill == .accent)
            #expect(live.border == nil, "the live prominent button is a flat accent fill (§3.4)")
        }

        @Test("a disabled prominent button drops to the disabled bezelled surface")
        func disabledProminentDims() {
            let off = prominent.palette(isEnabled: false)
            #expect(off.label == .t4)
            #expect(off.fill == .f3)
            #expect(off.border == .line)
        }

        /// The regression itself, stated as a difference rather than as two values.
        ///
        /// Written this way on purpose: asserting the disabled tokens alone would still pass if
        /// someone later made the *live* palette identical to them. What went wrong here was that
        /// the two states were the same, so that is what is asserted.
        @Test("the two states differ in every slot, so a disabled primary cannot read as live")
        func theTwoStatesAreDistinguishable() {
            let live = prominent.palette(isEnabled: true)
            let off = prominent.palette(isEnabled: false)
            #expect(live.label != off.label, "a disabled primary carries the live label tier")
            #expect(live.fill != off.fill, "a disabled primary carries the live fill")
            #expect(live != off)
        }

        /// The exemption claimed by name, at this call site rather than in general.
        ///
        /// `--t4` measures 3.37:1 dark and 2.79:1 light (`DESIGN.md` §2) and is under the 4.5:1
        /// floor in both. It is admissible here **only** because its role is `disabled`, which
        /// carries `floor == nil` and cites WCAG 1.4.3's inactive-control clause;
        /// `ContrastFloorTests.theDisabledExemptionIsLoadBearing` is what keeps that honest by
        /// failing if `--t4` ever clears the floor and the exemption stops being needed. This
        /// asserts that the token this style reaches for is the one that carries the exemption,
        /// rather than some other dim tier borrowed by eye.
        @Test("the disabled tier is the token that carries the exemption, not a borrowed dim")
        func theDisabledTierClaimsItsExemption() {
            #expect(prominent.palette(isEnabled: false).label == .t4)
            #expect(ColorToken.t4.contrastRole == .disabled)
            #expect(ContrastRole.disabled.floor == nil)
            #expect(ContrastRole.disabled.claim.contains("1.4.3"))
        }

        /// `--accent` is a reserved indicator meaning; a disabled control must not keep it.
        @Test("a disabled prominent button surrenders the reserved accent fill")
        func disabledSurrendersTheReservedHue() {
            let off = prominent.palette(isEnabled: false)
            #expect(
                !off.fill.isReservedMeaning,
                "a disabled control kept \(off.fill), which is reserved for a live meaning (§2)"
            )
        }

        // MARK: - The phone rung

        /// M36. The phone's prominent style spelled its own triple and drifted: `--raised` for the
        /// disabled fill where §3 ratifies `--f3`, and no bezel where §3 gives `--line`. It reads
        /// this palette now, so the assertion is that the two ladders are one decision rather than
        /// two lists that happen to agree today — a second list is what drifted.
        ///
        /// `PhoneProminentDisabledRenderTests` is the other half, and the halves are not
        /// interchangeable: this says which token was chosen, that says which colour was painted.
        @Test("the phone's prominent rung resolves the same triple as the Mac's")
        func thePhoneRungIsTheSameLadder() {
            let phone = PhoneProminentButtonStyle()
            for isEnabled in [true, false] {
                #expect(
                    phone.palette(isEnabled: isEnabled) == prominent.palette(isEnabled: isEnabled),
                    "the phone and Mac prominent ladders disagree at isEnabled=\(isEnabled)"
                )
            }
            #expect(phone.palette(isEnabled: false).fill == .f3)
            #expect(phone.palette(isEnabled: false).border == .line)
        }

        // MARK: - The standard style

        @Test("the standard style's disabled tier wins over the destructive tier")
        func disabledBeatsDestructive() {
            #expect(standard.labelColour(isEnabled: false, role: .destructive) == .t4)
            #expect(standard.labelColour(isEnabled: false, role: nil) == .t4)
        }

        /// The other half of the destructive treatment: the label was moved to the role by M18 and
        /// the **fill** was left, so the control still painted `--raised` behind it — in the light
        /// appearance `#FFFFFF` on a `--panel` sheet ground, a second filled button on a surface the
        /// brief allows one on. `MockButtonFidelityTests` is what ties the `nil` here to
        /// `.btn.destructive{…background:none…}` in the mock rather than to a reading of it.
        @Test("a live destructive button is unfilled, and every other standard button is not")
        func destructiveIsUnfilled() {
            #expect(standard.fill(role: .destructive, isPressed: false) == nil)
            #expect(standard.fill(role: nil, isPressed: false) == .raised)
        }

        /// Pressed is `--f1` for the destructive control — the mock's own `:hover` fill, standing in
        /// for a press a `ButtonStyle` cannot observe. Asserted as a *difference* rather than as two
        /// values, for `theTwoStatesAreDistinguishable`'s reason: a press with no visible change is
        /// the defect, not a particular token.
        @Test("a pressed button changes its fill in every role")
        func pressedChangesTheFill() {
            for role in [ButtonRole.destructive, nil] {
                let named = role.map(String.init(describing:)) ?? "plain"
                #expect(
                    standard.fill(role: role, isPressed: true) != standard.fill(role: role, isPressed: false),
                    "a pressed \(named) button paints what a resting one does"
                )
            }
            #expect(standard.fill(role: .destructive, isPressed: true) == .f1)
            #expect(standard.fill(role: nil, isPressed: true) == .raised2)
        }

        @Test("a live destructive label is the text-safe ink, never the indicator hue")
        func destructiveUsesTheInk() {
            #expect(standard.labelColour(isEnabled: true, role: .destructive) == .failInk)
            #expect(standard.labelColour(isEnabled: true, role: nil) == .t1)
            #expect(
                ColorToken.failInk.contrastRole == .text,
                "the destructive label tier is no longer a text role"
            )
            #expect(
                ColorToken.fail.contrastRole != .text,
                "--fail became a text role, so the ink/hue distinction this style rests on is gone"
            )
        }
    }
#endif
