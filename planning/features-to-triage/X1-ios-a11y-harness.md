# X1 — the iOS accessibility-tree harness, and the two surfaces still empty

**Category:** mac/ios · test instrument **Found:** 2026-08-20, by running `make all` on a clean tree.

`make all` exited 2 at `test-ios` with **19 failing iOS test cases** while macOS was green at
1468 tests / 178 suites. Every failure had the same shape — *rendered nothing*, `is not on screen: `
with an empty tail, `("0") is not greater than ("0")`. Seventeen are fixed; two remain, and both
were red before this work started.

## What was wrong, and what fixed it

**Two instrument defects, found by measuring rather than by reading the tests.**

1. **A fixed settle pass is the wrong instrument.** `host()` spun the run loop once for 50ms with
   the comment that SwiftUI fills `accessibilityElements` on the next turn. *When* is not fixed —
   it moves with the simulator's OS and with load — so the same suite passed on one runner and
   failed on the next. Replaced with a deadline poll that returns as soon as the tree is populated.
   The poll deliberately **does not assert** on an empty tree: an empty tree is legitimate on a
   frames-only surface, and asserting there broke four passing tests while fixing four others.

2. **`ObjectIdentifier` is unique only among live objects, and the walker retained nothing.**
   `walk` guards re-entry with `seen.insert(ObjectIdentifier(element))`. SwiftUI's bridge vends a
   freshly allocated element from `accessibilityElement(at:)`, nothing held it, and the next
   allocation reused the address — so a *different* element collided with an id already in `seen`
   and that whole branch silently returned `[]`. This is why the failures moved between runs and
   between files: it is an address-reuse race, not a missing feature. Fixed by retaining every
   visited element for the duration of the walk.

Measured, in order: **19 → 9 → 2** failing cases, with a zero-regression check at each step
(`comm` over the sorted failing-test-name sets, both directions).

## The two that remain

Both are `DiscoverSurfaceIOSTests`, both were failing at the baseline, and the diagnostic now built
into `settleAccessibilityTree` says what is happening:

```
SETTLE-EMPTY frame=(0.0, 0.0, 393.0, 852.0) descendants=5 containers=0 elemCounts=[]
  classes=[HostingScrollViewx1,PlatformContainerx1,PlatformGroupContainerx1,UIViewx1,
           _UIScrollViewScrollIndicatorx1]
```

- `testEveryCommitStateRendersTheNarrowing` — all seven `CommitState` cases, each hosting
  `ScrollView { QueueCommitBar(...) }`. The hierarchy contains **only scroll scaffolding**: five
  views, no accessibility containers, no elements. So SwiftUI built no content views at all.
  `QueueCommitBar`'s body renders `Text(PairingCopy.neverInstalls)` unconditionally and that
  constant is a real two-sentence string, so the product is not at fault for omitting it — the
  content subtree is never realised in this harness.
- `testDiscoverStaysInsideTheSafeArea` — fails its own vacuity guard,
  *"nothing was measured, so this proved nothing"*, which is the correct behaviour of a good test
  against the same empty subtree.

The comparison that narrows it: `ScrollView { plate(for:) }` in the same file, through the same
`harness.host`, now populates and passes. So the differentiator is inside `QueueCommitBar` rather
than in `ScrollView` or in the harness.

## What to do

Find why `QueueCommitBar`'s content subtree is never realised under `UIHostingController` in this
harness. The obvious next probes, cheapest first: host it **without** the `ScrollView` wrapper;
host it with an explicit `.frame(width:height:)`; and print `sizeThatFits` for the bar alone, since
a zero intrinsic height would explain a scroll view that lays out its scaffolding and no content.

Treat the result honestly under `test-campaign`'s rule: if the bar genuinely renders nothing at a
given size, that red **is** the reproduction and gets a `DEF-*` id rather than a widened assertion.
If it is the harness, the fix belongs beside the two above.

**Do not close this by weakening either assertion.** Both tests carry vacuity guards that are
working correctly, and those guards are the reason this was visible at all.
