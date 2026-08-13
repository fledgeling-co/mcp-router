import Foundation

/// The breaker's construction, as values rather than as a drawing.
///
/// The breaker is the app's signature element and `DESIGN.md` §1 says so: one lever per declared
/// server, snapping up the instant an agent calls it and easing down when the reaper closes it.
/// Its geometry lives here, in the headless target, for one reason — **the invariant below has to
/// be testable without a UI harness.** Two prototype rounds failed on construction rather than on
/// styling, and a defect that only a running app can catch is a defect that ships.
///
/// What went wrong before, recorded so it cannot recur:
///
/// 1. The lit track was inset 11pt per side (14 wide) behind a lever inset 3pt per side (30 wide),
///    so the lever covered the track completely and the glow only bled out at the top.
/// 2. The housing was *darker* than its row, so the unit read as a hole punched in the table
///    rather than as a raised control.
/// 3. The lamp sat at `top:-9px` — **outside** a 40pt housing. In a 56pt row that overflows by 1pt,
///    and SwiftUI clips a child drawn outside its parent's bounds in most containers. The housing
///    is therefore 48pt here: an 8pt lamp boss mounted *on* the plate, then the 40pt switch body.
///    It is also truer to the object, since a real breaker's indicator lamp is mounted on its
///    faceplate.
///
/// The invariant that makes it read as a switch: **the slot is at least as wide as the toggle and
/// strictly taller**, so a recess is visible above the toggle when it is down and below it when up
/// — lit or not. That is what a dormant row needs, and dormant is most rows most of the time.
public struct BreakerGeometry: Sendable, Equatable {
    // Housing.
    public let housingWidth: Double
    public let housingHeight: Double
    public let housingRadius: Double

    /// The lamp boss occupies the top of the plate, inside the housing bounds.
    public let lampBossHeight: Double
    public let lampDiameter: Double

    // Slot insets, measured from the housing edges.
    public let slotInsetLeading: Double
    public let slotInsetTop: Double
    public let slotInsetTrailing: Double
    public let slotInsetBottom: Double
    public let slotRadius: Double

    // Toggle.
    public let toggleInsetHorizontal: Double
    public let toggleHeight: Double
    public let toggleRadius: Double
    public let toggleRestingOffset: Double
    public let toggleRaisedOffset: Double

    // Motion. `DESIGN.md` §7: springs, not durations.
    /// Rising: fast with a slight overshoot — the call has already happened.
    public let riseResponse: Double
    public let riseDamping: Double
    /// Falling: slow and settling, no overshoot — the reaper is unhurried.
    public let fallResponse: Double
    public let fallDamping: Double

    public static let standard = BreakerGeometry(
        housingWidth: 30, housingHeight: 48, housingRadius: 5,
        lampBossHeight: 8, lampDiameter: 6,
        slotInsetLeading: 4, slotInsetTop: 11, slotInsetTrailing: 4, slotInsetBottom: 3,
        slotRadius: 3,
        toggleInsetHorizontal: 4, toggleHeight: 15, toggleRadius: 2.5,
        toggleRestingOffset: 4, toggleRaisedOffset: 19,
        riseResponse: 0.18, riseDamping: 0.62,
        fallResponse: 0.60, fallDamping: 1.0
    )

    // MARK: - Derived

    public var slotWidth: Double { housingWidth - slotInsetLeading - slotInsetTrailing }
    public var slotHeight: Double { housingHeight - slotInsetTop - slotInsetBottom }
    public var toggleWidth: Double { housingWidth - toggleInsetHorizontal * 2 }

    // MARK: - The invariants, as values a test can read

    /// A slot narrower than its toggle is the first failure: the lever hides the track.
    public var slotIsAtLeastAsWideAsToggle: Bool { slotWidth >= toggleWidth }

    /// A slot no taller than its toggle is the second: nothing reads as a recess in any state.
    public var slotIsStrictlyTallerThanToggle: Bool { slotHeight > toggleHeight }

    /// The lamp must sit inside the housing, or it clips.
    public var lampIsInsideHousing: Bool {
        lampBossHeight >= lampDiameter && lampBossHeight <= slotInsetTop
    }

    /// The toggle must stay inside the slot at both ends of its travel, or the recess stops
    /// bounding it and the control reads as a floating rectangle.
    public var toggleStaysWithinSlot: Bool {
        let slotBottom = slotInsetBottom
        let slotTop = slotInsetBottom + slotHeight
        return toggleRestingOffset >= slotBottom
            && toggleRaisedOffset + toggleHeight <= slotTop
    }

    /// Rising overshoots; falling does not. Anything else contradicts `DESIGN.md` §7.
    public var risesWithOvershoot: Bool { riseDamping < 1.0 }
    public var fallsWithoutOvershoot: Bool { fallDamping >= 1.0 }
    public var risesFasterThanItFalls: Bool { riseResponse < fallResponse }
}

/// What a breaker is showing. One dormant state and three lit ones, each bound to the colour token
/// that carries that meaning and to nothing else.
public enum BreakerState: String, CaseIterable, Sendable {
    /// No child process. The lever rests down and the lamp is unlit — but the slot still reads.
    case dormant
    /// A child process is running.
    case running
    /// Wants a human decision.
    case wantsYou
    /// Failed or tripped.
    case tripped

    /// The token that lights the slot and the lamp, or `nil` when nothing is lit.
    public var indicator: ColorToken? {
        switch self {
        case .dormant: nil
        case .running: .live
        case .wantsYou: .attention
        case .tripped: .fail
        }
    }

    /// The lever is only up when a process is actually running.
    public var isRaised: Bool { self == .running }

    /// Spoken state, so colour is never the only signal (`DESIGN.md` §3 rule 10).
    public var accessibilityDescription: String {
        switch self {
        case .dormant: "Dormant"
        case .running: "Running"
        case .wantsYou: "Wants your decision"
        case .tripped: "Tripped"
        }
    }
}
