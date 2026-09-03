# X8 — two campaign detectors report findings they cannot support

**Category:** instrument · **Found:** 2026-08-21, by arming and sampling the detectors
**Defects:** DEF-055, DEF-054 · **Upstream:** `github.com/fledgeling-co/fledgeling-plugins`

## Where this can be done, and it is not here

Same constraint as X7, and for the same reason: both defects are in `test-campaign` 0.9.2
on the machine, and the vendored submodule is 0.5.0 and contains neither script (DEF-057).
An mcp-router runner cannot close this. Route it upstream or hold it.

## What was measured

**DEF-055 — the blind-mutation pass is right about almost nothing it reports.** Given this
project's verbs in `campaign.json`'s `blindVocabulary`, `vacuity-check.py` reports
`examined=1661 mutating=320 re-read-after=232 blind=88`.

It was armed both ways before being doubted: a probe `@Test` that mutates and never
observes (`var acc: [Int] = []; acc.removeAll(); #expect(Bool(true))`) moved the count
88 → 89 → 88, with `examined` and `mutating` each moving by one in step. The check detects
a genuinely blind test. Log at `planning/test-campaign/evidence/arming/blind-mutation.arming.log`.

Then it was sampled. Of the 88, fifteen have no assertion of any kind after the last
mutating call — the stratum where a real finding is likeliest. Nine were read in full; two
were not tests. **All seven remaining real tests observe after mutating**, through idioms
no reader verb names: `client.calls.last?.operation`, `seen.filter { … }`, and a rebind of
the same port that throws if the socket was not released. Precision on that stratum is
0 of 7.

Four mechanisms, two structural and two specific to Swift:

| | What it does | Cost on this suite |
|---|---|---|
| Population | scans every `func`, not every `@Test` | 130 non-tests examined |
| Helpers | exclusion is file-scoped, so a stub in `TestSupport.swift` called from elsewhere reads as a test | 21 of the 88 |
| Lookbehind | `(?<![A-Za-z0-9_])` cannot exclude a dot, so the enum case in `== .reset(.clearPlacard)` counts as a mutating call | 41 of 72 re-measured |
| Ordering | takes the last mutator by source *position* | misreads `defer`, loop bodies, and a mutator inside its own `#expect` |

The tempting repair — adding `calls`, `operation` and `filter` to the reader vocabulary —
was deliberately not done here, and should not be done upstream either. Those terms are
generic enough to suppress true findings as well as false ones, so it would lower the
number without improving what the pass knows.

**DEF-054 — `attach-shots --apply` would file the design as the build.** On this campaign
it would repoint 11 surfaces from their build capture to
`evidence/shots/mock-hidpi/SURF-00N.full.png`, which is a render of the **design**, while
every other gate stayed green. Its report names the surface rather than the file, so the
substitution is not visible in what it prints.

## What to deliver

1. `vacuity-check.py`'s blind pass takes its population from the harness's own test
   discriminator rather than from every `func`. For swift-testing that is a `@Test`
   annotation; make the discriminator per-language and declared, so a project that gets it
   wrong finds out rather than getting a confident number.
2. The helper exclusion works across the test root, not within one file. A name defined
   once and called from anywhere else is a helper.
3. The mutator match rejects a dot-prefixed occurrence in value position. An enum case
   inside an assertion is not a call the test made.
4. "After the last mutator" is computed so that `defer`, loop bodies and a mutator inside
   its own assertion are not misread. Where that cannot be settled cheaply, report the
   finding with the construct named, so a reader can dismiss it in one look instead of
   opening the file.
5. `attach-shots` refuses to attach a capture whose recorded `target` disagrees with the
   subject's, and prints the file path it would attach rather than only the surface id.

Each of 1–4 can be checked against this repo: the 88 should fall, and the seven tests named
above should stop being reported.

## Scope

Deliver those five. The pass's sensitivity is proven and is not the problem — a fix that
lowers the count by widening the reader vocabulary would hide the defect rather than fix
it, so change what the pass *examines* and *matches*, not what suppresses it.

## A sixth, added 2026-08-27 by G29 — the tie pass cannot read a route template

`capture-lineage.py`'s `tie()` normalises scheme, host, port, query and fragment away and then
asks for string equality or a suffix match. A surface whose route is parameterised —
`app://mac/servers/{server}/document`, one address per server — therefore fails against every
capture of it, because `mac/servers/g17-capability/document` is neither equal to nor a suffix of
`mac/servers/{server}/document`. The gate reports UNTIED, *"the recorded target does not resolve
to the subject's route"*, over a capture that was pointed at exactly the right thing.

Measured on `mcp-router` against the vendored 0.9.2 and the machine's 0.15.0, whose `tie()` is
byte-identical. `references/capture-lineage.md` already says resolution is *"deliberately loose on
the parts a harness legitimately varies"*; a `{server}` segment is such a part, and it is the one
the looseness does not reach.

6. `tie()` treats a route segment of the form `{name}`, `:name` or `*` as matching exactly one
   non-empty target segment. Literal segments, the source-file refusal and the normalisation are
   unchanged, and the seeded swap must still go red — a segment wildcard must not make two
   different boards tie. Checkable against `mcp-router`: SURF-028's frames stop being reported
   untied and nothing else moves.

Recorded as `DEF-061` in that campaign's `inventory.json`, with the reason the fix was not applied
locally: `vendor/README.md` pins the tree by checksum so the gates re-run from a clone, and a
`tie()` that behaves one way in one repository is not evidence anywhere. Referred out of family
(gpt-5.6-sol, high effort) before deciding, and it reached the same conclusion independently.


---

## WE3 ADJUDICATION, 2026-09-03 — **item 5's first half was NOT upstream. It was this repository's directory name, and it is fixed.**

### The "Where this can be done, and it is not here" paragraph is stale, same as X7's

It says both defects are on the machine and the vendored submodule contains neither script.
`vendor/test-campaign/` has carried **0.9.2** — `attach-shots.py`, `vacuity-check.py` and all —
since 2026-08-22, one day after this brief. The blocker moved from *"the code is at no path
here"* to *"the code is here and pinned by checksum"*, which forbids the same edit for a
different reason and, unlike the old one, let the defect be read closely enough to find out where
it actually lived.

### DEF-054 — split, and the split is the finding

**The instrument already ships the guard.** `attach-shots.py:101` at `5934c38f` drops any image with a
directory part named EXACTLY `mock` before matching, and `capture-lineage.py:150` at `5934c38f` applies the same
rule; both lines are byte-identical in the machine's 0.17.0. This repository put its hi-dpi
renders at `evidence/shots/mock-hidpi/`, which is not that name, so both tools walked them. The
defect was the directory name.

**Measured before and after**, against the pinned 0.9.2, on a scratchpad copy:

| | images walked | attached to a design render |
|---|---|---|
| `evidence/shots/mock-hidpi/` | 69 | **SURF-009** → `mock-hidpi/SURF-009.full.png` |
| `evidence/shots/mock/hidpi/` | 58 | none |

SURF-009 is the one surface with a rendered design of record and no build capture at all
(DEF-051), so nothing outranked the render. **The eleven in this brief's original measurement are
not withdrawn** — `sorted()` over `Path` case-folds on Windows, where `mock-hidpi/` sorts *before*
`SURF-00N.build.png` and loses the last-write-wins race, while on the macOS tree this was measured
on it sorts after and wins eleven times. Ten of the eleven were held back by collation, not by
anything anybody chose.

**Armed:** `planning/mock-exclusion-gate.py`, in `make lint`. It does not check the directory
name — that is not a property. It holds the equality: the set `bin/capture-manifest.py` calls a
render of the design and the set the vendored rule refuses to attach must be the same set, both
directions. Both sides are read rather than copied (`MOCK_DIRS` by import; the exclusion line out
of `vendor/` under a recorded SHA-256), so a re-vendor that moves the rule exits 2 NOT COMPARED
rather than asserting the old one. Watched to fail first: 11 findings, then green. Transcript at
`planning/evidence/WE3/mock-exclusion-gate.baseline.txt`.

**Item 5's second half stays (A) and unchanged.** The report still prints surface ids rather than
the file — `attach-shots.py:201` at `5934c38f`, `print(f"   {sid}")` — and `--apply` still checks only that a
`target` field is *present* (`:167`) rather than comparing it to the subject's route. Exact remedy
in DEF-054's `resolution`.

### DEF-055 and item 6 — not adjudicated here

DEF-055 is another runner's member. Item 6 (`tie()` and route templates) is DEF-061's, likewise.

### A finding this brief's shape predicts, filed rather than folded in

While arming the effect-class axis: **31 of the 49 cases naming a `witness.effect` name a class
`EFFECT_CLASSES` does not carry**, all of them `effect-witness · pass`. `campaign.py` counts them
into its `40 effect-witness claim(s) with no recorder, no effect class, or a count of zero` and
then caps the printed detail at twelve lines, which on this campaign are twelve lines about four
*other* cases — so not one of the 31 appears in the report. That is this brief's own category, a
detector reporting a number it cannot support. Filed as **DEF-502**, with a ratcheted gate at
`planning/effect-class-vocabulary-gate.py` holding the roster at 31.
