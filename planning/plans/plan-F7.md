# plan-F7 — the session analyst

Spec: `planning/specs/spec-F7.md`. Base: `08a24ed`. Branch `ai/n3`, worktree `.worktrees/N3`.

## Slices

**A · `app/Sources/RouterCore/Analyst/` — the subsystem.** Six files, no route, no UI.

| file | what it owns |
|---|---|
| `AnalystLane.swift` | the five CLI rungs, their binaries, models and argument vectors; the cadence enum and its labels |
| `AnalystSettings.swift` | primary, fallback and cadence as a value; parse and render through `JSONValue`; refuse an unknown lane by name |
| `SessionCorpus.swift` | the store table, the JSONL reader, and the per-store read report — lines read, lines discarded, reason |
| `SessionPatterns.swift` | command heads and `command not found` signatures, counted, floored, capped at three examples |
| `AnalystJudge.swift` | `AnalystJudging` port, the prompt, the strict reply parser, `CLIAnalystJudge` over an `AnalystCommandRunning` port |
| `AnalystEngine.swift` | corpus → patterns → candidates → judge (primary, then fallback) → reject off-list ids → dedupe → run record; `AnalystStore` persistence |

**B · `app/Sources/RouterCore/Control/ControlAnalyst.swift` — the three routes.** `analyst` on
`GET /insights` built from `AnalystPort`; `POST /insights/analyse`; `PATCH /insights/analyst`.
`ControlDeps.analyst` optional, absent → 503 naming the missing capability, matching `extensions`,
`caches` and `health`.

**C · the app's models and client.** `AnalystRun` gains the spec §4 members; `AnalystFindingCard`,
`AnalystLaneChoice`, `AnalystStoreReport` are new. `ControlAPIClient` gains `runAnalyst()` and
`setAnalyst(primary:fallback:cadence:)`; `LiveControlAPIClient` and `FixtureControlAPIClient`
implement both.

**D · `InsightsBoard`'s analyst card.** Four readouts and three menus where the empty state was;
`Analyse now` calls the model, which calls the client, which reloads. The empty state stays for
`analyst == nil` and gains the *reason* it is empty rather than the *absence of a feature*.

## Tests

Every arm below is watched red before it is trusted.

| suite | what it holds |
|---|---|
| `AnalystCorpusTests` | a fixture tree with four stores; positive `linesRead`; a malformed line counted as discarded with its reason; an absent store reported by name; the SQLite store reported unread |
| `AnalystPatternTests` | the floor; the example cap; `command not found` as its own kind; a signal seen in two harnesses carrying both |
| `AnalystJudgeTests` | the reply parser: a well-formed line, a line naming an id outside the candidate list, a truncated reply, an empty reply |
| `AnalystEngineTests` | primary refuses → fallback runs and `usedFallback` is true; both refuse → no run recorded and the error surfaces; off-list id → `rejectedFindings` 1 and `findings` 0; the same finding twice inside 30 days → suppressed; a grown signal set → fires again; no candidate source → `candidatesUnavailable` |
| `ControlAnalystRoutesTests` | through `ControlHandler.handle`: the three routes, the 503 with no port, the 409 in flight, the 422 on an unknown lane, and `analyst: null` before the first run |
| `InsightsAnalystBoardTests` | the model's `analyseNow()` against a recording client: the request the client received, then the readouts drawn from the reloaded response |

## Gates

`make lint` whole · `make test` · `citation-gate` · `sweep-control-gate` (new files need a
disposition row at commit) · the campaign's `control-census.py` after SURF-026's
`controlsUnactuatable` rows are removed.

## Case ids

Read at `08a24ed`: 142 cases, maximum **CASE-0222**. This item allocates from **CASE-0223**.
Requirement inventory maximum **REQ-029**; this item allocates **REQ-030**.
