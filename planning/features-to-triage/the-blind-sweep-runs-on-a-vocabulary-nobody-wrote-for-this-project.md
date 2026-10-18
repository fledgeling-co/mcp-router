---
status: to-triage
found-by: `vacuity-check.py --gate` (test-campaign 0.14.1), 2026-08-29
reckon-sources: [DEF-048, DEF-055]
---
# The blind-mutation sweep runs on borrowed vocabulary, so its three findings settle nothing

- origin: test-campaign 0.14.1 run against `planning/test-campaign`, full scope · 2026-08-29
- audience: whoever wants to know that a test which changes something also looks at it afterwards
- platforms: n/a
- proposed-by-ai: true

## What and why

`campaign.json` declares no `blindVocabulary`, so the blind sweep runs on defaults only — 9 mutators
and 7 readers — over a 1257-file Swift corpus. Its recall is therefore unmeasured: nobody knows what
fraction of the genuinely blind tests in this suite those seven reader verbs are capable of seeing.

On that vocabulary the sweep reports three mutating tests with no read after: `restartRechecksTheCamera`
in PhoneStorageFailureTests, and `restartIsIssuedBeforeTheStagingWrite` and `restartIsOwedBeforeTheWriteLands`
in WatchRestartTests. All three have the same last mutator, `restart`, with no read after it.

The two halves are one problem, which is why they are one brief. Three findings that share a verb are
one question, and it cannot be answered while the vocabulary answering it was written for some other
codebase: the three may be real blind tests, or they may read back through an idiom no default reader
verb names. This project has already measured that shape once — a sampled stratum of this sweep's
findings turned out to observe through idioms the vocabulary did not list — and recorded that widening
the reader list to make the number fall suppresses true findings along with false ones.

## Acceptance sketch

- `campaign.json` declares the mutating and reading verbs this Swift suite actually uses, rather than
  inheriting defaults.
- The sweep's recall on this corpus is measured and stated as a number: tests planted to mutate
  without reading are counted, and the count of those it catches is published rather than assumed.
- Each of the three named tests ends up in one of two states — it reads back after `restart`, or it is
  recorded as reading through an idiom the vocabulary now names.
- Any verb added to the reader list is shown not to have suppressed a planted true finding, so the
  count falls for a reason.
- Removing the read from a test that has one makes the sweep report it.

## Assumptions made writing this

- Assuming the vocabulary is declared rather than the sweep switched off, since an unmeasured sweep
  still catches something and a disabled one catches nothing.
- Assuming the three findings are adjudicated after the vocabulary is right rather than before,
  because a verdict reached on the default list would have to be revisited.
- Assuming recall is measured by planting blind tests rather than by reading the corpus by hand, since
  a hand count over 1257 files is the thing the sweep exists to avoid.


---

## WE3 ADJUDICATION, 2026-09-03 — **(B), and it landed on 2026-08-29. The premise of this brief is no longer true of the tree.**

This row names `vacuity-check.py`, which is vendored. It is not a defect in that script: the
input it complains about is `planning/test-campaign/campaign.json`, which is this repository's
file, and the fix is there.

**"`campaign.json` declares no `blindVocabulary`" is false today.** It declares one — 19 mutators
and 34 readers, with `"only": true` — written by K4 against the corpus at `testRoot`, measured at
`83e5380`, and dated the same day this brief was filed. The brief and the fix crossed.

The acceptance sketch is answered clause by clause by the `note` field that ships with the
vocabulary, which is worth reading in full because it is the measurement rather than a claim
about one:

* *declared rather than inherited* — yes, and `only: true` is argued rather than defaulted: the
  nine shipped defaults are snake_case for a Rust/RPC shape against a camelCase Swift corpus, and
  unioning them in contributes nothing except `restart`, the verb behind all three unadjudicable
  findings.
* *recall stated as a number* — four figures over the same 2282 test bodies: defaults
  `mutating=3 blind=3`; fitted mutators with no readers `blind=481`; with the ten tightest readers
  `blind=210`; with the full reader list `blind=111`. The reader list suppresses 370 of 481, and
  the 99 between 210 and 111 is stated as what the looser half costs.
* *a verb added is shown not to have suppressed a true finding* — the note records what was
  deliberately **left out** and why: `expect` (5781 sites) and `require` (383) would collapse the
  count to near zero without the pass learning anything, and `contains`/`filter`/`map` are
  transforms over an already-read value. That is the "widening the reader list to make the number
  fall" trap this brief names, refused on the record.
* *removing a read makes the sweep report it* — `bin/blind-vocabulary-arm.py` arms the vocabulary
  two ways on every run.

**What is genuinely still open, and it is not this brief's.** The note says so itself: the 111 is
a worklist and the campaign claims no blind number, because DEF-055's four structural causes are
not withdrawn — the pass still examines every `func` rather than every `@Test`, its helper
exclusion is still file-scoped, and a mutator in a `defer` block still reads as source-early.
Those four are **(A)**, in `vacuity-check.py`, and they are X8's delivery items 1–4. DEF-055 is
another runner's member in this wave and was not touched here.

So: the vocabulary half is (B) and done; the precision half is (A) and belongs to DEF-055.
Status word not changed — `shipped-brief-gate` R6 would refuse a terminal word while DEF-055 is
open, and it would be right to.
