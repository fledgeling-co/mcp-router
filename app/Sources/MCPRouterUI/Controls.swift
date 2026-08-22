import MCPRouterKit
import SwiftUI

/// The control ladder from `DESIGN.md` §2, as a type rather than as five numbers.
///
/// The document lists Mini 16 · Small 20 · Regular 24 · Large 28 · XL 36. Those used to be one
/// prose cell that the parity check could not read, and a value no check can read is a value that
/// drifts — so they are individual rows now and individual `MetricToken` cases, and this ladder
/// reads them rather than restating them. Nothing here is a literal.
public enum ControlScale: String, CaseIterable, Sendable {
    case mini, small, regular, large, extraLarge

    /// The documented metric this rung takes its height from.
    public var metric: MetricToken {
        switch self {
        case .mini: .controlMini
        case .small: .controlSmall
        case .regular: .controlRegular
        case .large: .controlLarge
        case .extraLarge: .controlExtraLarge
        }
    }

    /// The control's height in points, straight from the design authority.
    public var height: Double { metric.leadingScalar }

    /// The type role that sits inside a control of this size.
    ///
    /// `DESIGN.md` §3.5 is explicit that hierarchy comes from label tiers and weight, never from
    /// size inflation — so the ladder narrows to three roles across five sizes rather than giving
    /// every rung its own.
    public var labelRole: TypeToken {
        switch self {
        case .mini: .subheadline
        case .small: .callout
        case .regular, .large: .body
        case .extraLarge: .title3
        }
    }

    /// Horizontal padding, held to the selection inset so controls and selection share one rhythm.
    public var horizontalPadding: Double { MetricToken.selectionInset.leadingScalar * 2 }

    /// Concentric corners: `DESIGN.md` §2 closes on "child radius = parent radius − padding", and a
    /// control's own radius scales with its height rather than being picked per rung.
    public var cornerRadius: Double { MetricToken.selectionRadius.leadingScalar * (height / 32) }
}

// MARK: - Selection

public extension View {
    /// The sidebar and list selection treatment.
    ///
    /// `DESIGN.md` §3 rule 1: "Selection is a flat inset rounded fill with accent text — never a
    /// full-bleed bar." The inset is what makes it not-full-bleed, so it is applied as real
    /// horizontal padding on the fill rather than as a visual trick — a fill drawn edge to edge
    /// with a rounded corner still reads as a bar.
    ///
    /// **Where this departs from the prototype, deliberately.** `prototype.html` paints its
    /// selected nav row with a neutral white fill and a `--t1` label. This document's own
    /// precedence rule says that when the two disagree, the prototype is stale and the document is
    /// the spec — and the document says accent text. So the label takes `--accent` and the fill
    /// takes `--f1`, the recorded bezel fill, rather than an alpha invented here.
    func selectionFill(_ isSelected: Bool) -> some View {
        let radius = MetricToken.selectionRadius.leadingScalar
        let inset = MetricToken.selectionInset.leadingScalar
        return foregroundStyle(isSelected ? ColorToken.accent.color : ColorToken.t2.color)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(ColorToken.f1.color)
                        .padding(.horizontal, inset)
                }
            }
    }

    /// The keyboard focus ring.
    ///
    /// `DESIGN.md` §8: "Focus rings are visible, accent-bound, 2px." Both the width and the colour
    /// are read from tokens, so a change to either is a change to the design authority rather than
    /// to a view. Drawn outside the control's own bounds so it never eats into the hit area.
    func focusRing(_ isFocused: Bool, radius: Double? = nil) -> some View {
        let width = MetricToken.focusRing.leadingScalar
        let corner = (radius ?? MetricToken.selectionRadius.leadingScalar) + width
        return overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(ColorToken.accent.color, lineWidth: width)
                    .padding(-width)
            }
        }
    }
}

// MARK: - Buttons

/// The one prominent action per view, and everything else.
///
/// `DESIGN.md` §3 rule 4 allows exactly one prominent accent-filled action per view, trailing. The
/// two styles are separate types rather than a boolean so that "which one is prominent" is a
/// visible decision at each call site.
public struct ProminentButtonStyle: ButtonStyle {
    private let scale: ControlScale
    public init(scale: ControlScale = .regular) {
        self.scale = scale
    }

    /// The three tokens this control resolves to, given whether it is enabled.
    ///
    /// A value rather than three branches inside `makeBody`, so the decision is assertable without
    /// a render: `ButtonPaletteTests` reads it directly and states the contrast ratio it lands on.
    public struct Palette: Equatable, Sendable {
        public let label: ColorToken
        public let fill: ColorToken
        /// nil where the control has no bezel — the live prominent button is a flat accent fill.
        public let border: ColorToken?
    }

    /// **The disabled treatment, derived rather than copied, and the derivation is recorded.**
    ///
    /// `DESIGN.md`:443 — *"Disabled dims in place and never disappears"* — and :491 — *"Every
    /// control additionally carries default / hover / focus-visible / active / disabled"* — both
    /// bind here, and this style had no disabled treatment at all: it painted `--on-accent` on an
    /// unconditional `--accent` fill, so a disabled primary rendered identically to a live one.
    ///
    /// The design of record was read first and **does not settle it by drawing one.** Of the 29
    /// `btn primary` instances in `design/mcp-router-console.html`, not one is disabled. Worse, its
    /// CSS would not dim one either: `.btn:disabled` at :679 and `.btn.primary` at :680 have equal
    /// specificity, `.primary` is declared second and therefore wins, so a disabled primary in the
    /// mock would keep its accent fill, its accent border and its `--on-accent` label and differ
    /// from a live one only by losing its shadow. That is the same defect this method exists to
    /// close, and it is reported as a fault in the mock rather than copied into the app — the
    /// treatment below is what the mock's own `:disabled` rule *says*, applied without the cascade
    /// accident that defeats it.
    ///
    /// So a disabled prominent button drops to the disabled bezelled surface: `--f3` behind `--t4`
    /// with a `--line` bezel. It keeps its height, its padding and its position, which is what
    /// "dims in place" asks for. Tinting the accent fill instead was rejected because `--t4` has no
    /// measured ratio on `--accent-ink` anywhere in `DESIGN.md` §2, and inventing one here would be
    /// the fabricated-number defect in a different costume.
    ///
    /// `--t4` on `--f3` is **below 4.5:1 and claims the disabled exemption by name.** §2 marks
    /// `--t4` *"disabled controls only — never live text"* at 3.37:1 / 2.79:1, `ContrastRole
    /// .disabled` carries `floor == nil` and cites WCAG 1.4.3's inactive-control clause, and
    /// `ButtonPaletteTests` states the measured figure on every run rather than leaving it here as
    /// prose.
    public func palette(isEnabled: Bool) -> Palette {
        isEnabled
            ? Palette(label: .onAccent, fill: .accent, border: nil)
            : Palette(label: .t4, fill: .f3, border: .line)
    }

    public func makeBody(configuration: Configuration) -> some View {
        // **A nested `View` rather than `@Environment` on this type.** A `ButtonStyle` is not a
        // `View`, and whether SwiftUI installs a style's dynamic properties has changed between
        // releases; a disabled button that renders at full strength is a defect no compile catches
        // and no unit test sees. Reading the environment from a real `View` is the construct where
        // it is unambiguously supported, so the question is removed rather than measured around.
        Label(scale: scale, palette: palette, configuration: configuration)
    }

    private struct Label: View {
        let scale: ControlScale
        let palette: (Bool) -> Palette
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let tokens = palette(isEnabled)
            configuration.label
                .typeRole(scale.labelRole)
                .foregroundStyle(tokens.label.color)
                .padding(.horizontal, scale.horizontalPadding)
                .frame(height: scale.height)
                .background(
                    RoundedRectangle(cornerRadius: scale.cornerRadius, style: .continuous)
                        .fill(tokens.fill.color)
                )
                .overlay {
                    if let border = tokens.border {
                        RoundedRectangle(cornerRadius: scale.cornerRadius, style: .continuous)
                            .strokeBorder(border.color, lineWidth: 1)
                    }
                }
                // Transform and opacity only, per §7 — a pressed control must not animate its colour.
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
        }
    }
}

/// The ordinary control surface: a resting `--raised` fill with a bezel.
public struct StandardButtonStyle: ButtonStyle {
    private let scale: ControlScale

    public init(scale: ControlScale = .regular) {
        self.scale = scale
    }

    /// The label tier for a role, in a state.
    ///
    /// **The destructive tier comes from the role, not from the call site.** M18's brief: "a
    /// destructive alternative takes `.destructive` rather than a red foreground colour, so the
    /// platform styles it." A custom `ButtonStyle` replaces the platform's rendering, so it has to
    /// honour the role itself — `configuration.role` is what makes that possible without the call
    /// site naming a colour.
    ///
    /// `--fail-ink` rather than `--fail`, and the difference is measured rather than stylistic:
    /// `ColorToken.fail.contrastRole` is `pairedWithAWord` (an indicator beside a word) while
    /// `failInk` is `text`. This label sits on `--raised`, which is one of §2's four text grounds,
    /// so the indicator hue would ship a label under the contrast floor. The call sites that wrote
    /// `ColorToken.fail` directly did exactly that.
    ///
    /// §5: `--t4` is the disabled tier and never live text. Disabled dims in place (§3.4) rather
    /// than disappearing, so the control keeps its size and its position.
    public func labelColour(isEnabled: Bool, role: ButtonRole?) -> ColorToken {
        guard isEnabled else { return .t4 }
        return role == .destructive ? .failInk : .t1
    }

    public func makeBody(configuration: Configuration) -> some View {
        // Same reason as `ProminentButtonStyle`: the environment is read from a real `View`, where
        // it is unambiguously supported, rather than from this type. This style already carried
        // `@Environment(\.isEnabled)` before M18 and the disabled tier appeared to work; M18 made
        // the same read load-bearing for the destructive tier too, so both moved to the construct
        // that does not depend on how SwiftUI treats a style's dynamic properties this release.
        Label(scale: scale, tier: labelColour, configuration: configuration)
    }

    private struct Label: View {
        let scale: ControlScale
        let tier: (Bool, ButtonRole?) -> ColorToken
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .typeRole(scale.labelRole)
                .foregroundStyle(tier(isEnabled, configuration.role).color)
                .padding(.horizontal, scale.horizontalPadding)
                .frame(height: scale.height)
                .background(
                    RoundedRectangle(cornerRadius: scale.cornerRadius, style: .continuous)
                        .fill(configuration.isPressed ? ColorToken.raised2.color : ColorToken.raised.color)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: scale.cornerRadius, style: .continuous)
                        .strokeBorder(ColorToken.lineStrong.color, lineWidth: 1)
                )
        }
    }
}
