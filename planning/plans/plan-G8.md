# plan-G8 — the executable part of *a question answered at the wrong scope*

**Tier: Small.** Two new scripts and one Makefile wiring. No UI, so the `design` stage is skipped
with that as its recorded reason: the deliverables are gates that print to a terminal and exit,
and there is no rendered surface for `design-review` or `be-my-witness` to gate.

## What already landed, and why it is not enough

anchor `The Cross-Branch Role-Intersection and Scope-Completeness Invariant (G8 / M16)`,
`scripts/acceptance/mock_fidelity.py:39` at `03c34c3`, opens a ten-line header comment recording
M16's cross-branch role-intersection rule. Nothing reads it, nothing depends on it, and nothing goes red
when it is violated. **A header comment with nothing downstream of it reads as a standard to
satisfy rather than a call to make** — which is this item's own subject, committed by the item.

The remaining scope is executable, and the brief names three pieces.

## 1. `planning/role-intersection-gate.py` — the cross-branch check, made runnable

M16's reduction, mechanised: rather than asking whether a merge conflicts, derive the **union of
every active branch's roles**, walk each surface's own record against it, and name what could not
be checked.

**Input — and this is the decision that makes it runnable at all.** `mock-fidelity-gate.sh` needs a
`MEASURE` Swift build to write `planning/fidelity/dumps/`, which is untracked and which fails on
this machine today (`make mock-fidelity SURFACE=servers` exits 3, known-inherited). A gate that
can only run behind a broken build is a gate nobody runs. But the **tracked** ledgers at
`planning/fidelity/*.ledger.md` already carry `role=… kind=…` for every build node the last real
measurement saw, one row per line. So the check reads those: six surfaces, no build, no dumps.

The cost is stated in the script rather than hidden: the ledgers are a **frame**, not the working
tree, so the gate answers *did the last recorded measurement of this surface use a role the union
adds* — and it prints each ledger's provenance so a stale one is visible as staleness rather than
as a clean answer. That is the same trade `citation-gate.py` takes with `TREE_ONLY`.

**Sets established before members are answered about**, in both directions:

- the **branch** set is `git for-each-ref` over every local head minus those already merged into
  the base, never the branches in conversation;
- the **surface** set is the union of ledgers across *all* those branches, not the ones on HEAD —
  so a surface another branch adds is in scope;
- every surface is walked, **including surfaces with zero diff on `mock_fidelity.py`**, because
  the quota rule keys on the build node's role rather than on the edit.

**Exit codes** mirror `mock_fidelity.py`, deliberately: `0` no surface touches an added role, `1`
at least one does — a call to make, not a defect — and `3` inconclusive, when a branch's file or a
surface's ledger could not be read and the verdict depended on it. Exit 1 is what turns the header
comment into something with teeth: M22's real exposure would have reddened it.

## 2. `planning/sweep-control-gate.py` — a presence control on every absence sweep

The rule earns a gate. This repo has four measured absence checks that could not fail: a
line-anchored `grep` returning 0 for a phrase present twice, a sentinel matching the product's own
copy, an `awk` on the wrong AX column, and a first-pass sweep over `scripts/` only. Every sweeping
script here already carries a control; **nothing checks that the next one does.**

Discovery over the tracked corpus, a registry at `planning/sweep-controls.json` naming each
sweeping script's control command and what it proves, and the gate **runs** each control rather
than believing the registry — so a control that has rotted reddens. A newly tracked sweep with no
entry is reported unregistered.

## 3. Every sweep names the normaliser that produced its count

Five sweeps over one phrase in one file returned four answers and only the widest was complete. So
no count in either script is printed bare: each carries its reader's identity, and each
intersection row carries `file:line` sites. `citation-gate.py`'s five-denominator block is the
form to follow.

## Why here rather than beside the citation gate

`citation-gate.py` does the adjacent job and shares the disciplines — hermetic control, denominators
printed side by side, a per-file ratchet. It does not share the **subject** (`path:line` citations
in tracked prose), the **corpus** (git refs and fidelity ledgers, not markdown), or the **exit
semantics** (tri-state with an inconclusive rung). Folding role intersection into it would give one
script two verdicts and force a citation ratchet onto a question that has no bare class. They sit
in the same directory, under the same conventions, as separate scripts.

## Proving each check can fail

Plant, watch it redden, restore byte-identically, report the `sha256` of the restored file. An
assertion nobody has watched fail is not known to bite, and this item exists because of exactly
that. Each script also carries a **hermetic control** that runs on every invocation — a throwaway
git repo in a temp directory with planted answers, the form `citation-gate.py --control` settled —
so the proof is repeatable rather than a one-off recorded in a note.

## Test strategy

No Swift and no UI, so no XCTest and no e2e surface. The oracle is the controls, which run on every
invocation and print above the table, plus the red-green plant record. `make` targets wire both
gates so they run unattended.
