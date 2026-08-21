# R7 gap-fix — three rows where the tool answers confidently and wrongly

**Parent:** R7, the harness reconciliation engine (`R7-harness-reconciliation.md`).
**Branch:** `ai/r7`, worktree `.worktrees/R7`, at `b3d2410`. Resume in place.
**Verdict this closes:** Verified 2026-08-21 at `metamorphic`, **Needs More Work**.

## What survived, so it is not re-litigated

The verifier reproduced every gate the bundle claimed, exactly: swiftlint `Found 0 violations,
0 serious in 489 files`, swiftformat `0/496`, `swift test` twice at `1551 tests in 193 suites`,
`make parity` at 358/358 floor, `parity-lock-selftest` 12 held, `parity-normalise-selftest` 14
behaved, `r7-harness-reconciliation.sh` `3 → 0 → armed-0 · pass`, and the two recorded blocks
(`parity-manifest-selftest` exit 2 without the SDK, `make lint` exit 2 at the `tools` guard in a
fresh worktree) both blocked rather than passed. The planted mutation reproduced at 7 failing
checks. §1's real-machine measurement reproduced from the shipped binary, so all three
"contradicts the brief" rows stand: Claude Code `wired-http` +1 duplicate, Gemini `stdio-shim`
+12 over 17 entries, grok `wired-http` +1, Codex `not-wired`, Cursor 0.

**One process claim is refuted and it matters more than any single finding.** The bundle records
that the out-of-family diff review was attempted on three families and delivered by none. Run
again, **all three delivered** — codex 14,036 B, grok 10,376 B, agy 11,511 B — and all three
independently named the same top defect, which is F1 below. The two lane failures were operator
error, not lanes being down: codex failed instantly with `Not inside a trusted directory` because
it was launched from `/tmp` and needed `-C <worktree>`, and grok emits ~230 B of narration early,
which is the shape the runner mistook for its entire output. An absent `-o` file is a lane
failure; a small early write is not.

## F1 — Gemini is wired via `httpUrl` and the tool reports `not-wired`, then offers to wire it

`HarnessRoute.detect` reads only `entry.raw.member("url")`, and `ServerParser` and
`SelfReference.isSelfReference` key on `url` alone. Gemini CLI's config key is `httpUrl` —
confirmed independently by the verifier from the shipped binary, `strings -a ~/.local/bin/agy`
returning `json:"httpUrl"`, which is the spec's own §1.2 evidence. So `.wiredViaHTTP` is
**unreachable for Gemini**, and A1's primary axis has a hole in the one harness this brief is
entirely about.

Measured output:

```
Gemini CLI
  not wired — 1 of its 2 servers are ones the router already fronts
  speaks streamable HTTP — measured on agy 1.1.17 … server config struct carries json:"httpUrl"
  Point this harness at http://127.0.0.1:<port>/mcp.

Gemini CLI — …/.gemini/settings.json
  + add     mcp-router   (this router's endpoint)
```

The block names `httpUrl` as its evidence and three lines later fails to read an `httpUrl` entry.

Two things make this the blocking one rather than a coverage gap. It is **the same failure class
the bundle claims to have closed** for grok's TOML — *"a confident wrong plan offering to add a
router entry to a harness already wired via HTTP"* — reproduced unfixed in the harness the item
exists for. And it is **self-triggering**: `not-wired` plus that remedy tells the user to create
the state the tool then cannot read.

**Fix:** read `httpUrl` alongside `url` in `HarnessRoute.detect` and `ServerParser`, with a test.

## F2 — `--json` cannot express "could not be read"

`HarnessesVerb.json` emits `harness, path, exists, state, route, entries, duplicateCount,
duplicates, unparsed, httpCapability` and no `unreadable`. An unreadable config serialises
identically to a clean not-wired one:

```json
{"exists": true, "state": "not-wired", "route": "none", "entries": 0, "duplicateCount": 0, "unparsed": []}
```

The human output says `could not be read:` and correctly suppresses the plan; the machine output
does not. This is the distinction the bundle itself says cost a wrong answer against
`~/.grok/config.toml` — carried in the type and dropped at the wire. It blocks because the
acceptance lane asserts on JSON only, so the lane cannot see the difference either, and R7-C1's
Harnesses board will consume the same JSON.

**Fix:** carry `unreadable` (and its reason) into the JSON, and assert it in the lane.

## F3 — the write-boundary gate does not enforce the guarantee ORCHESTRATOR.md states

`ReconciliationPlan` genuinely has no applier today — `grep` over `app/Sources` finds it in its
own file and one render call in `HarnessesVerb`, with no `write(`, `createFile`, `removeItem` or
`FileHandle` anywhere under `RouterCore/Discovery` or the verb. The refusal is real. The gate that
is supposed to *keep* it real is not.

Both of `no-harness-config-writes.sh`'s rules are line-scoped (`grep -rnE … | grep -E …`), so they
fire only when a harness path literal or the token `ReconciliationPlan` sits on the same physical
line as a write call. Planted:

| plant | result |
|---|---|
| path literal + write on one line | caught, exit 1 |
| `ReconciliationPlan(...)…write(toFile:)` on one line | caught, exit 1 |
| **a realistic applier** — `ClientConfigs.path(for:)` on one line, `try rewritten.write(toFile: target, …)` on a later line | **exit 0, `none writes one`** |

The script's own header claims it refuses any use of `ReconciliationPlan` alongside a write
*anywhere under `app/Sources`*. It does not. `FileHandle(forWritingTo:)` is also missing from
`WRITING`, which lists only `forWritingAtPath`.

This is the guarantee that protects the user's machine, and a gate that passes a realistic applier
is worse than no gate, because ORCHESTRATOR.md cites it as the reason the refusal holds.

**Fix:** make both rules file-scoped (`grep -rl` for the pair), and add
`FileHandle(forWritingTo:`, `OutputStream(toFileAtPath:` and `replaceItem(at:` to `WRITING`.

## Acceptance

Each fix proved by a mutation that goes red and returns on restore.

1. A Gemini `settings.json` carrying an `httpUrl` pointing at this router reports `wired-http`,
   emits no `+ add` line, and its duplicates are compared. Reverting `detect` to `url`-only turns
   the suite red.
2. An unreadable config's JSON carries `unreadable` with its reason, and the acceptance lane
   asserts on it. Dropping the field from the encoder turns the lane red.
3. **Plant 2 above now exits 1.** All three plants are kept in the selftest so the gate's scope is
   itself armed, and reverting either rule to line-scoped turns the selftest red.
4. Everything in *What survived* still reproduces, with exit codes quoted. `make test` run twice —
   `PoolReapingTests.swift:61` is non-deterministically red under load (registered as G3), and it
   did not flake in either of the verifier's runs, so a red here is worth reporting rather than
   re-running away.

## Scope

Deliver these three and their acceptance. The eleven follow-ups are registered as `D-r7-a` …
`D-r7-k` in `ORCHESTRATOR.md`'s deferred register and stay deferred — including the two silent
mutations (`HTTPCapability`'s table is unasserted, so a fabricated `.measured` passes every gate)
and the acceptance lane's blindness to the `.name` duplicate basis. Both are real; the unit suite
guards the second, and neither is what this item is being sent back for.

**Merging conflicts in two files, not one.** `ORCHESTRATOR.md` as expected, and also
`planning/features-to-triage/LEDGER.md`. Both take the union: main's R6 row and its renumbered
`R13`/`R11`/`R12` register, the branch's R7 row and its `R7-C1`…`C4` children. The
three-colliding-ids finding in the bundle is **already fixed on main** and is not to be re-filed.

Record anything else found rather than fixing it.
