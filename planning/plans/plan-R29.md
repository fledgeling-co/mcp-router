# plan-R29 — push a reload to live sessions

**Spec:** `planning/specs/spec-R29.md` · **Tier:** Standard · **Branch:** `ai/r29`

## Slices

| # | File | What |
|---|---|---|
| 1 | `src/livereload.ts` (new) | The registry of open standalone `GET /mcp` SSE streams, and `announceToolsChanged()`. Pure of HTTP: it takes anything with a `send()`. |
| 2 | `src/router.ts` | Register a `GET /mcp` transport with the registry; unregister on close. Expose `notifyToolsChanged` on the returned handle. |
| 3 | `src/sessions.ts` (new) | Read `~/.claude/sessions/*.json`, classify reachability against the live process table, and push the socket ask. Never throws; per-session outcome. |
| 4 | `src/control.ts` | Fire both on the mutations that change the served tool list: `POST /servers`, `DELETE /servers/<n>`, `POST /servers/<n>/reindex`, `PATCH` when `disabled` moves. New `GET /sessions` and `POST /sessions/notify`. |
| 5 | `src/index.ts` | `mcpr sessions [--push] [--dry-run]`. |
| 6 | `README.md` | One section stating which mechanism reaches what, and when. |
| 7 | `scripts/e2e-session-push.mjs` | The fixture proof for slice 3. |
| 8 | `scripts/e2e-live-reload.mjs` | The fixture proof for slices 1–2. |

## Test seams

The router has no TypeScript unit harness, so both proofs are self-contained `.mjs` scripts in
the `scripts/e2e*.mjs` family, each with its own `HOME` and its own fixture, run from `make`.

**Slice 3 is proved against a fixture socket this item creates and owns.** A temporary `HOME`
holding a synthetic `sessions/<pid>.json` and key file, and a unix socket bound by the test
itself, which records the exact bytes it receives. The push is never aimed at a real session:
`scripts/e2e-session-push.mjs` takes a `--home` and reads nothing outside it.

Each script must be able to go red. Both carry a control that plants a fault and requires the
check to report it, so a script that measured nothing exits non-zero rather than clean.

### What each proof must establish

`e2e-live-reload.mjs`
1. A `GET /mcp` opens a stream and the registry counts it.
2. `announceToolsChanged()` writes a well-formed `notifications/tools/list_changed` to it.
3. A closed stream is dropped from the registry and is not counted as a failure.
4. Control: with the registry emptied, the announce reports **0 delivered** and the script fails
   if it reports otherwise — a push to nobody must not read as a push.

`e2e-session-push.mjs`
1. The registry reader finds the fixture session and no other.
2. A live pid whose `procStart` disagrees is classified `recycled`, not `reachable` — see the
   trap below.
3. The socket receives the auth line **first**, then the user frame, both newline-delimited JSON.
4. The frame carries the target's `sessionId`, so a recycled pid is refused by the receiver.
5. A registry entry whose socket is gone is `exited`, and the run still exits 0.
6. Control: a fixture that accepts nothing must be reported failed, not skipped.

## The trap this plan exists to avoid

`procStart` in the registry is **UTC**; `ps -o lstart=` is **local**. Measured 2026-08-28 on two
sessions: registry `Sat Aug 22 10:02:12 2026` against `ps` `Sat Aug 22 20:02:12 2026`, a constant
+10:00 (AEST). A direct string compare classifies **every** live session as recycled and the
feature reports nobody reachable while everything is fine — a green that means the opposite of
what it says. Compare instants, not strings.

## Out of scope

Making the router stateful, or holding MCP session state per client. §1.3 shows the gap is that
the router keeps no reference to a stream it already serves; closing it needs no change to the
stateless design, and changing that design is an R-series decision, not this item's.
