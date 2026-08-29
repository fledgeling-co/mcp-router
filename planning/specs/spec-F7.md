# F7: the session analyst, and the button that has never done anything

**Category:** router + mac · **Brief:** `planning/features-to-triage/F-session-analyzer-skill-recommender.md`
**Closes:** DEF-065's analyst half — `Button(InsightsBoardCopy.analyseNow) {}`, and the three
configuration readouts SURF-026 replaces with an empty state.
**Related:** M20 (built the *delivery* — `AnalystFinding`, `FindingAnnouncement`, the
`finding.analyst` notification category — and recorded that nothing constructs one), M22 (built
`GET /insights`, whose `analyst` member has been `null` since the day it shipped).

`PRD.md` §6 specifies a session analyst. Nothing under `app/Sources` implements one, and three
surfaces say so out loud: `ControlInsights.swift` writes `analyst: null` with a comment naming the
absence, `InsightsBoard` draws an empty state with a dim button wired to `{}`, and
`FindingArrival.swift` states that **no banner of its family can fire in a shipped build, because
there is no producer.** This item is the producer.

---

## 1 · What this item is, in one paragraph

The router grows an analyst: it reads the session stores of the harnesses on this machine, extracts
the shell commands and missing-tool errors that recur, asks a model **running through a CLI the
user is already signed into** which capability from a candidate list would help, and records the
result. `GET /insights` stops answering `analyst: null`. `POST /insights/analyse` runs it now.
`PATCH /insights/analyst` changes which model judges and how often it runs. The Insights board's
analyst card stops being an empty state and becomes the design's four readouts, three of them
actuating.

## 2 · The boundary, stated before the requirements

**In.** Ingestion of the four JSONL session stores, pattern extraction, the CLI judge with its
primary/fallback ladder, candidate resolution, 30-day deduplication, persistence, the three control
routes, and the Insights analyst card.

**Out, each with its reason.**

| deferred | why |
|---|---|
| Cursor ingestion | `~/.cursor/chats/` is SQLite. Every other store is JSONL and shares one reader; SQLite is a second reader with a second failure surface. The store is **enumerated and reported unread with its reason on the wire** rather than omitted, because a store silently skipped is indistinguishable from one that held nothing. |
| The Inbox recommendation card and the macOS banner | The delivery layer assigns it elsewhere in its own words: *"The day the analyst ships, it is the producer that arrives,"*, `app/Sources/MCPRouterKit/Inbox/FindingArrival.swift:14` at `08a24ed`. The layer is built and unwired; wiring it is a second surface (SURF-005) with its own cases. This item does not fire a banner and does not claim to. |
| The Settings analyst sheet (`⌥⌘A`, the per-store checkboxes, *Turn the analyst off*) | The design draws the same three settings twice — once as popups on Insights, once as a sheet in Settings. This item builds the Insights half, which is the half DEF-065 names. |
| A timer that fires the cadence unattended | See REQ-030.7. The cadence is **stored, reported, and used to compute `nextRunAt`**, and `POST /insights/analyse` is what actually runs. A daemon-side scheduler is a lifecycle change to `RouterService` and is scoped separately. The wire reports `scheduled: false` beside the cadence so no surface can read "every 6 hours" as a promise the router does not keep. |

## 3 · Requirements

**REQ-030.** *The router has a session analyst, and every figure it reports is one it counted.*

1. **It reads what it says it read.** The corpus reports `linesRead` and, per store, the lines it
   discarded and why. A store that is absent, unreadable, or of a format this reader does not
   handle is reported **by name with its reason**, never omitted. `linesRead` is the count of lines
   the reader actually parsed, not the count of bytes it opened.
2. **A pattern is a count, not a guess.** A signal reaches the model only when it recurs at or above
   the floor. Each pattern carries its occurrence count, the harnesses it was seen in, and at most
   three verbatim examples.
3. **The finding's subject comes from the router, never from the model.** The judge is handed a
   candidate list the router computed and must answer with an id **from that list**. A reply naming
   anything else is rejected, counted as `rejectedFindings`, and produces no finding. This is the
   guard that makes a hallucinated capability name unrepresentable rather than merely unlikely.
4. **The ladder is honest about which rung ran.** The run records the lane and model that produced
   it and whether the primary was used. A fallback run never reads as though the primary judged it.
5. **Nothing leaves the machine.** The judge is a local CLI process. No route in this item opens a
   network socket; candidate resolution is a port, and when the daemon supplies none the run
   completes with zero findings and `candidatesUnavailable` on the wire rather than a fabricated
   recommendation.
6. **A finding seen before stays quiet for 30 days.** Suppression is by fingerprint over the entry
   and the signals behind it, so a finding whose evidence has *grown a new signal* is a new finding
   and fires again.
7. **The cadence is a setting, and the wire says it is not a schedule.** `cadence` and `nextRunAt`
   are reported alongside `scheduled: false`. Nothing in this item claims a run happened that did
   not.
8. **The button acts, and the proof is read elsewhere.** `POST /insights/analyse` changes state that
   `GET /insights` reports and that the store file on disk holds. `Analyse now` is enabled exactly
   when the router serves the route.

## 4 · The wire

`GET /insights` — `analyst` becomes an object once a run exists, and stays `null` before the first.

```
analyst: {
  lane, model, label,            // which rung judged, and its display label
  ranAt, linesRead, findings,    // the design's "41 min ago · 12,400 lines · 3 findings"
  usedFallback, rejectedFindings,
  primary: {lane, model, label}, fallback: {lane, model, label} | null,
  cadence, cadenceLabel, nextRunAt | null, scheduled: false,
  stores: [{harness, path, read: bool, lines, discarded, reason | null}],
  recent: [{id, entryID, subject, sentence, evidenceCount, judgedBy, signals: [...]}]
}
```

`POST /insights/analyse` → 200 with the same object · 503 when the router has no analyst ·
409 while a run is in flight. `PATCH /insights/analyst` → 200 with the same object · 422 naming the
member it refused. Both require the control token; both are declared divergences from
`src/control.ts`, which answers the whole `/insights` family 404 by design (`div-m22-insights`).

## 5 · What could make this item's own evidence hollow

- **A judge stub that always answers.** Every engine test drives a judge that can refuse, time out,
  or answer with an id outside the candidate list, and the rejection path is asserted by the
  `rejectedFindings` count rather than by the absence of findings — an absence is what a broken
  engine also produces.
- **An empty-corpus green.** The reader tests assert a positive `linesRead` and named discards, so
  a reader that opened nothing cannot pass by reporting nothing.
- **A control that reports its own success.** The board case presses `Analyse now` and reads the
  outcome from a second `GET /insights` against the recording client, plus the store the engine
  wrote — never from the button's own callback.
