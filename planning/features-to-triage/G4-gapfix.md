# G4 gap-fix — the census counted the instrument into its own denominator

**Parent:** G4 · **Verdict:** Needs More Work, 2026-08-22 (first verification)
**Worktree:** `.worktrees/G4`, branch `ai/g4`

## What passed, and it is most of the item

Four of the five claims hold, each re-derived rather than read:

- **`make all` red at `parity-selftest`, and red identically at the base.** Reproduced exactly:
  `git archive 72958de` plus this worktree's `node_modules` and `dist` gives `31 behaved, 5 did
  not`, exit 1, `diff`ing empty against the HEAD run — bar one HEAD case killed at exit 143 under a
  load average of 945 from other sessions, which behaved on re-run. This was the load-bearing claim
  and it stands.
- **Both gates print their boundary on every run**, confirmed by running them: the accounting gate
  closes on *"reaches the SILENT drop in Python only … and so does every reader inside the 66 shell
  files"*, the null-run gate on *"instances 2, 3, 7 and the egress one in G4's table all bite here
  and are still misaimed"*.
- **`no-wire-codable.sh` behaves as blamed** — two scratch trees differing by one exemption comment
  give exit 1 with `clean` printed and the `exemption(s) recorded` line never reached.
- **The two arms recorded as fixture defects read that way from outside**:
  `no-raw-design-values.sh` exits at `:140` with *the geometry checks did not run* when `Shell`,
  `Activity` or `Boards` is absent — ahead of the rules under test — and the fix adds those
  directories without touching the rules.

The verifier armed both gates independently, in a clone so the subject tree stayed untouched, and
both bit: a deleted `tally.drop` gave `unaccounted 1` naming the reader and line at exit 1; an
intact-but-unmatchable import rule gave `HELD RAW-import`, `armed 28, 27 changed verdict`, exit 1.

## The block — one number, and it is this item's own shape

**The census's "before" column is not a measurement of the base tree.** It counts the gate's own
four readers and fourteen drop sites as pre-existing.

Run the shipped detector against a tree reconstructed from `git archive 72958de`, with the gate
placed **outside** `planning/` and `scripts/` so it does not scan itself:

| | Reported | Measured at the base |
|---|---|---|
| readers | 19 | **15** |
| discarding iterations | 27 | **22** |
| drop sites | 48 | **34** |

Copy `reader-accounting.py` into that base tree's `planning/` and the reported column reappears
exactly — `readers 19 … over 27 discarding iterations`, `drop sites 48`, `unaccounted 19`. So the
19 is reproducible and it is the instrument counting itself.

The after column already carries the evidence: `unresolved 67` is the verifier's measured 55 plus
the 12 the three new files contribute, with the per-file breakdown identical across both runs for
the other eighteen files.

**Two sub-figures are wrong the same way**: `table_ids` had **one** silent drop site at base
(`:53`), not three; `describes` had three (`:87`, `:90`, `:93`).

This is not a rounding complaint. *"Nineteen readers in this repository"* is commit `5a9569c`'s
subject line and §1's headline, and the number is an instrument counting itself into its own
denominator — the shape this item exists to catch, committed inside the item that catches it.

## Acceptance

1. `19 → 15`, `27 → 22`, `48 → 34` wherever they appear: the progress note, the tsv header, §1's
   headline, and the commit claim (a follow-up commit correcting it is fine; do not rewrite
   history).
2. `table_ids`' base drop-site count corrected to one, `describes`' to three.
3. **The corrected figures are measured with the gate outside the scanned directories**, and the
   command is pasted. Measuring the base with the instrument sitting in it is what produced this.
4. The sweep for those five numbers is **wrap-tolerant** — normalise whitespace across newlines
   before asserting absence. R17's gap-fix 2 returned a clean grep over a corpus that still held
   its claim because a hard wrap split the phrase; do not repeat it two items later.
5. Gates unmoved, **measured at this base and pasted**. This branch reads `make test` **1684 in
   209**, lint **0**, reconciler **0 across A–L**, `make all` **red at `parity-selftest` as at the
   base**.

## Register these, do not fix them

- **`D-g4-a`** — `planning/fidelity/servers.ledger.md` is stale on `main` after M21: it reads
  `tokens | clean | 25 matched, 64 pending` beside a register that now says `70 matched, 19
  pending`. Running the gate rewrites it. Nothing asserts its freshness. Found by M21's verifier,
  and it belongs to this item's class — a record nothing checks.
- **`D-g4-b`** — the reconciler's `merged ai/*` line reads a **live** `git branch --merged main`
  count, so it moved 29 → 26 when three branches were cleaned. A figure in a reconciliation report
  that changes without the files changing.
- **`D-g4-c`** — `make test` failed twice standalone on `AuthorizationURLBoxTests / "a waiter that
  is cancelled is resumed rather than stranded"` (`OAuthWireTests.swift:263`, a 3-second wall-clock
  budget), then passed inside `make all` and in isolation in 3.164 s, at load 900–945. Attributable
  to load but **not excludable as a real intermittency**, and recorded that way rather than as a
  flake. `G3` owns the only other wall-clock assertion in this suite.

## Scope

The census figures and their homes. **No change to either gate's logic** — both are verified
working and armed, and an edit there would put this item's evidence back in question.
