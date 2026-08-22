import Foundation

/// JavaScript's `Math.round`: half rounds toward +∞, which differs from Swift's `rounded()`
/// (half away from zero) for negative halves. Durations here are non-negative, but the router's
/// status fields are diffed against the reference byte for byte, so the semantics are matched
/// rather than assumed equivalent.
///
/// It sat at the foot of `UpstreamPool.swift` until M22, which needed it for the duty-cycle route
/// and pushed that file past its length cap. It is not pool state — it is JavaScript's rounding,
/// and it belongs beside ``JSNumber`` with the rest of the language's own arithmetic.
func jsRound(_ value: Double) -> Int {
    Int((value + 0.5).rounded(.down))
}
