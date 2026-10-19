# Re-vendor test-campaign 0.9.2 → 0.20.0: defect verdicts and gate results

**Not merged.** The re-vendor this file measures stayed on `ai/revendor-campaign` (0d5a79ea): 0.20.0 closes none of the seven open instrument defects that 0.9.2 does not already close, and it turns `capture-lineage --gate` red by a rule change (a verdict counts only when it names a judge). `vendor/test-campaign/` on main is still 0.9.2. The verdicts below place DEF-051, 052, 054, 055, 056 and 061 upstream, in fledgeling-plugins, where a fix has to land before any re-vendor is worth taking.

Measured 2026-10-18 on `ai/revendor-campaign`. The vendored copy is `plugins/test-campaign/` at fledgeling-plugins `13dff4e90b8c7ac3c4da74f1919ce3850de8f3dd` (2026-10-16). The tree checksum is `2b6c8b03f2419c20ae1bf8eeba297773a68100ad0cd4db79a0b03ff2816c7fab`, and `diff -r` against a fresh `git archive` extract exits 0 with no output.

Seven of the eight in-scope defects are still present in 0.20.0. DEF-053 is fixed. The four documented gates and the five bin gates that resolve the vendored tree were run. Two gates are red: `campaign.py check`, which is red under 0.9.2 too and points at case data, and `capture-lineage.py --gate`, which turns red because 0.20.0 counts a verdict as judged only when the row names its judge. No inventory status, ratchet or campaign datum was edited.

## Gate results

Each 0.20.0 run is `python3 vendor/test-campaign/skills/test-campaign/scripts/<script> …`, run with `PYTHONDONTWRITEBYTECODE=1` so nothing is written into the vendored tree. The 0.9.2 control is the same script from `git archive 28ecd67`, run over the same `planning/test-campaign`.

| Gate | 0.20.0 exit | 0.9.2 control | Verdict |
|---|---|---|---|
| `campaign.py check planning/test-campaign` | **1** | 1 | Red under both versions, with the same six lines. `CASE-0262` and `CASE-0263` claim `effect-witness` with no recorder, no effect class and no count. This is a finding about the campaign data, not a change in the instrument. |
| `strict-check.py planning/test-campaign` | 0 | 0 | Green. Output is byte-identical to the control (`diff` exit 0). Ratchet 121, measured 135. The gate suggests raising the ratchet; it was not raised. |
| `capture-lineage.py planning/test-campaign --gate` | **2** | 0 | **Red under 0.20.0 only, a behaviour change.** 0.20.0 prints `JUDGED 0 of 21`, `23 verdict row(s) name no judge or are marked advisory`, and `ratchet: 15 — FAILED, judged fell to 0`. The 0.9.2 control prints `JUDGED 16 of 21 (76%)`. See the note on verdict rows below. The ratchet was not re-pinned. |
| `vacuity-check.py planning/test-campaign` (as the README writes it) | 0 | 0 | Green in both. The findings differ: 0.20.0 reports `findings=198` and 0.9.2 reports `findings=1`. This is a behaviour change, explained below. |
| `vacuity-check.py planning/test-campaign --gate` | 1 | 1 | Red under both versions. The shared finding is REQ-016, which declares an outbound-socket effect with no `provider`. 0.20.0 reports 198 findings in total, and its log attributes 196 of them to the blind pass. |
| `planning/test-campaign/bin/blind-vocabulary-arm.py` | 0 | — | `blind arm: 6 of 6 checks as expected`. |
| `planning/test-campaign/bin/effect-class-census.py --control` | 0 | — | `control: 7 of 7 arms as expected`. |
| `planning/test-campaign/bin/effect-class-census.py` | 0 | — | `findings: 0`. Resolves the vendored tree first and also the 0.19.1 plugin cache. |
| `planning/test-campaign/bin/vocab-differential.py --control` | 0 | — | `control: 14 of 14 arms as expected`. |
| `planning/test-campaign/bin/vocab-differential.py` | 0 | — | `examined=12 … 2 inconclusive (SURF-009, SURF-028) … findings: 0`. |

The stop-and-report condition did not trigger. All four gate scripts exist under the same names in the upstream commit, and the flags the repo uses (`check`, `--gate`, `--control`) are present.

### Why `capture-lineage` went red

`def is_judgement(v: dict) -> bool:`, `capture-lineage.py:342-354` at `0d5a79ea` counts a verdict as a judgement only when it names a judge (`judge.model`, a non-empty `judge` string, or a `model` field) and is not marked advisory. All 23 rows in `planning/test-campaign/witness-verdicts.json` carry none of `judge`, `model` or `advisory`, so none counts. The same 23 rows were counted as judged under 0.9.2. The rule dates from 0.19.0, and its comment records why it was added. This is an instrument behaviour change. The provenance gap it exposes is in the data: the verdict rows name no judge. Recording the judge in those rows is the owner's call and was not done here.

### Why `vacuity-check` reports 198 findings

0.20.0 reads `campaign.json` (`testRoot: app`, and `blindVocabulary` with `only: true`) and runs the blind pass by default. 0.9.2 runs it only with `--tests <root>`. With `--tests app` 0.9.2 reports `findings=121`, so the default changes the count by its own mechanism. The 0.20.0 log reads `blind: examined=2644 mutating=483 re-read-after=287 blind=196` and `blind: NOT MEASURED — unterminated string literal`, which the log attributes to the line `for primitive in ["42", #""hi""#, "true", "false", "0", #""""#] {`, `PrimitiveBodyTests.swift:140` at `0d5a79ea`. Precision of the blind findings was not re-measured.

## Defect verdicts

Verdicts are `fixed`, `still present`, or `cannot tell`. Line numbers are in 0.20.0 (`vendor/test-campaign/skills/test-campaign/scripts/`), and each one is framed at `0d5a79ea`, the tip of `ai/revendor-campaign`, which carries that copy. The upstream commit `13dff4e9` is not an object in this repository, so it cannot be the tree a frame is checked against. The copy-run figures come from `campaign.py report`, `witness-worklist.py` and `attach-shots.py --apply --filename-only`, each run over a throwaway copy of `planning/test-campaign` in `/tmp`, so the repo's data was not touched.

| ID | Verdict | Evidence |
|---|---|---|
| DEF-051 | **still present** | The judgeable line is still `judgeable = [p for p in pairs if p.get("reference")]`, `witness-worklist.py:90` at `0d5a79ea`. Run on the copy: `pairs=20  judgeable=17  WITHOUT a reference=3`. The judgeable set includes SURF-009, whose `pairs.json` entry has a `reference` (`mock/SURF-009.png`) and `shot: null`. |
| DEF-052 | **still present** | `fails = [c for c in cases if state_of(c.get("status")) == "fail"]`, `evidence-page.py:520` at `0d5a79ea` feeds the Defects section, and `:305` takes the nav count from `counts["fail"]`. On the copy: 22 open defects in `inventory.json`, 15 of them absent from `evidence.html`. `ledger.md` (from `campaign.py report`) names 0 `DEF-` ids. |
| DEF-053 | **fixed** | `EFFECT_RUNGS = {"outcome", "metamorphic", "effect-witness",`, `strict-check.py:59` at `0d5a79ea` opens the rung set with `"outcome"`, `"metamorphic"` and `"effect-witness"`. The same line is in the 28ecd67 copy that was vendored before this change, so the fix was already in the vendored tree; its `awaiting-re-pull` status is stale for this repo. 0.20.0 output is identical to the control. |
| DEF-054 | **still present** | `and "mock" not in {part.lower() for part in p.relative_to(shots_dir).parts[:-1]}`, `attach-shots.py:101` at `0d5a79ea` excludes an image only when a path component is exactly `mock`, so `mock-hidpi/` gets through. On the copy, `--apply --filename-only` set `shot` to `evidence/shots/mock-hidpi/SURF-00N.full.png` for SURF-001 through SURF-011, which is the design render. The `UNCORROBORATED` block still prints surface ids (SURF-001 … SURF-011, SURF-022), not file paths. |
| DEF-055 | **still present** (structural causes; precision not re-measured) | Cause 1, scanning every `func`: `decls = [(block["start"], block["name"], "decl") for block in swift["blocks"]]`, `vacuity-check.py:796` at `0d5a79ea` builds `decls` from all Swift blocks, not only `@Test` ones, and the tool prints `uncalled named functions remain candidates, not proven test entries`. Cause 2, file-scoped helper exclusion: `:816` counts calls within the file's own `src`. Cause 3, the lookbehind lets a dot through: `:844` says `The lookbehind still allows a method call`. The `reset` example is no longer reached, because `reset` is not in the declared 19-verb `blindVocabulary`. Cause 4, last mutator by position with no `defer` handling: `grep defer` finds only the string `deferred` (`:442`). |
| DEF-056 | **still present** (count has grown) | `by_surface.setdefault(c.get("surface", "—"), []).append(c)`, `campaign.py:2558` at `0d5a79ea` buckets each case with `setdefault(c.get("surface", "—"))`, and `:2573` emits rows only for `inventory["surface"]` ids. The ledger header reads `156 cases`, the table has `137` rows, and the gap is exactly the 19 cases with no `surface`. None of CASE-0145–0148 or CASE-0151–0154 appears in the table. |
| DEF-061 | **still present** | `def tie(target: str, route: str) -> tuple[bool, str]:`, `capture-lineage.py:109-120` at `0d5a79ea` (`tie`) has no template handling. Direct call: `tie("mac/servers/g17-capability/document", "app://mac/servers/{server}/document")` returns `(False, "target … does not resolve to route …")`; the literal control returns `(True, "")`. The gate does not trip today only because SURF-028 has no capture. |
| DEF-057 | **partly closed** (not in the step list; recorded for completeness) | The vendored tree is now 0.20.0, and the documented gates and the bin gates resolve it first. Two things remain. `effect-class-census.py` and `blind-vocabulary-arm.py` also read the 0.19.1 plugin cache. The submodule pointer `.claude/plugins/fledgeling-plugins` is still at `baaf79ab`, which the DEF-057 record places at test-campaign 0.5.0. That pointer was not touched here and its version was not re-measured. |

## Not done, and why

- `inventory.json` defect statuses, ratchets (`capture-ratchet.json`, `strict-ratchet.json`) and campaign data were not edited.
- The README's cache-diff check (`diff -r … ~/.claude/plugins/cache/…/0.20.0`) was not run. The cache holds 0.19.1, so it would compare against the wrong version. Only the archive check was run.
- The README's gate figures (`69/76`, `62 of 76`) describe the 2026-08-20 data. The campaign data has moved on (156 cases today), so those numbers are not comparable to today's runs.
