# Where evidence lives, and where dispatch material lives

Two rules with one root, settled by `G6` on 2026-08-26. They are stated together because each
fix displaces the other's problem: move a brief out of `/tmp` and it lands in a tree under test,
and fixing only one half makes the other half universal instead of occasional.

The root is one sentence: **a record's pointer must resolve where it is read, not merely where it
was written.**

---

## 1 · An artifact a record cites as evidence is committed, or the record does not cite it

`/tmp` is emptied. On 2026-08-23 a terminal died and every `/tmp` artifact this fleet had cited
went with it — four sweeps and a build log, each named by a durable record as the thing that
proved a guard was armed. One of them carried an *accepted verdict*: `G5` gap-fix 2 recorded four
planted faults producing four `FAIL` rows, plus three the verifier planted itself, all against
`/tmp/g5gf2/sweep2.py` (gone). The verdict was sound when given and is now unfalsifiable.

**This is worse than a stale number, and the asymmetry is the point.** A stale literal is wrong and
*checkable*: run the thing, compare, see the disagreement. A dead path produces no wrong answer to
catch — only an absence, and an absence reads identically to *not yet run*. A reader who cannot
find the file cannot tell whether the evidence was weak, strong, or never gathered.

So:

- **A load-bearing instrument is committed.** A sweep, a fixture, a mutation harness, a probe — if
  a record cites its result, it lives in the repository. `planning/claim-sweep.py` is the
  precedent and it survived the same crash that took the others; they were written days apart for
  the same shape of problem and only one is still evidence.
- **A record may keep a dead path only by marking it**, and the marker must be **closed**:

  ```
  parenthesised, marker word first    `/tmp/g5gf/sweep.py` (gone)
                                      `/tmp/g-*.log` (not retained)
  a cell holding only the marker      | `/tmp/g5gf2/sweep2.py` | gap-fix 2's | gone |
  bold and closed                     `/tmp/g5gf3/sweep3.py` **gone**
  ```

  Vocabulary: *gone, unrecoverable, not recovered, not recoverable, no longer exists, does not
  exist, not retained, never retained, withdrawn, deleted, reconstructed, recovered*. An
  explanation may follow the marker word inside the same parentheses.

  The closing side is load-bearing. A looser grammar that accepted any of `(`, `|`, `*` or a dash
  before one of those words was broken three ways in a single out-of-family review: a table cell
  reading `| recovered 40 items |`, a next bullet reading `* deleted the old cache`, and prose
  reading *the runner \*recovered\* state* each satisfied it while withdrawing nothing. All three
  are now negative controls in the gate.

  The marker is what restores the distinction the defect destroys: *the evidence is unrecoverable*
  now reads differently from *the evidence was never gathered*.
- **One marker per citation.** The gate's window stops at the next scratch path, so a single
  trailing *(both gone)* withdraws only the second of two. A marker shared between pointers is a
  marker whose subject a reader has to work out, and working it out is the labour the form exists
  to remove.
- **A rebuilt instrument is not the one whose results were recorded.** Say *reconstructed* and
  never *recovered*, and be suspicious of a reconstruction whose report survives only as counts —
  an instrument rebuilt to return the recorded numbers is an instrument constructed to agree.
- **A live scratch path is not better than a dead one.** It is worse, because it still resolves.
  `R17` gap-fix 3 measured exactly this: `/tmp/g-gate.log` (gone) held *a different repository's* build
  output while a record pointed at it. A path that answers with something that is not what was
  measured is the failure the reader cannot see.

Enforced by **`planning/foreign-path-gate.py`**, which blocks any hand-written record citing a
scratch path without a marker. Its sibling `planning/citation-gate.py` asks whether a `path:line`
pointer still resolves; this asks whether the artifact behind a path survives at all. A durable
artifact with an imprecise pointer fails there, a precise pointer to a dead artifact fails here,
and neither implies the other.

---

## 2 · Dispatch material lives beside the work, not in it

Work orders, gap-fix briefs and verify briefs are the dispatcher's prompts. They are not project
artifacts, and they are not evidence.

- **Live dispatch material goes in `.dispatch/`**, ignored by `.gitignore`. Inside the repository,
  so a brief can cite a repo-relative path and satisfy *a brief cites a repo path or it cites
  nothing*. Outside every item's diff, so it cannot be swept into a feature commit by a `git add`.
- **The ignore entry is the mechanism, not the convention.** A convention is followed by whoever
  read it; `.gitignore` is followed by everyone. One runner invented an isolate-the-commit-and-drop-it
  workaround on its own and eleven others did not, which is what a per-runner fix looks like.
- **`/WORK-ORDER.md`, `/GAPFIX-BRIEF.md` and `/VERIFY-BRIEF.md` are ignored at the root**, because
  the root is exactly where the three that landed were written. The rules are root-anchored, so a
  file genuinely belonging at `planning/WORK-ORDER.md` is unaffected.
- **What already landed is recorded, not erased.** `planning/dispatch-records/` holds the committed
  copies verbatim, with the commits that added them named. History keeps the content either way; a
  file nobody can find is not a record.

The hazard this closes is older than the fleet that named it — one of the three adding commits
predates it. And it was larger than first measured: `WORK-ORDER.md` sat at the root of `main`, so
it was inherited by **29 branches**, and every runner's worktree opened with another item's work
order exactly where a runner looks for its own.

---

## What each rule does not cover

**Machine-durable absolute paths** — `/Users/…`, `~/…` — are a different defect with a different
remedy: a scratch path fails because the artifact evaporates, a machine path fails because the
reader is on another machine. `foreign-path-gate.py` counts them on every run and blocks on none.
At `0e5ff49` that count was 231 files.

**A citation's precision** is `G7`'s, not this file's. Carry the frame — anchor, line, tree — on
every citation and not one dead `/tmp` path comes back; commit every instrument and a bare line
number still rots. Both must hold and neither implies the other.
