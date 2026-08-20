import MCPRouterKit
import SwiftUI

/// The phone's button surfaces, at the phone's touch height.
///
/// **Why these exist rather than the shared `ProminentButtonStyle` / `StandardButtonStyle`.** Those
/// two set `.frame(height: scale.height)` from `ControlScale`, whose whole ladder is macOS density
/// — `DESIGN.md` §"Density: 13pt body, 24pt controls" — and tops out at 36pt for the extra-large
/// rung. Every rung is below the 44pt floor A5 holds this feature to, so on iPhone the shared
/// styles draw a control no thumb can reliably hit.
///
/// The subtle part, and the reason the first attempt at this passed review and failed on device:
/// wrapping the button in `.frame(minHeight: 44)` from the *outside* does not fix it. That grows
/// the container while the style's own fixed-height frame keeps the drawn control — and therefore
/// its hit region and its accessibility frame — at 24pt. The measurement that caught it read
/// `accessibilityFrame.height` and found 24.0 on four surfaces. So the height has to be applied
/// **inside** the style, which is what these do.
///
/// They are phone-local on purpose. The control ladder is F2's shared surface, and an iOS rung
/// added to it is a change every Mac surface inherits — so the gap is reported for the orchestrator
/// to schedule rather than made here. Everything else is the shared treatment unchanged: the same
/// tokens, the same concentric-radius rule, transform-only press feedback, and `--t4` for disabled
/// so a dimmed control keeps its size and its place (`DESIGN.md` §3.4).
/// **Width follows the same rule as height, for the same reason.** `DESIGN.md` and the phone mocks
/// draw the pairing flow's primary and secondary actions at the full content width. Declaring that
/// with `.frame(maxWidth: .infinity)` *outside* the style stretches the button's layout frame while
/// the style's own background still hugs the label, so the control reads as a centred pill with a
/// full-width tap region — measured on the on-glass camera pre-prompt and typed-entry captures,
/// where three such buttons drew at label width. `fillsWidth` puts the declaration inside the
/// style, beside the height, where the background can see it.
public struct PhoneProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    private let fillsWidth: Bool

    public init(fillsWidth: Bool = false) {
        self.fillsWidth = fillsWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typeRole(.body)
            .foregroundStyle(isEnabled ? ColorToken.onAccent.color : ColorToken.t4.color)
            .padding(.horizontal, PhoneMetric.controlPadding)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: PhoneMetric.minimumTarget)
            .background(
                RoundedRectangle(cornerRadius: PhoneMetric.controlRadius, style: .continuous)
                    .fill(isEnabled ? ColorToken.accent.color : ColorToken.raised.color)
            )
            // Transform only, per `DESIGN.md` §7 — a pressed control must not animate its colour.
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// The ordinary phone control surface: a resting `--raised` fill with a bezel, at touch height.
public struct PhoneStandardButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    private let fillsWidth: Bool

    public init(fillsWidth: Bool = false) {
        self.fillsWidth = fillsWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typeRole(.body)
            .foregroundStyle(isEnabled ? ColorToken.t1.color : ColorToken.t4.color)
            .padding(.horizontal, PhoneMetric.controlPadding)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: PhoneMetric.minimumTarget)
            .background(
                RoundedRectangle(cornerRadius: PhoneMetric.controlRadius, style: .continuous)
                    .fill(configuration.isPressed ? ColorToken.raised2.color : ColorToken.raised.color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PhoneMetric.controlRadius, style: .continuous)
                    .strokeBorder(ColorToken.lineStrong.color, lineWidth: PhoneMetric.hairline)
            )
    }
}
