---
status: completed
shipped-by: 67ae4f5
---

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

---

## Outcome — 2026-08-16, branch `ai/d3`

Every row was reproduced before it was decided. Evidence: `planning/evidence/D3-acceptance.md`.

| Child | Outcome |
|---|---|
| `M5-d` | **Closed.** `axkit pick` added: presses a segment, re-walks the tree, and requires that exactly one segment in the target's own radio group reads `AXValue == 1` and that it is the one named. Exit `0` switched · `3` already chosen, so the call drove nothing · `1` not chosen or the substring was ambiguous. Proven against the running app at load 49, never frontmost; mutation-tested |
| `D-i3-a` — the test half | **Closed as NOT-A-DEFECT.** The claim that the trait override "measurably never reaches the SwiftUI view" is **false**: measured, the view sees `dynamicTypeSize == .large` under `.large` and `.accessibility5` under `.accessibilityExtraExtraExtraLarge`. `testHostPropagatesContentSizeIntoTheSwiftUIEnvironment` now locks that in. **The row's "do not copy that pattern" was steering runners away from a helper that works** |
| `D-i3-a` — the product half | **Still open, correctly.** `TypeToken.font` really is a fixed `Font.system(size:weight:)` and `DESIGN.md` §2 fixes the eight sizes. A shared design decision, not an item's to take |
| `D-i3-g` | **Proposal ready**, not applied — `D3-copy-proposals.md`. Recommends `"Queue {count} for your Mac"`, with the six sites it moves and the guard it widens |
| `D-i3-h` | **Proposal ready**, not applied — same file. Recommends scoping both empty states to "these results" now, and raising render-from-store as its own item |

### Raised by D3

| New | What |
|---|---|
| `D-d3-a` | **Wire `axkit pick` into `m5-discover.sh` (A4's second half) and `m7-evals-cleanup.sh` (both segmented filters).** The verb exists and is proven; wiring it changes M5's and M7's acceptance surfaces and re-runs their gates, so it belongs to those items. The consumer must read exit `3`, not only `\|\| fail` on nonzero |
| `D-d3-b` | **Two iOS tests fail on `main` on a healthy simulator**, unrelated to D3: `PhoneSurfaceTests.testRowHeightIsIndependentOfNameLength` and `.testSkeletonMatchesTheRowItReplaces`, both *"no row was found in either render, so nothing was compared"*. I1 surfaces. Both fail honestly rather than comparing two empty sets |
| `D-d3-c` | **A long-booted simulator's accessibility bridge silently returns nothing**, turning 2 real failures into 45 and making `make test-ios` look like a product catastrophe. Every failing test read the accessibility tree; every passing one read the UIView tree. Worth a freshness or sanity probe in the iOS lane, the way `build-freshness.sh` guards the Mac lane |
| `D-d3-d` | The `chosen.count == 1` exclusivity clause in `axkit pick` is a **defensive guard no live input exercises** — a SwiftUI `Picker` is genuinely exclusive, and the mutation that removed it survived. Recorded as unproven rather than dressed up |
