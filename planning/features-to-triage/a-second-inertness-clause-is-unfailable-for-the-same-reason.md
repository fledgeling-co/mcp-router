---
status: to-triage
found-by: N8, 2026-08-29
registry-target: none
no-target-reason: nothing in the registry names `imageAttributeStripped` — CASE-0292 covers `htmlIsInert`, a different claim, and no defect was raised because the clause is unfailable rather than wrong
---

# A second clause in the same suite is unfailable for the same structural reason

- origin: N8 (`a-security-guard-that-cannot-fail-now-guards-a-live-entry-point.md`) · 2026-08-29
- audience: whoever reads `MarkdownSecurityTests` and believes the image rule is checked
- platforms: mac
- proposed-by-ai: true

## What and why

N8 rebuilt `MarkdownSecurityTests.htmlIsInert` so it can go red, and armed it as A10 of
`scripts/m19-red-green.py`. Doing so surfaced that the same defect sits one test away.

`MarkdownSecurityTests.imageAttributeStripped` is one clause —
`inline.attributed.runs.allSatisfy { $0.imageURL == nil }` — over one input,
`![pixel](https://tracker.example/p.gif)`. `MarkdownInline.sanitized` rebuilds the string run by
run and carries `inlinePresentationIntent` and an `https` `link` and nothing else, so **no input
can put an `imageURL` on a run**. The clause is true by construction of the allowlist rather than
by anything the test supplies, and no arm in `scripts/m19-red-green.py` names it.

This is the same shape N8 fixed, and the same shape M19's second verdict blocked on: an absence
assertion whose subject the code under test cannot produce. It is not the same test, it carries a
different claim, and N8 declined to widen into it rather than leaving it unrecorded.

Nothing here is known to be broken. `imageURL` is genuinely dropped today, and images are a block
the resolver decides about rather than an inline attribute — `PackageImageResolver` carries that
rule and is armed. What is missing is the ability to notice if the allowlist stopped dropping it.

## Acceptance sketch

- The image clause fails when `sanitized` starts carrying an `imageURL`, demonstrated by making it
  fail rather than argued from the code.
- A red-green arm names the test, so a change to the allowlist's rebuild is caught rather than
  assumed.
- If the clause cannot be made failable at the inline layer — because an `imageURL` is structurally
  a block-level concern here — the test says what it actually measures instead of naming a property
  it cannot check, and the real guard is named where it lives.
- The suite is swept for any remaining clause whose subject the code under test cannot produce,
  rather than these two being fixed one verdict at a time.

## Assumptions made writing this

- Assuming the remedy is again the assertion rather than new sanitisation, on N8's measurement that
  the platform and the allowlist both already do the dropping.
- Assuming the last acceptance bullet — a sweep of the whole suite — is worth pricing here, because
  two instances found by two separate reviews is the argument for looking rather than waiting.
