import MCPRouterKit
import SwiftUI

/// The breaker — the app's signature element, and the only loud thing in it.
///
/// One lever per declared server: it snaps up the instant an agent calls the server and eases down
/// when the reaper closes it. `DESIGN.md` §1 names it the signature and §7 gives it its two speeds.
///
/// **Every dimension here comes from `BreakerGeometry`, which lives in the UI-free target.** That
/// split is deliberate rather than tidy: two prototype rounds failed on *construction* — the lever
/// covering its own track, the housing reading as a hole, the lamp drawn outside the housing and
/// clipped — and a defect only a running app can catch is a defect that ships. The geometry is
/// therefore a value with testable invariants, and this file only draws it.
public struct Breaker: View {
    private let state: BreakerState
    private let geometry: BreakerGeometry

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(state: BreakerState, geometry: BreakerGeometry = .standard) {
        self.state = state
        self.geometry = geometry
    }

    /// The slot is lit by the state's own indicator colour, and by nothing else. `--f2` is the
    /// documented track fill, so an unlit slot is a track rather than a dimmed light.
    private var slotFill: Color {
        (state.indicator ?? .f2).color
    }

    /// The lamp is unlit on `--f3`, the inactive fill, so a dormant unit still shows its lamp
    /// housing rather than a hole.
    private var lampFill: Color {
        (state.indicator ?? .f3).color
    }

    /// Rising is fast with a slight overshoot; falling is slow and settles. Chosen on the state
    /// being moved *to*, which is what makes one flick use one spring and the return use the other.
    ///
    /// `nil` under Reduce Motion, which removes the animation and leaves the state change intact —
    /// `DESIGN.md` §7 requires the motion to go, never the meaning.
    private var transition: Animation? {
        guard !reduceMotion else { return nil }
        return state.isRaised
            ? .spring(response: geometry.riseResponse, dampingFraction: geometry.riseDamping)
            : .spring(response: geometry.fallResponse, dampingFraction: geometry.fallDamping)
    }

    private var toggleOffsetInSlot: Double {
        let travel = state.isRaised ? geometry.toggleRaisedOffset : geometry.toggleRestingOffset
        return travel - geometry.slotInsetBottom
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: geometry.housingRadius, style: .continuous)
            // The housing is `--raised`, never darker than the row it sits in. Drawn darker it
            // reads as a hole punched in the table instead of as a control mounted on it.
            .fill(ColorToken.raised.color)
            .overlay(
                RoundedRectangle(cornerRadius: geometry.housingRadius, style: .continuous)
                    .strokeBorder(ColorToken.lineStrong.color, lineWidth: 1)
            )
            .overlay(alignment: .top) { lamp }
            .overlay(alignment: .bottom) { slot }
            .frame(width: geometry.housingWidth, height: geometry.housingHeight)
            .animation(transition, value: state.isRaised)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Breaker")
            // Colour is never the only signal (§3 rule 10): the state is spoken in words, and the
            // lever's position carries it visually.
            .accessibilityValue(state.accessibilityDescription)
    }

    /// Mounted on the plate, inside the housing bounds. It sat at `top:-9px` on a 40pt housing
    /// once — outside its parent, which SwiftUI clips in most containers.
    private var lamp: some View {
        Circle()
            .fill(lampFill)
            .frame(width: geometry.lampDiameter, height: geometry.lampDiameter)
            .padding(.top, (geometry.lampBossHeight - geometry.lampDiameter) / 2)
    }

    /// The recess and the lever. The slot is wider and taller than the toggle, so a recess stays
    /// visible above the lever when it is down and below it when it is up — lit or not. That is
    /// what a dormant row needs, and dormant is most rows most of the time.
    private var slot: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: geometry.slotRadius, style: .continuous)
                .fill(slotFill)
                .frame(width: geometry.slotWidth, height: geometry.slotHeight)

            RoundedRectangle(cornerRadius: geometry.toggleRadius, style: .continuous)
                .fill(ColorToken.raised2.color)
                .overlay(
                    RoundedRectangle(cornerRadius: geometry.toggleRadius, style: .continuous)
                        .strokeBorder(ColorToken.lineStrong.color, lineWidth: 1)
                )
                .frame(width: geometry.toggleWidth, height: geometry.toggleHeight)
                .offset(y: -toggleOffsetInSlot)
        }
        .padding(.bottom, geometry.slotInsetBottom)
    }
}

/// A breaker that can actually be flicked.
///
/// `DESIGN.md` §10 records that the motion has never been observed running — the prototype animates
/// nothing. This is the control that makes the two springs watchable, and §8 binds `Space` to
/// toggling the selected row's breaker, so it is a real `Button` rather than a tap gesture.
public struct BreakerToggle: View {
    @Binding private var state: BreakerState
    private let geometry: BreakerGeometry

    public init(state: Binding<BreakerState>, geometry: BreakerGeometry = .standard) {
        _state = state
        self.geometry = geometry
    }

    public var body: some View {
        Button {
            state = state.isRaised ? .dormant : .running
        } label: {
            Breaker(state: state, geometry: geometry)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Breaker")
        .accessibilityValue(state.accessibilityDescription)
        .accessibilityHint("Toggles the server between dormant and running")
    }
}
