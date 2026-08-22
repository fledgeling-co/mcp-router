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

    /// The label tier for a role, in a state. Split out so the destructive branch is one
    /// expression rather than a nested ternary inside the body.
    private func labelColour(for role: ButtonRole?) -> ColorToken {
        guard isEnabled else { return .t4 }
        return role == .destructive ? .failInk : .t1
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typeRole(scale.labelRole)
            .foregroundStyle(ColorToken.onAccent.color)
            .padding(.horizontal, scale.horizontalPadding)
            .frame(height: scale.height)
            .background(
                RoundedRectangle(cornerRadius: scale.cornerRadius, style: .continuous)
                    .fill(ColorToken.accent.color)
            )
            // Transform and opacity only, per §7 — a pressed control must not animate its colour.
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// The ordinary control surface: a resting `--raised` fill with a bezel.
public struct StandardButtonStyle: ButtonStyle {
    private let scale: ControlScale
    @Environment(\.isEnabled) private var isEnabled

    public init(scale: ControlScale = .regular) {
        self.scale = scale
    }

    /// The label tier for a role, in a state. Split out so the destructive branch is one
    /// expression rather than a nested ternary inside the body.
    private func labelColour(for role: ButtonRole?) -> ColorToken {
        guard isEnabled else { return .t4 }
        return role == .destructive ? .failInk : .t1
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typeRole(scale.labelRole)
            // §5: `--t4` is the disabled tier and never live text. Disabled dims in place (§3.4)
            // rather than disappearing, so the control keeps its size and its position.
            //
            // **The destructive tier comes from the role, not from the call site.** M18's brief:
            // "a destructive alternative takes `.destructive` rather than a red foreground colour,
            // so the platform styles it." A custom `ButtonStyle` replaces the platform's rendering,
            // so it has to honour the role itself — `configuration.role` is what makes that
            // possible without the call site naming a colour.
            //
            // `--fail-ink` rather than `--fail`, and the difference is measured rather than
            // stylistic: `ColorToken.fail.contrastRole` is `pairedWithAWord` (an indicator beside a
            // word) while `failInk` is `text`. This label sits on `--raised`, which is one of §2's
            // four text grounds, so the indicator hue would ship a label under the contrast floor.
            // The two call sites that wrote `ColorToken.fail` directly did exactly that.
            .foregroundStyle(labelColour(for: configuration.role).color)
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
