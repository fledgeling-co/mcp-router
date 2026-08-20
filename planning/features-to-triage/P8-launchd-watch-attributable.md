# P8 — make `install-launchd-watch`'s `reran` term attributable

**Category:** parity · test instrument **Parent:** D-p1-e (withdrawn by P5, and by an
out-of-family reviewer independently)
**Blocks:** R4-C, which needs 82 of 83 and currently has 80.

The second of the two rows standing between the parity gate and the cutover target. Everything
P5 built is kept; one term has to start measuring what it claims.

## What is wrong, measured rather than theorised

`oneshot` discriminates: a resident Swift program reads `yes,no,no` and the lane exits 1.

`reran` does not. Point the agent's `WatchPaths` at a decoy in a fresh `mktemp -d` the lane never
touches — with the generated plist dumped to prove the mutation took — and a genuine delivery is
impossible, so the only correct answer is `no`. Across six trials: **4 correctly red, 2 spuriously
green**, and the spurious ones are byte-identical in the report to a genuine first-delivery re-run.
A seventh trial with the decoy in a sibling directory also read green.

The gate runs this lane once. So a Swift watcher that never re-ran on a file change **would have
recorded this row green about one run in three**.

The row note's stated limit — *WatchPaths fires on churn in the file's directory* — is also wrong,
measured: a decoy in its own private directory went green twice. The measured rate replaces the
theory.

## The lesson this row carries for the rest of the fleet

A series bounds the **agreement rate**. What is broken here is what the term **measures**, and no
number of agreeing runs can find that. Sixteen observations agreed on all four terms at loads
5.5–10.3, and the term was still wrong. This is why an assertion is armed — watched to fail —
rather than trusted because it passed.

## What to build

Make the observed re-run **attributable**: tie it to the specific staged change that should have
caused it, so a spurious launchd spawn cannot satisfy the term. The shape that does this is a
stamped stimulus — the staged file carries a token the watcher must observe and report back —
so the assertion is *this run saw this change* rather than *the run counter moved*.

Everything already built is kept: launchd's own `runs` counter read from `launchctl print`, the
settle predicate, the restaging loop that survives lossy `WatchPaths` delivery, and the
`runs=N->M:stages=K` evidence line.

## Acceptance

- The decoy mutation goes **red on every trial**, not four in six. State the trial count in the
  evidence; a rate is the finding here, and the previous note's absence of one is what let a
  one-in-three false green stand.
- `oneshot` still discriminates, so the fix does not trade one term for another.
- The row moves `blocked → proven` with the measured trial count attached.
- The evidence line prints its denominator, so a reader sees whether agreement needed one
  delivery or six.
