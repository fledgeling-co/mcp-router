# R17 gap-fix 3 — one claim, two homes, and a sweep that could not see one of them

**Parent:** R17 · **Verdict:** Needs More Work, 2026-08-22 (third verification)
**Worktree:** `.worktrees/R17`, branch `ai/r17`, base `13e728b`

## What passed

Criteria 1, 2 and 4. The withdrawn clause is gone from `:114` and a wrap-tolerant sweep finds the
assertion nowhere — the surviving `indifferen*` hits at `:100` and `:109` are the withdrawal's own
reasoning, and the archived Fable lane quotes it in order to refute it. The six-site list is right,
with both inventories **re-derived from source rather than carried**: node has 5 `saveManifest`
sites and `writeFileSync` appears only inside `saveManifest`; Swift has 3 `ManifestIO.save` sites
and no other writer. Verb attributions spot-checked correct. Gates unmoved.

## The block — criterion 3, and the instrument is the finding

`planning/evidence/R17-acceptance.md:472` still reads *"the declaration names **all four uncovered
sites**, `src/index.ts` among them"*. That is the document speaking in its own voice inside an
`agy` rebuttal — not archived quotation — and it is now false of the declaration it describes,
because `surface.tsv` names six.

**The runner's sweep could not see it.** The file's hard wrap splits the phrase across lines
472–473, and the sweep's regex is line-anchored. Measured:

```
grep -c "all four uncovered sites" planning/evidence/R17-acceptance.md   →  0
python3 -c "re.findall(r'all\s+four\s+uncovered', open(f).read())"       →  1
```

So the sweep returned clean over a corpus that still contains the claim. This is the **fourth**
consecutive pass to block on this claim class, and the first where the instrument rather than the
diligence is at fault: the previous three corrected a claim in some of its homes, and this one
could not read one of its homes at all.

`:647` fails too, arguably rather than outright. Read strictly as node-scoped it is true — one node
save covered, four node saves uncovered. But its subject is *what the declaration says*, and the
declaration now says six.

## Acceptance

1. `:472` reads *"names all six uncovered sites"*.
2. `:647` reads *"which one save on each side it covers and which six it does not"*.
3. **The sweep is wrap-tolerant and its output is pasted.** A line-anchored grep is not sufficient
   evidence for a claim about a hard-wrapped corpus; normalise whitespace across newlines, or read
   whole files, before asserting absence. Sweep every tracked file, not just the two edited.
4. Gates unmoved. **Measure them at this base and paste what they return** — do not carry a figure
   from another branch. On `ai/r17` the third verification measured `make test` **1686 in 210**,
   `make lint` **0 over 531 files**, `make parity` **358/358**, `parity-cli.sh` **18/0** with all
   four `cli-watch` scenarios ok, and the reconciler **0 across A–K** with 217 register rows. Check
   L does not exist on this base and `A-L` is unmeetable here; A–K is the correct claim.

## Correct `D-r17-d` while you are in the file

The row states the red rate as *"about a quarter to a third of runs"*. The third verification
refuted that as stated and **strengthened the substance**:

- Serially on an idle tree it never reds: **0 of 40** on this branch's `surface.tsv` and **0 of 40**
  on main's.
- Under four concurrent copies it reds hard: **53 of 104** on the branch, **24 of 72** on main —
  which settles the reproduces-on-main half properly.

So the rate is **concurrency-conditional, not flat**, and the row should say so.

And the mechanism is now **proven rather than suspected**, more strongly than the row claims.
Across those runs the gate reported ten fixture names *in both directions* — `add-refused`,
`added`, `approve`, `auth-start`, `patch-response`, `removed`, `server-placarded`, `server-tools`,
`servers`, `unauthorized` each appearing both as *on disk and has no manifest row* and as *carries
a row, which is not on disk* — over a git-tracked 24-file directory with no local modifications.
**Two mutually exclusive findings about one unchanging file can only come from the comparison**,
which is `parity-manifest-check.sh:431` and `:437` piping a `printf` into `grep -qxF` per item and
reading any non-zero exit as *not found*. The same shape appears at a second site
(`src/index.ts dispatches "serve"`), so it is not confined to the fixture loop. Direction stays
false-RED.

Record it; do not fix it. This item's scope carries no code.

## Scope

`planning/evidence/R17-acceptance.md` (two lines) and the `D-r17-d` row in `ORCHESTRATOR.md`.
**No code.** Nothing under `src/`, `app/` or `scripts/`.
