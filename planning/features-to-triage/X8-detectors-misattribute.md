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
