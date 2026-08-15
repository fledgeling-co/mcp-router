# P3 — acceptance evidence

Appended, never rewritten. Branch `ai/p3`, worktree `.worktrees/P3`.
Rows owned: `control-usage-stream`, `control-registry-search`, `fixture-registry-search`.

This item touches no rendered surface. `UI_VERIFICATION.md`'s rules about the developer loop and
about only testing a screen you changed are honoured by there being **no screen in the diff**: the
Mac and iOS targets are untouched, `BoardRegistry` is untouched, and no app was launched. The
surfaces exercised here are two loopback HTTP routes and the parity harness.

---

## 1. What was measured before anything was changed

Taken on `main @ 7babd97`, from `.worktrees/P3`, and each one decided a step.

| # | Measurement | Result |
|---|---|---|
| 1 | `parity-stream.sh` run by hand | exit 0 · 1 result row · 5 frames diffed byte for byte |
| 2 | `parity-gate.sh` `LANES` | `control fixture divergence pool suite mcp cli install state log` — **`stream` absent**, so the lane above had never been dispatched by the gate |
| 3 | `GET /registry/search?q=github&limit=2`, both binaries, scratch homes | Swift **HTTP 502** `{"error":"registry search is unavailable: no HTTP client is configured"}` · reference **HTTP 200** with results |
| 4 | `grep -rn "RegistryDeps(" app/Sources` | **no match.** Every `HTTPFetching` conformance lives in a test target; the daemon's `ControlDeps` never set `registry:` |
| 5 | SSE response heads, both routers, `od -c` | byte-identical: `HTTP/1.1 200 OK`, `content-type`, `cache-control`, `connection`, `Date`, `Transfer-Encoding: chunked`, same order — only `Date` differs |
| 6 | Late subscriber, both routers, after 2 records | exactly **1** `data:` frame each — no backlog on either side |
| 7 | node `fetch` error messages | refused → `"fetch failed"` · DNS → `"fetch failed"` · abort → `"This operation was aborted"` |
| 8 | BEFORE parity gate, from the worktree | **77 of 83 proven, 6 blocked, 0 DIVERGED, exit 1** |

**Measurement 3 and 4 contradict the brief**, which said all three rows were oracle problems and
not implementation gaps. They are recorded here rather than smoothed over: `GET /registry/search`
was unanswerable in the shipping Swift binary, and the row being blocked for an *oracle* reason is
what kept anyone from looking.

---

## 2. Mutations — every one against a rebuilt binary

`swift build` ran before each red run. Without it a mutation reports against the previous binary
and reads BLOCKED rather than red.

**The plan listed eight mutations; seven were run.** `M1` and `M2` were "remove `stream` from
`LANES`" and "remove `registry` from `LANES`" — the same mechanism, one line apart, and each needs
a **full gate run** to observe. They were combined into one mutation that removes both and asserts
both rows fall back to blocked. A second ten-minute gate run would have proved the identical
sentence about the identical line. Stated here rather than left as a count that does not match the
plan.

| # | Mutation | Lane | Result |
|---|---|---|---|
| M1 | `stream` and `registry` removed from `parity-gate.sh`'s `LANES` | the gate | **RED** — see §2.1 |
| M3 | `ControlStream.openingFrame` `": connected"` → `": ready"` | `parity-stream.sh` | **RED** — *"a router never delivered the SSE opening comment, so no frames could be compared"* |
| M4 | `("cache-control", "no-store")` deleted from `usageStream()`'s headers | `parity-stream.sh` | **RED on the head verdict only** — *"the swift head is missing ^cache-control: no-store$"*, while the frame, late-subscriber and still-open verdicts all stayed green |
| M5 | the daemon's stream yields `usage.recent(limit: 3)` on subscribe | `parity-stream.sh` | **RED on the late verdict** — *"the swift router replayed 3 record(s) to a subscriber that joined afterwards"* |
| M6 | the `registry:` wiring removed from `RouterServiceDispatch` | `parity-registry.sh` | **RED, 7 of 8 scenarios** — *"status differs: reference 200, Swift 502"* |
| M7 | `coerceLimit`'s `min(truthy, 60)` → `min(truthy, 30)` | `parity-registry.sh` | **RED on `?limit=99` only** — see §2.2 |
| M8 | `RegistryHTTPClient` maps a transport error to `"\(error)"` | `parity-registry.sh` | **RED on the unreachable scenario** — the body no longer carries `official registry unreachable: fetch failed` |

### 2.1 M1 — the wiring is the whole mechanism

With both lanes removed from `LANES`, the gate reports `control-usage-stream` and
`control-registry-search` as **blocked, `(no lane reported)`** — *"the manifest claims this is
proven and no lane spoke for it"* — and coverage falls back. The lane scripts are untouched and
still pass when run by hand. That is exactly the state `stream` was in from R2-R until this item.

### 2.2 M7 — the mutation only reddens because the fixture echoes the query

`?limit=99` is capped at 60 by the reference and at 30 by the mutant. The corpus is 7 merged rows,
so `slice(0, 30)` and `slice(0, 60)` return **the same seven rows** — the results array is
identical and a body diff alone would have passed the mutant.

It reddens because `registry-fixture-server.mjs` echoes the query string it received into one
entry's `description`, so the reference's body carries `official received: search=github&limit=60`
and the mutant's carries `limit=30`. **The echo is what makes the limit rule comparable at all**,
and this mutation is the evidence for that rather than a design note.

### 2.3 Two guards that could not have failed, found and fixed

Both were in code this item wrote, and both were found by running the thing rather than reading it.

1. **`grep -vE '^(: connected|: ping|data: .*|)$'`** — the unexpected-line-kind check in
   `parity-stream.sh`. The trailing `|)` is an empty sub-expression, which BSD grep **refuses**:
   it printed `grep: empty (sub)expression` to stderr, matched nothing, and left the check
   reporting clean for every possible input. Fixed to `'^(: connected|: ping|data: .*)$|^$'` and
   proved against a synthetic stream carrying an `event: usage` line, which the fixed form catches
   and the broken form does not.
2. **`lsof -nP -p "$pid" -iTCP -sTCP:ESTABLISHED`** — the egress check in `parity-registry.sh`.
   `lsof` ORs its selection options, so without `-a` this listed every established TCP connection
   on the machine rather than the router's. It reported the **same three off-loopback connections
   for both routers**, which is what an OR looks like when an AND was meant, and it failed the run.
   Fixed with `-a`.

---

## 3. What the two lanes now compare

### `control-usage-stream` — 4 verdicts

| Verdict | Claim |
|---|---|
| head | status line and every response header, byte for byte, `Date` the only substitution, plus the three handler headers asserted present by name |
| frames | every line of the frame region including the blank lines that terminate each SSE frame, with any unrecognised line kind a named failure even when both sides produce it |
| late | a subscriber that joins after three records gets **zero** backlog (asserted absolutely on each side, after a settle, before any diff), then exactly the one record driven afterwards, byte for byte |
| still-open | both original readers alive **and** carrying the record driven after the heartbeat |

### `control-registry-search` — 8 scenarios, plus a shape guard and an egress guard

Both routers against one pinned registry on loopback, both homes seeded with an in-TTL
`github-cache.json`. Bodies compared as **raw bytes with no normalisation at all**, status
compared alongside.

```
  shape guard: 7 rows carrying every path this lane claims to compare
  ok   ?q=github&limit=3 — envelope, merge, ranking, seeded stars — HTTP 200, 1242 bytes
  ok   ?limit=0 — zero is falsy and becomes 30 — HTTP 200, 2403 bytes
  ok   ?limit=abc — NaN is falsy and becomes 30 — HTTP 200, 2403 bytes
  ok   ?limit=-1 — a negative reaches slice — HTTP 200, 2130 bytes
  ok   ?limit=99 — capped at 60 — HTTP 200, 2403 bytes
  ok   no q — an empty query sets no search parameter — HTTP 200, 2380 bytes
  ok   smithery answering 503 — the warning and the partial result — HTTP 200, 1806 bytes
  ok   the registry unreachable — both report node's own "fetch failed" — HTTP 200, 159 bytes
  neither router holds a connection off loopback, and the seeded star count survived into
  the compared body — the GitHub cache was read rather than the network
compared 8 scenarios: 8 ok, 0 failed
```

The shape guard refuses the whole run unless the reference's own body carries a deduped
`source:"both"` row, a Smithery-only row, an official-only row, npx and uvx stdio installs, sse and
http remote installs, a `requires[]`, `installed` in both states, the seeded stars, and a non-empty
`sources` census. Two parsers that both returned nothing diff clean, and that is the failure this
lane is most exposed to.

---

## 4. `fixture-registry-search` — accepted as uncomparable

Not re-recorded, and the reasoning is in `spec-P3.md` §2.3 and in the manifest note itself. In
short: pinning the upstream makes the row *comparable* but changes its claim to one that
`control-registry-search` already proves against the live reference and the live Swift router every
gate run, at the cost of destroying the only production-shaped registry sample the decode suite has.

`parity-fixture.sh`, `capture-control-fixtures.sh` and `registry-search.json` are **unmodified**.

**Consequence, reported not absorbed: 83 of 83 is unreachable while this row is enumerated and
unprovable.** Registered as `D-p3-f` for R4-C and the owner.

---

## 5. Gates

Branch `ai/p3`, 0 commits behind `main` (`7babd97`).

| Gate | Result |
|---|---|
| `make lint` | **0 violations over 448 files**, exit 0. All four linters ran — `no-raw-design-values: clean` over 107 files, `no-wire-codable: clean` |
| `make test` | **1414 tests / 173 suites**, exit 0 |
| `make build-mac` | `** BUILD SUCCEEDED **`, exit 0 |
| `scripts/acceptance/parity-manifest-check.sh` | **exit 0** — *"83 rows, consistent with control.ts, index.ts, router.ts and the fixture directory; every cited test, script and row id resolves"* |
| `make parity-selftest` | **exit 0** — normalise selftest 14 behaved, 0 did not |
| `scripts/acceptance/parity-gate.sh` | **79 of 83 proven, 4 blocked, 0 DIVERGED. Exit 1 by design** |

### Parity, before and after

| | rows proven | blocked | DIVERGED | exit |
|---|---|---|---|---|
| BEFORE, `main @ 7babd97` | **77 of 83** | 6 | 0 | 1 |
| AFTER, `ai/p3` | **79 of 83** | 4 | 0 | 1 |

By group, after: `control` **15 of 16** (was 13), `fixture` 23 of 24, `divergence` 15 of 15
(4 by suite only), `pool` 6 of 6, `mcp` 5 of 5, `cli` 9 of 10, `install` 4 of 5, `state` 1 of 1,
`log` 1 of 1. The new lanes reported `stream: 4 result rows` and `registry: 8 result rows`.

The four still blocked: `fixture-registry-search` (`accepted-uncomparable`, §4),
`control-auth-post-http` (`D-p1-a`), `cli-auth` (`D-p1-d`), `install-rollback` (`R4-C`). **None of
them is P3's to close**, and the gate's closing line is unchanged and still correct: *"The cutover
requires 83 of 83. It has 79."*

**The census did not move.** 83 rows before, 83 after; the `# rows: 83` pin at `surface.tsv:3` is
untouched; the diff over that file is **3 lines changed, 0 added, 0 removed**.

### A gate behaving correctly, recorded because it looked like a failure

An earlier AFTER run returned **exit 2, 78 of 83**, with `stream` reporting *"environment:
something is already listening on :8988"*. That was **self-inflicted**: a mutation lane run of mine
held the port at the same moment. The gate did the right thing — it refused to score a lane it
could not run, reported `control-usage-stream` as `(no lane reported)` rather than green, and
exited 2 to distinguish an incomplete run from a passing one. The clean re-run with nothing else
holding a port is the 79 above. Recorded rather than quietly discarded, because "re-ran it and it
went green" is the shape of the mistake this fleet has already made once.


---

## 6. The three out-of-family reviews, and what they changed

All three ran on `grok --model grok-4.6`. **The lane was smoke-tested for the failure mode the brief
names** — grok exits 0 when session init fails — by asserting on CONTENT, not exit code: the spec
gate returned 14,845 bytes, the plan gate 4,387, the Phase D critic 10,953, each citing files and
line numbers that exist. A review that had never run cannot name `parity-stream.sh:210-221`.

One process note, recorded because it nearly cost a gate: **the first plan review was killed at ~45
minutes while its output file held 486 bytes, on the assumption it had stalled.** That was probably
wrong. grok buffers and flushes at completion — the spec gate sat at 486 bytes for ~25 minutes and
then produced 14,845 in one go. The relaunched plan gate is the one reported here.

**Verdicts: spec gate AMEND, plan gate AMEND, Phase D critic AMEND.** Eighteen findings between the
two later gates. Eleven changed the delivery; the rest were dispositioned with a reason.

### 6.1 The finding that mattered most — a green row with its interesting half unrun

**Critic 1 (HIGH), confirmed against `parity-gate.sh` and fixed.** `parity-registry.sh` appended
each scenario's verdict to `$PARITY_RESULTS` as it went. The gate's reconciliation scores a row
`proven` on any `ok` with no `fail`. So a lane that recorded six happy-path `ok`s and then died —
a fixture restart that failed, a stolen port, a kill — left `control-registry-search` **proven**,
with the 503 and unreachable paths never run. The gate then printed its env-failure banner claiming
"those rows were counted blocked rather than proven", which by that point was false.

That is exactly the failure this item exists to refuse, and it was inside the lane written to
refuse it. Verdicts are now buffered and flushed once, by `finish`, which also asserts that all 12
scenarios reached a verdict; every `exit 2` path flushes nothing. **Proved by mutation M10** below.

### 6.2 Corrections to §2 of this file — claims that were wrong

This file is appended, never rewritten, so the errors stay above and the corrections are here.

| Claim in §2 | Correction |
|---|---|
| M3 (`": connected"` → `": ready"`) proves "the frame region is compared, not counted" | **It does not.** It dies at the opening-`await` arrival gate (`parity-stream.sh:210-221`), which pre-dates P3; `frames_of` is never reached. Re-aimed — see M3a/M3b. |
| M6 is "**RED, 7 of 8** scenarios" | **Wrong number, and my miscount.** Measured directly with `registry: nil` and curl: reference 200 / Swift 502 on **every** scenario query — 8 of 8 under the old lane. The critic was right that a record naming no passing scenario could not be checked. |
| still-open proves the original readers were "carrying the record" | It asserted `count >= 4`. Two routers both staying open and both emitting *any* fourth `data:` line passed together. Now diffed byte for byte. |
| §5's AFTER gate | One cwd was reported where the plan required two. Both are now measured — §7. |

### 6.3 Every finding, and its disposition

**Taken, and changed the delivery (11):**

| # | Finding | What changed |
|---|---|---|
| C1 | partial lane scores the row proven | buffered results + `finish` + scenario-count assertion |
| C2 / P1 | M3 dies at the arrival gate | re-aimed to M3a (blank terminator) and M3b (`event:` line) |
| C3 | M5 does not isolate the late verdict | the 4th record is now driven **unconditionally**, so still-open is independent |
| C4 | M6's "7 of 8" is unfalsifiable | re-measured; the number was wrong and is corrected |
| C5 / P5 | the manifest's "risk is now carried" sentence is false | struck; the owner-less `https://github.com/` row added to the fixture corpus and shape-guarded |
| C6 | still-open counts frames rather than comparing them | the post-heartbeat record is diffed byte for byte |
| C8 | only smithery-down was compared | official-down added; the fixture could already produce it |
| C9 | `URLSession.shared` carries `URLCache.shared`; empty base uncompared | ephemeral session; empty-base scenario added; the `.cancelled` gap written down |
| C11 | late frames skip the line-kind check | the same `grep -vE` now runs on the late stream |
| P2 | ranking can read green without being compared | ranked order asserted **per router** against an expected sequence the merge order does not produce |
| P3 | `limit=-1` never asserts a shorter result set | asserted per router as an absolute, not as an agreement |

**Taken as a note rather than a code change (2):**

- **C7 / P3b — the 60 cap is not load-bearing for `results[]`.** True: the corpus is 8 rows, so
  `slice(0,30)` and `slice(0,60)` are identical and only the fixture's echo can see the cap.
  Growing the catalogue past 60 rows to make it bite would add ~55 synthetic entries to every
  compared body to test one `min`. The manifest note now says what is and is not compared, and
  **M7b** was added so the limit *default* is proved against a changed result set.
- **P4 — M1/M2 cannot redden the gate's exit code.** Correct, and it was already scored that way:
  the red condition is `proven` falling by one and `blocked.txt` naming the row with
  "(no lane reported)". Stated explicitly rather than left implied.

**Declined (2):**

- **P1's alternative for finding 5** — grok's spec gate and its plan gate disagree with each other
  here. Both say do *not* flip `fixture-registry-search`; the delivery follows that. No change.
- **C9's suggestion to map `.cancelled` to the abort wording.** Declined: nothing in the lane drives
  an abort, so the mapping would be a guess dressed as parity. The gap is written into
  `RegistryHTTPClient` instead, where the next person meets it.

### 6.4 The mutations, re-run against the amended lanes

Every one against a rebuilt binary. `swift build` before each.

| # | Mutation | Result |
|---|---|---|
| M3a | the blank-line terminator dropped from `frame(for:)` | **RED at the frame region** — *"normalisation left too few frames: ts=9 swift=6"*. The terminators really are inside the diff. |
| M3b | an `event: usage` line before each data frame | **RED by name** — *"the swift stream carried a line kind this lane does not recognise: event: usage"* |
| M5 | the daemon replays `usage.recent(limit: 3)` on subscribe | **RED on the late verdict ONLY** — *"the swift router replayed 3 record(s)"* — and **still-open stayed GREEN**. That isolation is the C3 fix working; before it, still-open went red as a side effect. |
| M9 *(new)* | the daemon calls `continuation.finish()` after its heartbeat | **RED on still-open ONLY** — *"had already ended before it was torn down"*, *"stopped delivering: 3 of 4"* — head, frames and late all green. Nothing covered this before. |
| M6 | the `registry:` wiring removed | **RED at the shape guard, before any scenario runs**, because the guard now runs on both routers. Stronger than the old 8-of-8. |
| M7a | `min(truthy, 60)` → `30` | **RED on `?limit=99` only**, via the echo — which is the evidence for C7 rather than a rebuttal of it |
| M7b *(new)* | the limit DEFAULT `30` → `5` | **RED on `?limit=0` and `?limit=abc`** — the default is now proved against a changed result set, not only a forwarded string |
| M8 | a transport error reports URLSession's own description | **RED on the unreachable scenario only** |
| M10 *(new)* | the lane dies (`exit 2`) after the happy path | **The lane reached seven `ok` verdicts and wrote NOTHING to `$PARITY_RESULTS`.** The gate sees "(no lane reported)" and counts the row blocked. Under the old code those seven made it proven. |
