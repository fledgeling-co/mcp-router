# R17 gap-fix 2 — two clauses, both a withdrawn claim outliving its withdrawal

**Parent:** R17 · **Verdict:** Needs More Work, 2026-08-22 (second verification)
**Worktree:** `.worktrees/R17`, branch `ai/r17`, base `55075ed`

## What held, and how strongly

**"No behaviour changed" was proven above the rung it was claimed at.** Rather than filtering the
diff for comments, the verifier compiled both revisions: `tsc --removeComments` on `src/watch.ts`
gives byte-identical JS (md5 `8602f002…` both sides) and `swiftc -frontend -dump-parse` on
`WatchIndexing.swift`, normalised, gives byte-identical parse trees (md5 `91b7eeff…`). Those two
files are the only source the pass touches, so **the edits are ruled out of the named red by
construction rather than by observation.**

**The strengthened route account survived the strongest attack available and is under-stated.** The
verifier built the R19-only world — delete removed, snapshot-then-save window intact — in the shape
of the owner's machine and ran a real `index --force` against a held-open fire. R19 alone admits
exactly **two** outcomes across the two write timings, and the measured partition is **neither**.

Every gate green, every line citation resolving, `R20` filed with a real work order, and the named
red confirmed registered by name in `D-r7-x` and by file-and-line in `D-g3-s`.

## BL-1 — a withdrawn claim standing five lines from its withdrawal

`R17-acceptance.md:114` still reads *"R19's window is indifferent to whether a server is staged"* —
the framing the same section records as broken at `:108-109` and replaces at `:104-105` with *"it
predicts its inverse"*.

**This is the third consecutive pass to block on that class**, and the second on this item: a
correction landing in some of the places its claim appears. One clause.

## BL-2 — the uncovered list is wrong in both directions

`R19.md:51` says *"Those four still carry the same read-then-save window on both sides"*. False, and
the same pass refuted it:

- **Six** sites are uncovered, not four.
- `src/index.ts:146` and `:186` have **no Swift `ManifestIO.save` twin**, so the symmetry claim is
  not merely imprecise, it is untrue of half the list.
- The two Swift sites that *are* uncovered — `AuthRoutes.swift:120` and `ServicePorts.swift:391` —
  appear **nowhere** in `R19.md` or in `surface.tsv`, which is where the declaration itself lives.

`R17-acceptance.md` and `WatchIndexing.swift` both state it correctly, so the correction landed in
two of the four places the claim appears — BL-1's shape again, in the same pass.

**The consequence is downstream**: R19's runner is sent looking for four Swift twins that do not
exist, and past the two that do.

The settled counts, measured from both sides: node has **5** `saveManifest` sites (`watch.ts:292`,
`index.ts:146`, `index.ts:186`, `control.ts:262`, `control.ts:432`) with `saveManifest` the only
writer; Swift has **3** `ManifestIO.save` sites (`AuthRoutes.swift:120`, `ServicePorts.swift:391`,
`WatchIndexing.swift:187`) and no other manifest writer. **This number has been wrong three times in
three directions** — five, then three, then four-of-six. State both figures and where each is from.

## Acceptance

1. The withdrawn clause is gone from `R17-acceptance.md:114`.
2. The uncovered list names six sites, drops the false symmetry, and names the two Swift sites in
   `surface.tsv` as well as in `R19.md`.
3. **A grep proving neither claim survives anywhere else.** Two passes have now corrected a claim in
   some of its homes; find them all before declaring it.
4. Gates unmoved: `make test` 0 at 1686/210, lint 0 over 531 files, parity 358/358, manifest-check
   92 rows, reconciler 0 across A–L, `parity-cli.sh` 18/0 with all four `cli-watch` scenarios green,
   `acceptance-r6` clean, R7 lane 0.

## Register these, do not fix them

- **`VER2-R17-3`** — the same divergence is readable from source on the `index` and `import` verbs
  and is filed as merely unmeasured. Swift routes every upstream through `ManifestIndexer.index` →
  `record`, re-loading at `ServicePorts.swift:381` and saving at `:391` **per entry**; node's
  `cmdIndex` loads once at `src/index.ts:177` and saves once at `:186`, and `cmdImport` at `:101`
  and `:146`. Same read-window disagreement the declaration covers for `watch`, on the writer R19's
  own reproduction used. Established by reading, not measuring — say so.
- **`VER2-R17-4`** — LEDGER's compressed R17 row reads *"the orchestrator's five save sites corrected
  to three"*, which reads as five having been wrong. Five was correct for node. ORCHESTRATOR states
  it properly.
- **`VER2-R17-5`** — the replacement figure is as unstable as the one it replaced: `parity-oauth.sh`
  standalone gave **21/21 twice** on this branch, the number that was struck through. The document's
  conclusion survives, since it says the count moves under load; the table presents `19/21 each` as
  a measurement of the branch.

## Scope

`R17-acceptance.md`, `R19.md`, `surface.tsv`, and the register rows. **No code.** The compiled-parse
proof above is what makes that verifiable, and a second pass should keep it true.

---

## Dispatch defects — 2026-08-22, found by the second runner, not by the brief

A duplicate runner was dispatched onto this item by orchestrator error. It detected the first
runner mid-write, **stopped before editing anything**, and handed back two findings plus a third
this note adds. All three have one cause and it is the orchestrator's: **the worktree is behind
main, and the brief's gate line was written against main.**

`.worktrees/R17` is at `55075ed`. `R17-gapfix-2.md` was committed to main at `afc087f` and check L
at `b616dc1`, both after that base.

1. **The work order is not in the worktree.** The dispatch told the runner to read
   `planning/features-to-triage/R17-gapfix-2.md`, which does not exist at `55075ed`. Both runners
   proceeded from the prompt body, which restates the acceptance closely enough — that is luck
   rather than design, and it is the same shape as the `spec-R4` unmeetable precondition already
   in the register.

2. **`reconciler 0 across A-L` cannot be met from this base.** The worktree's
   `ledger-reconcile.py` has A–K (`grep -c '"L"'` → 0 here, 1 on main). Read-only baseline
   measured in the worktree: `reconciled — no findings across A, B, B-range, C, D, E, F, G, H, I,
   J, K`, exit 0, 85 ids, 455 rows, 213 register rows.

3. **And check L would go red here if it were present.** Both committed conflict blocks are still
   in this worktree's `ORCHESTRATOR.md`, at `:242-249` and `:643-664` — the exact defect check L
   was written to catch, already fixed on main at `b616dc1` and not yet on this branch.

**The dispatch therefore contradicted itself**: it froze the branch off main *and* set an
acceptance that only main can satisfy. Same shape as M23 gap-fix 8's freeze-versus-acceptance
conflict. Resolution is the orchestrator's at finalisation — merge main into `ai/r17`, which is a
base update rather than a merge *to* main, then re-run the gate line as written.

## A fourth home of the withdrawn claim, and it is not in the current diff

The second runner swept further than the coverage paragraph and found two more occurrences of the
"four" claim inside `R17-acceptance.md`:

- `:490` — *"the declaration names all four uncovered sites"*, inside an `agy` rebuttal.
- `:645` — *"which one save it covers and which four it does not"*.

Neither is touched by the working-tree diff as of 12:00. Acceptance criterion 3 exists precisely
because two passes have now corrected a claim in some of its homes; **if the sweep stops at the
coverage paragraph this criterion fails a fourth time on the same shape.** Verify against these two
line numbers specifically.
