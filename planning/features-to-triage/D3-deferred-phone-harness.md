# D3 — The deferred register: phone copy, and the harness limit

**Source:** `deferred-plan` = `schedule-all` (confirmed).

Four children. Two are **spec-level**: I3 declined to rewrite them unilaterally because the strings are
specified verbatim and passed the spec gate, which is the correct call and the reason they are here.

| Child | What |
|---|---|
| `D-i3-g` | The Triage commit button says **"Send"** where nothing sends. The phone queues; the Mac decides. A11 specifies that string verbatim, so amending it is a spec change |
| `D-i3-h` | Decided buckets are the intersection with the current results page, so the Dismissed empty state claims a durability it does not deliver: dismissals appear to vanish when the page changes |
| `D-i3-a` | **No phone surface scales with Dynamic Type.** `TypeToken.font` is a fixed `Font.system(size:weight:)` shared with every Mac surface, and `DESIGN.md` §2 fixes the eight sizes deliberately, so this is a shared design decision to be made rather than a bug to fix. I1's Dynamic Type test overrides a UIKit trait that **measurably never reaches the SwiftUI view**, so it asserts something real but not what its name implies; do not copy that pattern |
| `M5-d` | **An `axkit` verb that can press a non-`AXButton` role.** A harness limit, not a product gap: `axkit press` matches `AXRole == "AXButton"` only, so no rendered pass can drive a segmented filter. Raised by M5, predicted to hit M7's two boards, and it did |

`D-i3-g` and `D-i3-h` want the owner's word on the copy before the code changes. Draft the amendment,
do not assume it.
