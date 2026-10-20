# reverify-F7 — session analyst and skill recommender (DEF-361)

**Verdict: NEEDS-WORK.** The analyst is built, ported to TypeScript at `f587a11b`, and its engine, routes and Mac card are tested and passing. Two things keep it from PASS. The wire returns an `analyst` object before the first run, where spec §4 says `null`, and a stale parity record. Two brief surfaces are deferred by the spec: the macOS banner and the Inbox card.

Checked against main at `63d7e208`, by branch `ai/reverify-2`, 2026-10-20.

**Method.** Requirements were derived from `planning/features-to-triage/F-session-analyzer-skill-recommender.md` and `planning/specs/spec-F7.md` before code was read. Verdicts: MET, PARTIAL, NOT MET, DEFERRED (the spec names the reason and an owner). Brief lines the spec defers are reported as unmet, not hidden.

**Base and drift.** Line references are at `63d7e208`, the tree this branch was cut from. Main has since advanced 21 commits (to `7432a5e1` at the time of the check). The files this item depends on are unchanged on main except `src/control.ts`, `src/insights.ts` and `src/router.ts` (the usage-window and inbox merges); the analyst routes there moved to lines 1038, 1044 and 1062 with the same logic. The audited Swift files are unchanged.

**Retirement check (DEF-361 requirement).** F7 was ported under plan P6. Every client call to `/insights`, `/insights/analyse` and `/insights/analyst` is served by `src/control.ts` (`:464-466` for the claim, `:983`, `:1005`, `:1023` for the handlers). The Mac panel calls `POST /insights/analyse` and `PATCH /insights/analyst`. The Windows Insights model does not call either route; it is an offline mockup, and the spec does not require a Windows analyst card. No dead control, so no DEF was filed.

| # | Requirement | Source | Verdict | Evidence |
|---|---|---|---|---|
| F7-1 | REQ-030.1 — the corpus reports `linesRead` (lines parsed) and per store the lines, discards and a reason; an absent or unreadable store is named, and the SQLite Cursor store is reported unread with its reason | spec-F7.md:47 | MET | `src/analyst-corpus.ts:53` (`export function sessionStores(home: string): SessionStore[]`). Four JSONL stores (Claude, Codex, Grok, Gemini) and Cursor enumerated as unread. `test/analyst-corpus.test.ts` — "it reports the lines it parsed, and that number is not zero", "a line it cannot use is counted as discarded rather than dropped in silence", "every store appears, and an absent one says why", "the SQLite store is enumerated, unread, and carries the reason it was not opened". All `ok` in the npm run. |
| F7-2 | REQ-030.2 — a signal reaches the model only at or above the recurrence floor; each pattern carries count, harnesses and at most three examples | spec-F7.md:51 | MET | `src/analyst-patterns.ts:11` (`export const PATTERN_FLOOR = 3;`). `test/analyst-patterns.test.ts` — "a signal under the floor does not reach the judge", "no more than three examples travel with a pattern", "a missing tool is its own kind, and the shell spellings both reach it". |
| F7-3 | REQ-030.3 — a judge reply naming an id outside the router's candidate list is rejected, counted in `rejectedFindings`, and yields no finding | spec-F7.md:54 | MET | `src/analyst-judge.ts:128` (`if (!known.has(entry) \|\| !knownSignals.has(signal) \|\| accepted.some(...))`). `test/analyst-judge.test.ts` — "an id outside the candidate list is rejected and counted", "a signal the run never counted is rejected, so the evidence figure cannot be invented". |
| F7-4 | REQ-030.4 — the run records lane and model; a fallback run never reads as the primary | spec-F7.md:58 | MET | `src/analyst.ts:181` (`run: this.record(corpus, { lane, usedFallback: index > 0, rejected: read.rejected, findings })`). `test/analyst-engine.test.ts` — "the primary refusing runs the fallback, and the run says so", "every rung refusing records no run at all and carries what each one said". |
| F7-5 | REQ-030.5 — the judge is a local CLI; no socket; with no candidate source a run gives zero findings and `candidatesUnavailable` | spec-F7.md:60 | MET | `src/router.ts:406` (`candidates: null,`). `test/analyst-engine.test.ts` — "no candidate source means no findings and a stated reason, never a bare zero". |
| F7-6 | REQ-030.6 — 30-day suppression by fingerprint over entry and signals; a grown signal set fires again | spec-F7.md:64 | MET | `src/analyst.ts:42` (`export const SUPPRESSION_MILLISECONDS = 30 * 24 * 3_600_000;`). `test/analyst-engine.test.ts` — "the same finding inside thirty days is suppressed, and after them it fires again", "a finding whose evidence gained a new signal is a new finding". |
| F7-7 | REQ-030.7 — `cadence` and `nextRunAt` reported with `scheduled: false`; nothing claims a schedule | spec-F7.md:67 | MET | `src/analyst.ts:435` (`scheduled: false,`). `test/insights-analyst-route.test.ts` — "A3 — the cadence is reported as a preference, never as a schedule". |
| F7-8 | REQ-030.8 — `POST /insights/analyse` changes what a later `GET /insights` reports and what is on disk | spec-F7.md:70 | MET | `src/control.ts:1018` (`json(res, 200, analystEnvelope(outcome.run, deps.analyst.settings()));`). `test/insights-analyst-route.test.ts` — "A4 — pressing the button changes what a LATER GET reports". |
| F7-9 | Wire §4 — `analyst` is `null` before the first run and an object after | spec-F7.md:76 | **NOT MET** | `src/control.ts:999` (`analyst: deps.analyst ? analystEnvelope(deps.analyst.lastRun(), deps.analyst.settings()) : null,`). With an analyst configured, `GET /insights` returns an object whose readings are null before the first run, not `null`. The test "A2 — an analyst that has never run reports its settings with every reading absent" (`test/insights-analyst-route.test.ts:166`) pins this behaviour, so the deviation is intentional in code but not in the spec. The spec and the code need to agree. |
| F7-10 | `POST /insights/analyse` returns 200 with the object; 503 with no analyst; 409 while a run is in flight | spec-F7.md:90 (§4) | MET | `src/control.ts:1005-1007` (`if (!deps.analyst) { json(res, 503, { error: ANALYST_UNAVAILABLE });`); 409 on `outcome.kind === 'alreadyRunning'`. `test/insights-analyst-route.test.ts` — "A6 — a run already in flight is refused rather than doubled". |
| F7-11 | `PATCH /insights/analyst` returns 200 or 422 naming the refused member | spec-F7.md:91 (§4) | MET | `src/control.ts:1031-1033` (`json(res, 422, { error: err.message, member: err.member });`). `test/insights-analyst-route.test.ts` — "A8 — a PATCH takes, and an unknown lane is refused by member name". |
| F7-12 | Both routes require the control token | spec-F7.md:92 (§4) | MET | `src/control.ts:531` (`if (mutating \|\| p.startsWith('/pairing/')) {`). `test/insights-analyst-route.test.ts` — "A9 — both paths are claimed, gated, and method-checked; a neighbour is not claimed". |
| F7-13 | §5 hollow-evidence guards: a judge that can refuse, time out or go off-list; positive `linesRead`; the control test reads its outcome from a second `GET` and the store | spec-F7.md:95 | MET | Tests in F7-1 to F7-11 assert the counts and the second read, not the button's callback. The "A4" test reads the outcome from `GET /insights`. |
| F7-14 | Brief: each harness's lightweight model — Claude Haiku, Cursor Composer, Grok 4.6 medium, Codex GPT-5.6-luna low | brief:13 | MET | `src/analyst-lanes.ts:26` (`const LANES: Record<AnalystLane, LaneSpec> = {`). Pinned models: `claude-haiku-4-5`, `composer`, `grok-4.6` with `--effort medium`, `gpt-5.6-luna` with `model_reasoning_effort="low"`, and `gemini-3.7-flash-high`. `test/analyst-judge.test.ts` — "lane argument vectors match their pinned forms", "each lane runs its pinned model, and the Claude lane is the cheap rung". |
| F7-15 | Brief: scans Claude, Cursor, Grok and Codex transcripts | brief:12 | PARTIAL | Claude, Grok and Codex read (F7-1). Gemini is read in addition. Cursor is enumerated and reported unread (F7-1), as the spec §2 says. |
| F7-16 | Brief: macOS local notification on high-confidence findings | brief:15; spec-F7.md:39 (deferred to `FindingArrival` / SURF-005) | DEFERRED | No finding dispatch in `src/` or `app/Sources`. The spec states this is out of scope. Still unmet against the brief. |
| F7-17 | Brief: recommendation cards in Inbox and Insights, one-click review and install | brief:16; spec-F7.md:39 | DEFERRED | No Inbox card for analyst findings; no install action wired. The Insights analyst card (F7-19) exists. Deferred by the spec, unmet against the brief. |
| F7-18 | Brief: "runs periodically on an idle cadence" | brief:20; spec-F7.md:41, :67 | DEFERRED | The spec defers the timer and reports `scheduled: false`. No scheduler exists. |
| F7-19 | Mac Insights analyst card: four readouts, three menus, `Analyse now` calls the route and reloads | plan-F7.md:28 (§D); spec-F7.md:24 | MET | `app/Tests/MCPRouterUITests/InsightsAnalystBoardTests.swift` — "pressing Analyse now posts once and redraws from a SECOND read". Suite "F7 · the Insights analyst card" passed in the Swift run below. Call site: `app/Sources/MCPRouterKit/Control/LiveControlAPIClient+Absent.swift:37` (`_ = try await analystWrite(.post, "insights/analyse", body: Data("{}".utf8))`). |
| F7-20 | Parity record: `planning/parity/surface.tsv` describes the `/insights` family accurately | spec-F7.md:92 (§4: "declared divergences from `src/control.ts`") | PARTIAL | `planning/parity/surface.tsv:130` (`divergence	div-m22-insights	M22 GET /insights is answered here and 404 at the reference`). No rows for F7's POST or PATCH analyst routes. The record was not updated when the routes were ported. |

**Commands run (2026-10-20, on `63d7e208`):**

```
governor-run --weight 2 -- npm test
# tests 314
# suites 28
# pass 314
# fail 0
```

```
cd app && governor-run --weight 4 -- swift test --build-system native -j 4 --filter 'SkillsUpdatesModelTests|SkillsWriteModelTests|InsightsAnalystBoardTests|CapabilityDocumentSheetTests|PairingRouterCodeTests'
Test run with 36 tests in 5 suites passed after 0.148 seconds.   exit=0
```

**Not run:** the Windows client; the mock-fidelity gate for `insights` (named by the ledger as owed: `planning/fidelity/insights.*` was derived before the analyst card existed).

**Open for the owner.** F7-9 (wire contract versus test pinned to the deviation), F7-16/F7-17 (banner and Inbox card, spec defers to SURF-005), F7-18 (no scheduler), F7-20 (stale parity rows).
