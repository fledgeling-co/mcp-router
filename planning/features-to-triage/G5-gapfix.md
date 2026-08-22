# G5 gap-fix — the +4 is the instrument, and the trap is wider than the submodule pin

**Parent:** G5 · **Verdict:** Needs More Work, 2026-08-22 (first verification) · **Branch:** `ai/g5`
**Oracle rung reached:** metamorphic — the load-bearing claim was flipped by a controlled
single-property mutation rather than re-run.

## What passed, and it is nearly all of it

**The load-bearing claim is confirmed and stronger than reported.** `effect-witness` appears **0×**
in 0.5.0's `strict-check.py` and 2× in 0.9.2's; `EFFECT_RUNGS` lacks the rung entirely. The
registry holds exactly four armed `effect-witness` cases (CASE-0145–0148, all pass), and
relabelling those four to `outcome` **in a temp copy** makes 0.5.0 read 62. So the gap is the rung
entire, and 58 is exactly what `strict-ratchet.json` records: a fresh clone following
`--init --recursive` prints the recorded figure and the word `held.` **A false confirmation, as
claimed.**

**The deny-instead-of-rename substitution was right**, and better than what the brief asked for: a
deny fails every read of the subtree where a rename only moves the name, and it was
non-destructive to four live agents. Two-way control reproduced. Its one gap versus a rename is
scope, closed here because the clone's submodule is uninitialised and all four scripts import
stdlib only — no `sys.path`, no skill-directory resolution, so there is no fallback to foreclose.

**Gate parity is byte-identical stdout and stderr, all exit 0** — not merely the same numbers.
**The pin is verified byte-for-byte against what GitHub returns**, which is stronger than the
README's own procedure. **No campaign data touched**, zero files changed under
`planning/test-campaign/` after ~15 gate runs. X7/X8 notes correct. Dispatch-hazard row accurate.

**Carrying the 8.2 MB whole was right.** `assets/` is 8.2 MB against `skills/` at 456 KB, no gate
script references plugin-root `assets/`, and carrying it whole is what makes the tree-SHA identity
possible — a subset would need a bespoke diff procedure and would have cost the strongest evidence
in the item to save 8 MB.

## The block — the attribution is inverted for the figure the item turns on

`planning/progress/G5.md` says the 58→62 and 15→16 rises are *"the registry moving, not the
instrument."* The verifier's 2×2 says the opposite for the first of those:

| `strict-check` | registry @ `cef3729` (70 cases) | registry @ today (76 cases) |
|---|---|---|
| **0.9.1** | 58 | **58** |
| **0.9.2** | 58 | **62** |

Every version through 0.9.1 reads **58** on today's registry; 0.9.2, 0.9.3 and 0.9.4 read 62.
`RUN-2026-08-20.md:589` records *"58 of 76 (76%)"* from a sitting headed **0.9.1**, and
`cases.json` has not changed since. So measured against the recorded figure the document itself
quotes, **the entire +4 is the instrument.**

Both halves are necessary — the registry had to gain the four cases *and* the instrument had to
gain the rung — and the half the sentence excludes is this item's whole subject.

For `capture-lineage` the runner is right and that half stands: `capture-lineage.py` is
byte-identical 0.9.1↔0.9.2, and 0.9.1 also reads 16, so that rise really is the registry.

## The consequence the documents do not carry

**0.9.1 reads 58 too.** So the trap is not 0.5.0-only, and the vendored 0.9.2 pin **does not
reproduce the campaign's recorded strict figure** — the recorded one is a pre-0.9.2 reading.

Vendoring 0.9.2 remains right: it is 0.9.1 plus the campaign's own requested DEF-048 fix,
`strict-check.py` differs by 8 lines, `vacuity-check.py` by 80, and three scripts are byte-
identical. But `ORCHESTRATOR.md` and `LEDGER.md` currently imply the trap belongs to the submodule
pin alone, and it does not.

## Acceptance

1. `G5.md`'s attribution sentence is corrected: the strict rise is the **instrument**, the lineage
   rise is the **registry**, and both halves of the strict case are necessary.
2. The **0.9.1-reads-58** fact is added wherever the trap is described as the submodule pin's —
   `ORCHESTRATOR.md`'s G5 row and hazard text, and `LEDGER.md`'s G5 row.
3. State plainly that the vendored pin does **not** reproduce the campaign's recorded strict
   figure, and why that is still the right pin.
4. `G5.md`'s cited tip `10da833` was amended away; `64e1631` is the tip. Correct it — a reader will
   not find that commit.
5. Gates unmoved at this base: `make lint` **0 over 535 files**, `0/542 require formatting`,
   `no-raw-design-values: clean`, selftest **27 held**; reconciler **0 across A–L**;
   `parity-manifest-check.sh` **exit 0, 92 rows**.

Use a **wrap-tolerant sweep with a presence control** on every corrected figure. An absence check
cannot detect its own blindness — G4's gap-fix shipped two broken sweeps that its absence check
passed, and R17 spent four passes on a claim a line-anchored grep could not see.

## For the owner, to relay rather than fix

They costed this decision at 8.9 MB believing it was instrument. **92% of it is imagery** —
`fidelity-runs` 3.6 MB, `audit-renders` 1.6 MB, two icon-engine PNGs 2.5 MB — and `skills/` is
456 KB. The verifier's judgement, which this item accepts, is that the ratio does not change the
call. The reason it does not is worth their knowing.

## Scope

`planning/progress/G5.md`, and the G5 rows and hazard text in `ORCHESTRATOR.md` and `LEDGER.md`.
**No change to the vendored tree, the pin, or any gate.** Both are verified and re-vendoring would
put this item's strongest evidence back in question.
