# M32 gap-fix — the guard that was defeated, and the ledgers that never described the run

Two gaps from the verification pass. Six of the eight requirements it checked were confirmed and
are untouched here.

## The oracle root check tested the spelling, not the file it opened

The guard added to stop an oracle pointing at the implementation was bypassable by traversal, and
the verifier drove it through:

```
app/Tests/../../app/Sources/MCPRouterKit/Shell/MenuCommand.swift   ok=True   "asserted as a quoted literal"
./app/Tests/../../app/Sources/MCPRouterKit/Shell/MenuCommand.swift ok=True   "asserted as a quoted literal"
app/Sources/MCPRouterKit/Shell/MenuCommand.swift                   ok=False  "oracle inside the implementation..."
```

The same file, refused under its plain name and accepted under a name wearing a test root. The
check ran `lstrip("./")` then `startswith` over the raw string, while `open` was handed
`os.path.join(ROOT, target)` — so the root a reader saw and the bytes that were read were two
different facts, and only the first was ever checked. The file it landed on contains the literal
because it is the file that draws it, which is precisely the defect the guard exists to refuse.

`oracle_verdict` in `scripts/acceptance/mock_fidelity.py` now resolves with `os.path.realpath`
before testing, and derives the root check from the resolved path. A reference resolving outside
the repository is refused by its own message rather than falling through to the root list.

**Why this was invisible.** The selftest planted only the naive spelling, so no case could fail on
a traversal. Both bypass spellings are now cases. Armed by reverting the engine alone: exactly
those two fail, and the unfixed engine returns **0** where the case expects **1** — a clean gate
over an oracle reading the implementation. Restored, the suite is 87 cases with all three exits
observed, up from 85.

## The committed ledgers described an earlier run — and the count of them was wrong

**There are six fidelity surfaces, not five, and the record's own count is what hid the sixth.**
The earlier version of this section said "All five surfaces were regenerated", then named
servers, insights, harnesses and readme as changed and popover as unchanged — five named, five
accounted for, denominator satisfied. `settings` was never in the sentence, so it was never in the
denominator either, and nothing in the paragraph could notice. That is the same failure family the
oracle-root fix above is about: a check whose scope is its own list cannot report what the list
omits. The surface set is derived here from the manifests on disk rather than from prose:

```
$ ls planning/fidelity/*.layers.json | sed 's#.*/##; s#\.layers\.json##'
harnesses  insights  popover  readme  servers  settings
```

**Why the omission was this item's own defect rather than bookkeeping.** This branch added
`census: required` to `planning/fidelity/settings.layers.json` (`553da1d`). The committed
`settings.ledger.md` was last written at `f7ee25e`, which predates this branch — so it described a
run under a manifest that no longer exists, and carried **no census row at all**. That is exactly
the condition the gap-fix was raised to close on `servers`, left standing on `settings`.

**The run.** Every one of the six was re-run on this tree after the rebase onto `main`
(2026-08-27), each surface its own invocation of
`./scripts/acceptance/mock-fidelity-gate.sh <surface>`. Exit codes as observed:

| Surface | Exit | Changed by this run |
|---|---|---|
| `harnesses` | 1 | no — byte-identical to the committed ledger |
| `insights` | 1 | no — byte-identical |
| `popover` | 3 | no — exits 3 at inventory before it measures anything; its ledger is that refusal, not a table |
| `readme` | 1 | no — byte-identical |
| `servers` | 1 | no — byte-identical |
| `settings` | 1 | **yes — the only ledger this run rewrote** |

Five reproducing byte-identically is the evidence that the earlier regeneration of those four was
sound and that `settings` was the whole of the gap. `settings` moved as follows:

```
- | `tokens`   | clean | 25 matched, 64 pending, of 89 rows |
+ | `tokens`   | clean | 70 matched, 19 pending, of 89 rows |
- | `literals` | clean | scanning 125 files |
+ | `literals` | clean | scanning 146 files |
+ | `census`   | 64 finding(s) | 263 mock element(s) across 2 state(s) · 64 outside every derivation rule, 0 of them waived |
```

The census row is new because the layer is new to this branch's manifest. The tokens and literals
rows moving — 25 matched becoming 70, 125 files scanned becoming 146 — are the independent
evidence that the committed table described an older tree rather than merely an older manifest.
The gate's own line for the run is `mock-fidelity: EXIT 1 — 161 finding(s)`, which is the 64
census findings plus the 97 breadth findings the table already carried; the "64" is the census
row, not the total.

The servers figures from the earlier regeneration stand unchanged on re-run: `census 8 finding(s)`
and `breadth 128 · covered-by-pair 13 · covered-unoracled 11`, against the `breadth 116 ·
covered-by-pair 24` and absent census row it had carried before.

## Two things this branch added that nothing can exercise

**The popover manifest.** `census: required` and a `mockElements: 1` floor were added to
`planning/fidelity/popover.layers.json`, and the popover gate exits 3 at the inventory stage — the
mock has no `.v-ideal` block under `#statusPopover` — on this branch and identically on main. The
census layer is never reached, so neither the requirement nor the floor can fire in either
direction. They are declarations of intent, not measurements, and they stay unexercised until the
mock carries that block. Recorded here rather than left to be discovered as coverage.

**A hash that names no file.** The live-control record quotes `a733fc19d074819d` as the restored
state of `scripts/acceptance/mock-affordances.py`. That value matches no file in this branch under
any of sha256, sha1, md5 or git blob. Re-measured here, the file's sha256 truncated to sixteen is
**`c2f2bad9600cdd04`**, which is what the verifier measured. The correction belongs in
`planning/features-to-triage/LEDGER.md`, which this branch may not write, so it is recorded here
and the ledger row is still wrong.
