# G5 gap-fix — the +4 was the instrument, and the trap was wider than the submodule pin

**Branch** `ai/g5` · **Base** the delivered tip `64e1631` · **Status** ready to verify — not
verified here.

Documents only. **No change to the vendored tree, the pin, or any gate** — both were verified in
the first pass and re-vendoring would put this item's strongest evidence back in question. Three
files changed: `planning/progress/G5.md`, `ORCHESTRATOR.md`, `planning/features-to-triage/LEDGER.md`.

---

## The block, re-measured here before it was written down

The verifier's finding was reproduced independently rather than transcribed, against a `cp -R`
copy of `planning/test-campaign/` under `/tmp` so the campaign directory was never the target:

| `strict-check.py` | reads on today's registry | `effect-witness` in the script |
|---|---|---|
| 0.5.0 — the submodule pin | 58 of 76 (76%) | **0×** |
| **0.9.1** — the version the recorded sitting was run with | **58 of 76 (76%)**, `held.` | **0×** |
| 0.9.2 — vendored here | 62 of 76 (82%) | 2× |
| 0.9.4 — installed | 62 of 76 (82%) | 2× |

`cases.json` holds 76 cases, of which exactly four carry `effect-witness` — CASE-0145, 0146, 0147
and 0148, all `pass`, all armed. `capture-lineage.py` is byte-identical across 0.9.1 and 0.9.2 and
0.9.1 also judges 16 against a ratchet of 15.

So the two rises have opposite causes, and `G5.md` had assigned both to the registry:

- **strict 58 → 62 is the instrument.** `RUN-2026-08-20.md:589` records *"58 of 76 (76%)"* from the
  fourth sitting, headed `test-campaign 0.9.1` at `:508`, and `cases.json` has not moved since.
  Measured against that figure the whole +4 is the rung.
- **lineage 15 → 16 is the registry.** Same script both versions, same reading — four new captures.

Both halves of the strict case are necessary: the registry had to gain the four armed cases *and*
the instrument had to gain the rung that can see them. The half the old sentence excluded is what
G5 is about.

## What changed in each file

**`planning/progress/G5.md`**

1. The attribution paragraph under acceptance 3 is replaced. It said *"The two figures that moved
   are the registry moving, not the instrument"*; it now separates the two rises, carries the
   four-version table above, and states that both halves of the strict case are necessary.
2. *"What the old instruction actually cost"* is now *"…— and what the new pin does not buy"*, with
   0.9.1 added to its table and two paragraphs: the trap is wider than the submodule pin, and
   **the vendored 0.9.2 does not reproduce the campaign's recorded strict figure** — 62 against a
   recorded 58, because the recorded reading is a pre-0.9.2 one. It is still the right pin, because
   a pin that reproduced 58 would be a pin to an instrument blind to four of the registry's own
   armed cases; what should move is the recorded figure, and `strict-ratchet.json` belongs to the
   campaign owner rather than to this item.
3. The cited tip `10da833` is corrected to `64e1631`. `10da833` was amended into `64e1631`, is on
   no branch, and a reader will not find it; the amend rewrote three lines of `G5.md` and nothing
   else, so the tree the gates read is the tip's, and the document now says so.
4. *"`parity-manifest-check.sh` was not run"* now records that this gap-fix ran it — exit 0, 92 rows.

**`ORCHESTRATOR.md`** — the G5 row (`:314`) gains the 0.9.1-reads-58 fact, the non-reproduction and
its justification, and the corrected attribution for both rises. The **DISPATCH — WORKTREE
SUBMODULE** hazard row (`:571`) gains a sentence: populating the submodule is not the only route to
a reading that agrees with `strict-ratchet.json` while measuring less, because the cache's 0.9.1
reads 58 as well.

**`planning/features-to-triage/LEDGER.md`** — the G5 row (`:67`) gains the same three facts in
compact form.

## The sweep, and why it has controls in both directions

Every corrected figure was checked with a **wrap-tolerant sweep**: each of the four documents read
whole and collapsed to single-spaced text, so a phrase broken across a hard-wrapped line — or across
an indented list continuation — still matches. **27 present-assertions, 2 absent-assertions, 11
controls, exit 0.**

An absence check cannot detect its own blindness, so the sweep carries controls in both directions
and prints all eleven before any assertion is trusted:

- **4 negative controls** — one per document: a wrong figure, a nonexistent version, the opposite
  claim, and a wrong gate reading, each checked against the file it would be wrong in and each
  required to report missing. A sweep matching everything fails here. None is quoted in this
  document, because a control reproduced in the text it guards stops being a control.
- **4 positive controls** — one per document, strings known to be present, that the absent-checks
  must report found. A sweep matching nothing fails here.
- **3 wrap controls**, which are the ones that matter, each proved rather than assumed. The first is
  the sentence at `G5.md:97-98` — *"the whole +4 is the rung and none of it is the registry"*. The
  other two are in this file, at lines **35–36** and **48–49**, the second spanning an indented list
  continuation; they are cited by location rather than quoted, for the same reason as the negative
  controls: a phrase reproduced unwrapped in the document it guards stops being a wrap control, and
  it took a failing run here to notice that. **`grep -Fc` returns 0 on all three; the sweep returns
  1 on all three.** That is the blindness demonstrated rather than asserted — the class that cost
  G4's gap-fix two broken sweeps and R17 four passes on a claim a line-anchored grep could not see.

The sweep lives at `/tmp/g5gf/sweep.py` and is deliberately not committed: the scope is four
documents, and a checker for one commit's prose is not repository surface.

## Gates

Run on this worktree with the working tree in its committed state.

| Gate | Read | Acceptance |
|---|---|---|
| `make lint` — swiftlint | **0 violations, 0 serious in 535 files** | 0 over 535 ✔ |
| `make lint` — swiftformat | **0/542 files require formatting**, 285 skipped | 0/542 ✔ |
| `make lint` — `no-raw-design-values` | **clean**, 77 files under the rules of 118 scanned | clean ✔ |
| `make lint` — `no-wire-codable` | clean, 2 exemptions | — |
| `make lint` — `no-harness-config-writes` | 327 examined, 8 name a config, 22 write, 8 in the seam, none writes one | — |
| `make lint` — selftest | **27 case(s) held** | 27 held ✔ |
| `planning/ledger-reconcile.py` | **reconciled — no findings across A–L**, exit 0 | 0 across A–L ✔ |
| `scripts/acceptance/parity-manifest-check.sh` | **exit 0, 92 rows** | exit 0, 92 rows ✔ |

`make lint` exits 0.

**The one warning is pre-existing and its parity is unchanged.** The reconciler still says
`LEDGER.md odd number of backtick quotes (1205)`. `LEDGER.md` reads **1205** backticks now against
**1193** both at the delivered tip `64e1631` and on current `main` — this gap-fix adds 12, an even
number, so it cannot have changed whether the count is odd.

**One denominator moved by exactly one, and it is this document.** swiftformat reports **285 files
skipped** against **284** at the delivered tip. Isolated rather than assumed: with
`planning/progress/G5-gapfix.md` moved aside the same command reads **284**, and with it back,
**285**. swiftformat counts every non-Swift file it walks past, and this commit adds one markdown
file. The Swift population is unchanged at **542 considered, 535 linted, 0 requiring formatting**.

**No campaign data touched.** `git status planning/test-campaign/` is empty; all four version
readings were taken against the `/tmp` copy.

## For the owner, relayed rather than fixed

The G5 decision was costed at **8.9 MB believing it was instrument**. It is not: **92% of the
vendored tree is imagery** — `fidelity-runs` 3.6 MB, `audit-renders` 1.6 MB, two icon-engine PNGs
2.5 MB — against `skills/` at **456 KB**. The verifier's judgement, which this item accepts, is
that the ratio does not change the call: carrying the tree whole is what makes the byte-for-byte
identity against `git archive` possible, and a trimmed subset would need a bespoke diff procedure
and would cost the strongest evidence in the item to save 8 MB. Recorded because the reason the
ratio does not change the call is worth knowing.

## Open

**`strict-ratchet.json` still holds 58, and it should read 62.** Not this item's to raise —
`planning/test-campaign/` belongs to another session, and G5 does not rewrite its registry. It is
recorded in `G5.md`, in the `ORCHESTRATOR.md` G5 row and in the `LEDGER.md` G5 row so whoever owns
the campaign finds it.

**X7 and X8 are untouched, as in the first pass.** Editable here since G5; closable only upstream.
