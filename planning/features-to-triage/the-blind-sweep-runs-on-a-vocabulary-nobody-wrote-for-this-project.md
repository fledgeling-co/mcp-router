---
status: to-triage
found-by: `vacuity-check.py --gate` (test-campaign 0.14.1), 2026-08-29
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
