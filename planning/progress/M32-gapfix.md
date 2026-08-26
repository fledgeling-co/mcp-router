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

## The committed ledgers described an earlier run

All five surfaces were regenerated from the delivered gate on this tree, each surface its own
invocation. The servers table had carried **no census row at all** and `breadth 116 ·
covered-by-pair 24`; the fresh run writes `census 8 finding(s)` and `breadth 128 · covered-by-pair
13 · covered-unoracled 11`, which is the figure the verifier measured independently. servers,
insights, harnesses and readme changed; popover did not, because it exits 3 before it measures
anything and its ledger already carried that refusal instead of a table.

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
