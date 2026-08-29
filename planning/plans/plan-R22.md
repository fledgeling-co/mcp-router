# plan-R22 — The daemon diagnostics bundle

**Spec** `planning/specs/spec-R22.md` · **Branch** `ai/n7` · **Lane** `router`

---

## The order the work was done in, and why that order

1. **Establish whether R25 had landed.** It is the sibling item — server configuration profile
   export with safe secret redaction — and building a second redactor beside an existing one is the
   worst outcome available here. Checked and it has not:
   `**To Do** — allocated 2026-08-27 by serial pre-triage; **proposed-by-ai**. Overlaps W1's secrets
   inventory.`, `planning/features-to-triage/LEDGER.md:149` at `08a24ed` — no spec, no plan, no
   branch. So the redactor is new, and it is written as
   a general component under `RouterCore/Diagnostics` rather than private to the bundle, so R25
   consumes it instead of writing a third.

2. **Settle the two forks out of family before writing anything.** The artifact shape and the
   redaction design are both technical and both evaluable with evidence, so they went to other model
   families rather than to the owner.

3. **Build the redactor, then the gatherer, then the routes.** In that order because the redactor is
   the deliverable and the routes are how it is reached.

4. **Write the cases, then arm them.** Every one watched red before any of it was believed.

5. **Then the socket lane**, because the unit suite cannot witness bytes leaving the process.

## The referral, and what came back

Three families were asked the same packet, from `/tmp`, with the candidate options listed and a
request for a better one:

| lane | outcome |
|---|---|
| `claude-fable-5 --effort high` | answered — in family, so it counts as a check rather than a second family |
| `agy --new-project --model gemini-3.7-flash-high` | answered on subject, 14 KB, both forks picked with an eight-vector attack list |
| `grok -m grok-4.6 --effort xhigh` | **lane failure — reported, not counted.** It returned 241 bytes of an agent's own preamble ("I'll load the voice skill and look at the actual router daemon…") and kept editing the output file afterwards; it answered neither fork. The harness behaved as an agent rather than as a one-shot reviewer. |
| `codex` | not probed — `ORCHESTRATOR.md` records the lane down and says not to spend a probe rediscovering it |

**Both lanes that answered picked A1 and B2 independently**, which is the pair this ships: one JSON
document on the wire, and structural withholding plus a value-scrub backstop.

**Four things came back that were taken:** percent-encoded and base64 needle variants; scrubbing
object keys as well as values; the URL userinfo and query sanitiser; and the twin-canary test
protocol, which is now the shape of every case here.

**Two were declined with the reason recorded:** the entropy filter on the needle floor
(§3.4 of the spec — over-redaction announces itself, under-redaction does not, and the asymmetry
decides it) and prefix matching for truncated tokens (§6).

**One was corrected.** Both lanes wanted JSON-escaped needle variants, reasoning about a search over
the serialised bytes. The scrub runs over the value tree *before* serialisation, so the escaping has
not happened and the whole class disappears rather than being enumerated. Recorded in
`SecretNeedles.variants`, at the code, rather than only here.

## Test strategy

The strategy is one sentence: **no absence is asserted alone.**

"The bundle does not contain the secret" is the easiest unfailable assertion in this repository. It
passes over an empty document, over a 404, over a gatherer that never read the config, and over a
redactor that was never called because layer 1 had already dropped the field. So each case pairs it
with a public canary that must be present, the key names that must be present, and — where layer 2
is the subject — a non-zero removal count.

| case | subject | what makes it non-vacuous |
|---|---|---|
| CASE-0270 | layer 1, over config | canary present, both key names present, `"value":"present"` |
| CASE-0271 | layer 2, over a log line | `<redacted:…>` present, `occurrencesRemoved` non-zero, canary survived |
| CASE-0272 | the needle floor | `dev-server on port 3000` present *and* intact |
| CASE-0273 | encoded forms | canary present; both forms planted before either absence is read |
| CASE-0274 | the ungated preview | the canary must be **absent** — a preview carrying no secret is satisfied by one carrying the whole scrubbed log |
| CASE-0275 | the token gate | the tokened 200 asserted beside the 401 and the 405, so those read as refusals rather than an absent route |

## What arming found that reading did not

**The redaction block was appended after the scrub**, so a credential written into an `env` key
name — or into a server's name — travelled out through the key path in `unscrubbable`. That is
precisely the leak vector one of the reviewers named, arriving at the last line of the function
written to close it, and reading the code did not catch it: the append looks obviously correct.
`R22-f` plants a secret as a value on one server and as an env KEY on another, and `ARM 8` reverts
the fix and watches it go red alone.

The socket lane's first draft carried **two assertions that could not fail**, and neither was
visible on the page:

- It derived the percent-encoded form with `urllib.parse.quote(s, safe="")`. `quote` never encodes
  an RFC 3986 unreserved character whatever `safe` is set to, so for a secret of alphanumerics and
  hyphens it returns the input unchanged — "its percent-encoded form is absent" was a second copy of
  "the literal is absent".
- Neither encoded form was ever written to disk, so both absences held over a router that did no
  encoding-aware scrubbing at all.

Found by arming the lane rather than by reading it: removing `SecretNeedles.variants` left the lane
green. The fix computes the forms the way the product does and **plants** both, and the lane now
refuses to run at all if an encoded form comes out equal to the literal. Re-armed, it goes 21 ok /
2 failed on exactly those two assertions.

The arming pass also grew a second reading for the same reason. It first reported only how many
tests went red, which cannot tell an arm that proved its own claim from one that reddened something
else entirely; it now names the cases, and that is what turned the two-layer separation from an
assertion in a comment into a measurement.

Its restore check was wrong too, and reported red on a clean run: it asked `git status`, and three
of the five files it mutates are new on this branch, so git calls them modified whatever the pass
did. It now compares against copies taken at the top.

## Gates

| gate | result |
|---|---|
| `swift test --filter ControlDiagnosticsTests` | 12 tests, 1 suite, passed |
| `bash planning/test-campaign/bin/arm-r22-diagnostics.sh` | 10 of 10 held — 8 arms red with the cases named, baseline green, restore byte-identical |
| `bash scripts/acceptance/r22-diagnostics.sh` | 23 ok, 0 failed |
| `python3 planning/registry-drop-gate.py` | exit 0, control held, no id dropped, 270 ids |
| `python3 planning/test-campaign/bin/effect-class-census.py` | exit 0, 30 requirements, 0 findings |
| `make lint`, `make test` | in the completion note — both run whole before reporting |

## Deferred, registered rather than dropped

- **R22-C1** — the menu item, the Settings action and the save panel. Needs a rendered surface, so
  it carries `design-review` and `be-my-witness`, which this item renders nothing for.
- **R22-C2** — the zip archive. The router answers a document; the app writes the file. Both
  out-of-family lanes picked that split for the same reason (§2 of the spec).
- **DEF-070** — `GET /servers` publishes every stdio upstream's argv to an unauthenticated local
  caller. Found here, filed here, and not fixed here: that route is reference-diffed and the fix is
  a parity decision.
