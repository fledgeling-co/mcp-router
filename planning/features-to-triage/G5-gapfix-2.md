# G5 gap-fix 2 — a file moved aside and never moved back, and two clauses

**Parent:** G5 · **Verdict:** Needs More Work, 2026-08-22 (second verification) · **Branch:** `ai/g5`
**Oracle rung reached:** metamorphic — the verifier re-executed **seven versions of the instrument
against two registry snapshots** and moved single properties, a file and a phrase, to see the
denominators and controls respond.

## What passed

**The block is closed and independently reproduced.** The 2×2 was re-derived from scratch: scripts
extracted with `git archive` from `~/Dev/fledgeling-plugins` at each version-bump commit, registries
as `cp -R` snapshots. The attribution now separates the two rises correctly.

**The controls hold, and were armed both ways**: `grep -Fc` returns **0** on each in the file it
guards, the normalised match returns **1**, and mutating two of the phrases in a copy made the
controls print `FAIL` and the sweep exit nonzero.

**Zero files changed under `planning/test-campaign/`** — clean in `git status` and empty across
`64e1631..HEAD`. The vendored tree, the pin and every gate are untouched.

## BL-1 — the progress note is not in the working tree

`git status` shows `planning/progress/G5-gapfix.md` as **deleted**. The commit is intact; the file
that `ORCHESTRATOR.md` and `LEDGER.md` both point at is simply not on disk, and the sweep crashes on
it as it stands.

The verifier's reading, which fits the evidence: **the swiftformat move-aside never moved back.**
The runner moved the new doc out of the tree to isolate whether it explained a denominator shift
from 284 to 285 skipped files — good practice, and the isolation is why that figure is trustworthy —
and the 15:52 capture reads 285, so the file was present when the gates ran.

`git checkout -- planning/progress/G5-gapfix.md` restores it. Confirm the restored file is
byte-identical to the committed one before doing anything else.

**This is worth a line in the note rather than a silent fix.** An item whose subject is records that
misdescribe their evidence lost its own record to a measurement technique, and every gate it ran
afterwards ran on a tree missing it.

## BL-2 — a stated measurement that is wrong

The backtick paragraph's clause about `main` is false: **the parity argument stands on `64e1631`
alone, and `main` reads 1128.** Correct the clause; the argument survives, the number does not.

## BL-3 — a present-tense claim about a cache that has moved

The hazard row's *"the cache's **0.9.1**"* reads as a present property of the plugin cache, which
today holds **0.9.6** and reads 62. In an item about misattributed readings, tense is not a nicety.

## Register, do not fix

**`D-g5-a` — the absent half of the sweep was never repository surface.** Leaving the 27-string
checker uncommitted is right for the presence half: a checker for one commit's prose is not
repository surface. But its two **ABSENT** assertions are exactly `planning/claim-sweep.py`'s job,
and that tool is on `main` and **not on this branch at all**, so the withdrawn claims were checked
over four hand-listed files rather than a corpus. The verifier ran the corpus check that tool would
have run — over **1366 tracked files**, `10da833` survives only in `G5-gapfix.md` and in `G5.md`'s
explanation of the amend, and the inverted sentence only where it is quoted as withdrawn.

**Nothing leaked, and that was luck confirmed afterwards rather than coverage.** Record it that way.

**`D-g5-b` — the fixed point is narrower than the doc implies.** Control W1 *is* quoted unwrapped,
at `G5-gapfix.md:84`. That is safe **only** because the sweep keys each control to one file and W1
guards `G5.md`; **a corpus-wide sweep would collapse on it.** The doc should say the property is
per-file rather than general.

**`D-g5-c` — `strict-ratchet.json` still holds `"checked": 58, "total": 70`** and should read 62.
`planning/test-campaign/` belongs to another session; already recorded in three documents.

## Acceptance

1. `planning/progress/G5-gapfix.md` is back in the working tree, byte-identical to the commit, with
   a line in the note saying it went missing and why.
2. The `main` backtick clause is corrected to 1128 with the argument left standing on `64e1631`.
3. The hazard row's tense is fixed and the cache's current version stated.
4. `D-g5-a`, `D-g5-b` and `D-g5-c` registered, not fixed.
5. **No gate re-run is needed** — the verifier states so explicitly, and nothing here reopens the
   vendoring evidence. Run only `/opt/homebrew/bin/python3 planning/ledger-reconcile.py` and the
   sweep, and paste both.

## Scope

`planning/progress/G5-gapfix.md`, one clause in it, the hazard row in `ORCHESTRATOR.md`, and the
register rows. **No vendored tree, no pin, no gate, no campaign data.**
