# Plan — G6: evidence that lives in `/tmp`, and dispatch artifacts written into the tree under test

Brief: `planning/features-to-triage/G6-evidence-that-lives-in-tmp-is-not-evidence.md`.
Triaged 2026-08-25 → To Do. Branch `ai/g6`, cut from `main` at `0e5ff49`.

## Tier

**Standard.** Four artifacts, one of them a gate, no product code touched. The two halves are
coupled by the brief's own argument and are delivered together: fixing only the `/tmp` half moves
briefs into worktrees and makes the tracked-artifact problem universal instead of occasional.

## What the grounding changed

Three of the brief's figures were re-measured on `0e5ff49` before planning, and two of them move:

- **`/tmp` is cited in durable specs, not only in progress docs.** `planning/specs/spec-P4.md`
  at 43, 85, 300; `planning/specs/spec-F1.md:166`; and six further specs the brief never names
  (`spec-R1`, `spec-R2`, `spec-R2W`, `spec-R3`, `spec-R6`, `spec-P2`). A spec is the most durable
  record in the pipeline, so this is the worst place the defect could have been sitting.
- **`WORK-ORDER.md` is on `main`, not in four of twelve worktrees.** It is tracked at the repo
  root at `0e5ff49` and is therefore present on **29 branches**, every one of which inherited it
  by being cut from `main`. The brief's *4 of 12* counted worktrees that had written their own;
  it did not notice the one every worktree already had. The file also carries
  `/Users/lukerhodes/Dev/mcp-router/.worktrees/M20` — one machine's absolute path, in a public
  repository.
- **Some `/tmp` instruments in the G5 family survived and one is already committed.**
  `planning/installed-claim-sweep.py` is the committed successor of the `/tmp/g5-mut*.py` family.
  So the R17 precedent was followed later in the same item's life, which is why the fix is
  *unenforced* rather than *unknown*.

## Deliverables

### 1 · `planning/foreign-path-gate.py` — the gate

A wrap-tolerant sweep over the tracked corpus that finds every **scratch-root** path
(`/tmp`, `/private/tmp`, `/var/folders`, `$TMPDIR`) and resolves each occurrence into exactly one
class of a total partition:

| class | what it is | blocks |
|---|---|---|
| `RUNTIME` | the token is in an executable or source file, constructed at run time by a committed instrument | no |
| `SUBJECT` | the token is in a record but is a value in the described system — an env value, a config example, a URL example | no |
| `CITED_LIVE` | the token is an artifact pointer in a record and the path exists on this machine now | **yes** |
| `CITED_DEAD` | the token is an artifact pointer in a record and the path does not exist | **yes** |
| `WITHDRAWN` | the token is an artifact pointer in a record, and the record marks it gone, unrecoverable, or reconstructed | no |

`CITED_LIVE` blocks because the brief's rule is *commit it or do not cite it*, and a live scratch
path is one reboot from being the other kind. `WITHDRAWN` is what makes the rule satisfiable
without deleting the history: a record may keep the path if it says, in a form a machine can read,
that the artifact behind it is gone.

**No ratchet.** G7 ratchets because its corpus holds 1291 bare citations and a gate demanding all
of them at once would never go green. The blocking set here is small enough to take to zero in one
pass, so this gate is an absolute zero. A ratchet that starts at zero is a worse gate than a
threshold at zero, because it invites a baseline bump.

**Presence control on every run.** `--control` builds a throwaway git repository in a temp
directory, plants one instance per class, runs the real classifier over it and requires each
planted answer exactly. One plant is discriminating rather than merely present: a withdrawal
marker separated from its citation by a hard wrap must read `WITHDRAWN` here and `CITED_DEAD`
under a line-anchored reading of the same fixture, and the run fails if those two agree. A
wrap-tolerant reader that would have answered the same either way has demonstrated nothing.

**Five named readings**, printed together and never blended, because five sweeps over one phrase
in one file once returned four different answers and none of the first four was right.

### 2 · Commit or withdraw every scratch citation in a durable record

Every `CITED_*` occurrence resolved one of three ways, and the record says which:

- **recovered** — the artifact still exists and is committed under `planning/verification/`;
- **reconstructed** — an equivalent instrument is committed and is marked *reconstructed*, because
  a rebuilt instrument is not the one whose results were recorded;
- **withdrawn** — the record keeps the path and marks it gone, so a reader can tell *the evidence
  is unrecoverable* from *the evidence was never gathered*, which is the distinction the brief
  says a dead path destroys.

### 3 · Where dispatch material lives

`.dispatch/` at the repository root, ignored. Inside the repository so a brief may cite a repo
path; outside every item's diff so no runner has to invent `bcc69dd`'s isolate-and-drop workaround
again. The ignore entry makes the choice once for everyone, which is the half the brief says a
per-runner fix cannot deliver.

And the sweep of what already landed: `WORK-ORDER.md` moves off the repo root. Three commits added
a dispatch artifact — `bcc69dd`, `9b13a49`, `30f639d` — and all three are ancestors of `main`.

### 4 · `planning/practices/EVIDENCE_AND_DISPATCH.md`

The two rules stated once, with the gate named as their enforcement.

## Test strategy

The gate is the test. Its own correctness rests on the presence control, which runs on every
invocation rather than behind a flag, and which fails if the wrap plant classifies identically
under both readings. Beyond that: `python3 -m py_compile` on the new instrument, the gate itself
at exit 0 over the fixed corpus, and `planning/claim-sweep.py` and `planning/null-run-gate.py`
re-run to show this diff moved neither.

No Swift or TypeScript is touched, so `make build` and `make test` are not in this item's blast
radius and are not run. That is a scope statement, not a skipped gate.

## Not in scope, and why

**Machine-durable absolute paths** — `/Users/…`, `~/…` — occur in 67 tracked files. They are a
different defect: a scratch path fails because the artifact evaporates, a machine path fails
because the reader is on another machine. This gate counts and prints them and blocks on none,
and the count is registered as a follow-up. Folding it in would put a third, uncoupled axis into
an item whose whole argument is that its two halves are coupled and a third neighbour is not.

**`planning/citation-gate.py`** (branch `ai/g7`) is the adjacent gate and is not extended. It asks
whether a `path:line` pointer resolves; this asks whether the artifact behind a path survives and
sits inside the repository. Different extractor, different classes, different remedy. They sit
side by side in `planning/` and each names the other's boundary.
