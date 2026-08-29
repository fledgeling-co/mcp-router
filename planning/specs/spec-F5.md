# F5: skill and server use, by version — and the boundary past which no version may be credited

**Category:** router · **Brief:** `planning/features-to-triage/F-skill-version-usage-history-stats.md`
**Depends on:** R28 (the router holds skills, plugins and marketplaces) · R30 (the register read
that names an installed plugin's version) · M22 (`GET /insights`, and the rule that a figure the
router cannot take is `null` with a reason beside it, never `0`).

The brief asks for "the exact version of each tool at the moment it was executed". This spec is
mostly about the word **exact**, because two of the three things it needs are on disk and the third
is not, and the item is worthless if it reports the third as though it were the first two.

**Nothing in this item sends anything anywhere.** §6 states what is read, what is written, where,
and what the gate that holds it there refuses.

---

## 1 · The design of record contradicts itself here, and F5 is the fault line

`design/mcp-router-console.html` says both of these:

| line | surface | what it says |
|---|---|---|
| 2780–2781 | the skill detail pane | *"Why there is no 'use, by version'* — This pane used to chart a run count per version. **The router never sees a skill run** — the client loads it into an agent's context and the router is not on that path — so the bars were counting something nothing here observes." |
| 3490–3525 | the Insights board | *"Skill and server use, by version"* — a table crediting `design-review 2.3.1` with 142 runs and `trawl 1.4.2` with 64, under the callout *"The version recorded is the one that was live when the call ran, so a run against 1.4.0 never counts toward 1.4.2's evidence."* |

The second table is the thing the first section says is unobservable. `InsightsBoard.swift`'s own
doc comment already parked it on the first reading — *"The version table has no data behind it at
all: `UsageRecord` carries the server, the tool and the caller, and no version anywhere."*

**Both halves are partly right, and the measurements in §2 say which part.** The router really is
not on the path of a skill run. But the *harness* writes down every skill it ran, in its own session
transcripts, on this machine — so a skill run is observable here, just not by the relay. That is a
different mechanism with a different privacy posture and a different failure mode, and the whole of
this item's honesty is in never letting a number from it stand unlabelled beside a number the router
counted itself.

So F5 follows the Insights half of the mock, draws the table, and makes the callout at 3525 a rule
the code enforces rather than a caption: **a run that cannot be shown to have happened against the
installed version is not counted toward it.** §4 is that rule. It turns out to exclude a great deal.

---

## 2 · What was measured, and by what instrument

Read-only, on the author's machine, **2026-08-29**, with `python3` over `~/.claude`, `~/.codex`,
`~/.cursor`, `~/.grok` and `~/.gemini`. No value from any file below is reproduced in this
repository; what was taken is shape and counts.

| reading | figure |
|---|---|
| Claude Code session transcripts (`~/.claude/projects/**/*.jsonl`) | **59,476 files · 19.5 GB** |
| lines in a 400-file random sample | 20,268, of which **0** failed to parse as JSON |
| …carrying a `timestamp` | 19,332 of 20,268 (**936 do not**) |
| `tool_use` blocks in a 200-file sample | 3,320 across 21 distinct tool names |
| …that are `Skill` | **15**, input shape `{skill, args}` (13) or `{skill}` (2) |
| …that are `mcp__<server>__<tool>` | 64 |
| distinct `version` values on a transcript line | 23, all of the form `2.1.2xx` — **Claude Code's own version, never the skill's** |
| `~/.claude/skills` directories | 22, all carrying `SKILL.md` |
| …whose frontmatter declares `version:` | **13 — nine do not** |
| `plugins/installed_plugins.json` records | 127, every one carrying `version`, `installedAt`, **`lastUpdated`** and `gitCommitSha` |
| `~/.codex` `*.jsonl` | 4 — a session index and archived rollouts, line shape `{timestamp, type, payload}`, no skill concept |
| `~/.grok` `*.jsonl` | 2,169 — **sandbox events, not transcripts**; no tool call in them |
| `~/.cursor` / `~/.gemini` `*.jsonl` | 0 / 1 |

Four of those rows decide the design, and three of them refute the obvious approach.

### 2.1 · A skill run IS observable, and the transcript does not say which version ran

`Skill` appears as an ordinary `tool_use` block carrying `{"skill": "ship-feature:ship-feature"}`.
So the brief's first clause is satisfiable: the harness writes down every skill it invoked, with a
timestamp, on this machine.

The `version` member on the same line is `2.1.239` — **Claude Code's**. Nothing in a transcript
names the version of the skill that ran. Nor could it: the harness reads `SKILL.md` out of a
directory and the directory's contents at that moment are not recorded anywhere in the session.

So *"the exact version at the moment it was executed"* is **not recoverable from a transcript**, for
any past run, by any amount of parsing. A table that joined today's installed version onto a
historical run would be attributing evidence to a version that may not have existed when the run
happened — which is exactly what the mock's own callout forbids, printed under a table that does it.

### 2.2 · One boundary of version history is on disk, and exactly one

Every one of the 127 plugin records carries `lastUpdated` beside `version`. That is a real
measurement about the past, and it is the only one there is:

* a run at `T >= lastUpdated` happened while the **installed version** was the live one. The
  installed set has not moved since `T`, so crediting it is a deduction, not an assumption.
* a run at `T < lastUpdated` happened before the current version arrived. **The version that was
  live at `T` is not on disk anywhere.** It is not the installed one — that is the one fact
  available — and no other candidate exists.

There is no second boundary. `installed_plugins.json` keeps one `lastUpdated` per record, not a
history, so the attributable window is `[lastUpdated, now]` and everything before it is dark.

**The alternative this beat:** credit every historical run to the installed version and put the
caveat in a caption. That is what the mock draws, it is what makes the numbers large, and it is the
defect this repository has a gate family for — a count whose correct answer and whose fabricated
answer are the same shade of green. The cost of refusing it is stated rather than hidden: on this
machine most historical runs will report **no version established**, and the table will look
emptier than the mock does. That is the measurement.

### 2.3 · Nine of twenty-two skills have no version to credit at all

13 of 22 `SKILL.md` files declare `version:`. The mock already knows this — its skills pane reads
*"~/.claude/skills · 5 skills, not versioned … there is no upstream to update from and no version
to pin evidence to"*.

The brief's own assumption names the fallback: *"version resolution falls back to 'unversioned' or
plugin git commit hash when explicit semantic versions are absent"*. A commit sha exists for
plugins (`gitCommitSha`, on all 127) and not for a hand-written skill, so the general fallback is
the one thing every entry has: **a digest over its own bytes**, which `ExtensionStamp.measure`
already computes. Evidence then pins to *these bytes* rather than to a number, and a run before the
bytes last changed is dark for the same reason a run before `lastUpdated` is.

### 2.4 · The corpus cannot be rescanned per request

59,476 files and 19.5 GB. A 200-file sample took 0.5 s, so a full pass is roughly **150 seconds and
19.5 GB of reads**. `GET /insights` answers in a request; a reader that walked the corpus on each
call would hang the control API and hammer the disk.

So the scan is **incremental against a watermark** — per file, the size and mtime last read and the
byte offset reached — and a file whose size and mtime are unchanged is not opened. Transcript files
are append-only JSONL, which is what makes an offset valid across runs; a file that **shrank** is
not resumed from an offset into different bytes, it is re-read from zero and said to have been.

### 2.5 · Claude Code is the only harness here that records a skill run

Codex's rollouts are a different line shape and have no skill concept. Grok's 2,169 `*.jsonl` are
sandbox events with no tool call in them. Cursor has none.

This is `HarnessCallCount`'s situation exactly, and it takes that type's answer: a harness with no
figure reports **`null` and the reason**, never `0`. A zero would be the finding — *this harness ran
no skills* — and it would be fabricated.

---

## 3 · What is recorded, where it is written, and what leaves this machine

**Nothing leaves this machine.** There is no endpoint, no key, no queue and no batch anywhere in
this item, and §6 is the gate that keeps it that way.

| | |
|---|---|
| **Read** | Session transcript files under a root the operator names. From each line: the `timestamp`, and — only for an assistant `tool_use` block — the tool's `name` and, for `Skill`, the `skill` input. |
| **Not read** | Everything else on the line, and it is the majority: prompts, assistant prose, tool arguments other than `skill`, tool results, file contents, `cwd`, `gitBranch`, `sessionId`, `requestId`. What it discards it **counts**, per §5. |
| **Written** | `<router home>/invocations.jsonl` — one line per observed invocation: `ts`, `kind`, `name`, `harness`, plus `tool` for a server call, and nothing else. `<router home>/versions.jsonl` — the version ledger of §4.2. `<router home>/invocation-watermarks.json` — per file, its size, mtime and the offset reached. |
| **Sent** | Nothing. |

**Where the claim actually rests, stated precisely, because the loose version of it was written
here first and was false.** An earlier draft of this row said the reader "does not decode a line
into a general structure and then select". It does — a JSONL line has to be parsed to be read at
all, and `JSONParser.parse` builds a whole `JSONValue`. What is true is narrower and stronger: that
value is a **local that goes out of scope at the end of the loop**, and the only thing that survives
`TranscriptScan` is an ``InvocationEvent``, which has **no member** for a prompt, an argument, a
result, a working directory, a branch or a session id. So the guarantee is structural rather than a
matter of the reader being disciplined, and `InvocationEvent.wireKeys` (asserted by CASE-0263) is
what reddens if a fifth member is ever added.

`<router home>` is the directory that already holds `usage.jsonl` and `usage-stats.json`
(`UpstreamConfig.path`), at the same permissions.

**The scan is off until it is pointed somewhere.** `MCP_ROUTER_TRANSCRIPTS` is the whole of the
configuration and unset is the shipped state — a colon-separated list of `<harness>=<root>` pairs,
the shape `PATH` already teaches. The router could find `~/.claude/projects` on nearly every machine
it runs on and deliberately does not, because a default there would mean an upgrade silently began
opening 59,476 files of somebody's agent history, and no release note makes that the same act as
being asked to.

With it unset every route in this family answers the way `/extensions` answers with no store: it
names the missing capability rather than serving an empty history, because a router that has read
nothing and a machine that has run nothing are not the same claim. **`RouterService` supplies the
reporter**, which is the line that matters rather than the type existing: `registry` and `authFlow`
each existed, were unit-tested and shipped `nil` in `RouterServiceDispatch`, so every route
depending on them answered a refusal on the wire while the suite stayed green
(`control-registry-search`, `D-p1-a`).

**The first scan is armed once, at `start()`, detached after `listen()`.** A cold corpus is roughly
150 seconds; every later pass is nearly free because the watermark skips every unchanged file.
Once per start rather than on a timer is a real limit and not a plan — a long-lived daemon's window
stops advancing until it restarts — and it is registered as `D-f5-e` rather than defaulted, because
how often to re-read somebody's session directory is a decision to be asked for.

---

## 4 · The types

### 4.1 · `CapabilityVersion` — provenance in the case, following `ClientProcessName`

```
case declared(String, from: String)   // read from the entry's own descriptor; `from` is the file
case derived(digest: String)          // no declared version: SHA-256 over the entry's bytes
case unknown(reason: String)          // nothing established it
```

`ClientProcessName` is the precedent and the reason is the same one written there: the difference
between a measurement and a naming claim belongs in the type, where a reader can see it without
trusting prose. `declared` for the 13 skills and the 127 plugins that carry a version; `derived` for
the nine that do not; `unknown` for an entry whose descriptor could not be read at all.

### 4.2 · `VersionLedger` — the boundary set, which grows

`versions.jsonl`, append-on-change: each time the router reads the installed set, an entry whose
version differs from the last observation of that capability appends `{ts, kind, name, version,
source}`. Nothing appends when nothing moved.

Seeded from `lastUpdated` (§2.2), so the ledger starts with one boundary per plugin — the only
history disk holds — and gains a real one every time a version moves under a running router. The
window that can be attributed therefore **widens with use**, and how far back it reaches is a
readable figure rather than an assumption.

**`RouterService.start()` seeds before it scans, and the order is load-bearing rather than tidy.**
A window folded with an empty ledger reports every run `unestablished`, which is a correct answer to
the wrong question and is *indistinguishable from the honest refusal this whole item exists to
give*. So the register is read first and the corpus second.

The register is `~/.claude/plugins/installed_plugins.json` by default, overridable with
`MCP_ROUTER_PLUGIN_REGISTER`. **It is read by default once a corpus has been named, and the
transcript root is not**, which is a distinction rather than an inconsistency: a session transcript
records what a person said and did, and this file is a version manifest — 127 records of `{version,
installedAt, lastUpdated, gitCommitSha}` with no user content of any kind. It is also the only
statement about the past on the machine, so an operator who asked for use-by-version and did not get
it read would be handed a table crediting nothing at all.

### 4.3 · `VersionAtRun` — the join, and where it refuses

For an invocation of capability `C` at time `T`:

```
case attributed(String, since: String)   // the newest boundary at or before T says this, AND no
                                         // later boundary disagrees
case superseded(movedAt: String)         // a later boundary carries a different version, so the
                                         // change sits on an unknown side of T. Counted toward
                                         // NOTHING.
case unestablished(reason: String)       // no boundary reaches T, or its timestamp is not orderable
```

**"No later boundary disagrees" is the whole rule, and it is not "T is after the newest boundary".**
A boundary asserts *at `ts`, this was at `v`* and nothing wider, so two consecutive boundaries with
different versions bracket a change whose **moment is unknown** — the router saw `U` at `ts_p` and
`V` at `ts_b`, and the swap happened somewhere between. A run inside that interval could have been
on either side. A later boundary carrying the **same** version is confirming evidence and does not
supersede anything.

`superseded` is the case the item exists for. It is not an error and it is not a gap in the data —
it is the correct answer, and it is the mock's own callout made mechanical: *a run against 1.4.0
never counts toward 1.4.2's evidence.* Its count is reported beside the table, in the way
`InsightsResponse.otherCalls` is reported beside the harness bars, so the rows and the headline
reconcile instead of quietly disagreeing.

### 4.4 · `InvocationEvent` — the record, and everything it cannot carry

Ordered JSON members, like `UsageRecord`, for the same reason: it is written with a compact
stringifier and read back, so key order and the omission of an absent member are on the wire.

`ts` · `kind` (`skill` | `plugin` | `server`) · `name` · `harness`. **There is no field for prompt
text, arguments, project, cwd or session id**, so there is no path by which one is written even by
mistake — the absence is structural, not a matter of the reader being careful.

---

## 5 · What the reader drops, and how it says so

`TranscriptScan` is a raw-input reader that discards most of what it is given, and it reports every
class rather than returning a count of what it managed to keep:

| counted | meaning |
|---|---|
| `linesRead` | lines taken off disk |
| `unparseable` | not JSON. 0 in a 20,268-line sample, and the last line of a live session is routinely torn |
| `withoutTimestamp` | parsed, but carries no `timestamp` — **936 of 20,268 in the sample**, so this is a real class and not a theoretical one |
| `notAnInvocation` | parsed and timestamped and carries no `tool_use` block — the bulk of every transcript |
| `unnamedTool` | a `tool_use` block with no usable `name` |
| `filesSkipped` | unchanged since the watermark, so not opened at all |
| `filesReread` | shrank since the watermark, so re-read from zero rather than resumed |

`totalCalls` is meaningless without these, which is `UsageInsights.unreadableLines`' argument one
directory over: a count of what parsed is not a count of what was there.

---

## 6 · The egress gate

`scripts/lint/no-telemetry-egress.sh` refuses any outbound-network symbol under
`app/Sources/RouterCore/Invocations` — `URLSession`, `URLRequest`, `NWConnection`, `Network`,
`Socket`, `dataTask`, `http://`, `https://`. It is in `make lint`.

**It ships with a selftest that makes it fail**, because this fleet has now found five oracles that
could not fail inside one merged item and a printer filed as a gate. `no-telemetry-egress-selftest.sh`
writes a file carrying one refused symbol into a scratch copy of the tree, requires the gate to exit
non-zero on it, removes it, requires exit 0, and exits non-zero if the gate ever agreed with itself.
A gate that examined no files exits non-zero rather than reporting clean.

---

## 7 · Acceptance

| # | requirement | oracle |
|---|---|---|
| A1 | A `Skill` block in a transcript becomes one `InvocationEvent` naming the skill | drive `TranscriptScan` over a fixture and read the events |
| A2 | An `mcp__<server>__<tool>` block becomes one event of kind `server` naming the server | fixture |
| A3 | A line with no timestamp is **counted** as `withoutTimestamp` and produces no event | fixture, asserting both the count and the absence |
| A4 | A torn last line is counted as `unparseable` and costs nothing else in the file | fixture whose last line is truncated mid-object |
| A5 | No event carries prompt text, arguments, cwd or session id | the type has no member for them; a test asserts the serialised keys are exactly the four |
| A6 | A run **after** the newest boundary is `attributed` to the installed version | ledger fixture |
| A7 | A run **before** a boundary is `superseded` and counts toward no version | ledger fixture — the assertion is that the version's total does **not** move |
| A8 | A capability with no declared version resolves `derived(digest:)` | store fixture with no `version:` in frontmatter |
| A9 | An unchanged file is not opened on the second scan | watermark fixture, asserting `filesSkipped` moved and the events did not |
| A10 | A file that shrank is re-read from zero and says so | watermark fixture asserting `filesReread` |
| A11 | With no transcript root configured, the routes name the missing capability | control-handler test asserting the status and the sentence |
| A12 | The export carries the same rows as the window fold, in both formats | one fold, two encoders, compared |
| A13 | A harness with no observable transcript reports `null` and a reason, never `0` | fold test |
| A14 | The egress gate fails on a planted symbol and passes when it is removed | the selftest, run in `make lint` |

## 8 · Deferred children

| id | what | why it is not here |
|---|---|---|
| `D-f5-a` | The Insights board's *Skill and server use, by version* table in SwiftUI | The route and the fold are what the board reads. `no-raw-design-values.sh` A36 forbids file access under `MCPRouterUI/Boards`, so the board cannot read a transcript itself and ships behind the route either way — the same order `div-m22-harnesses` records for the Harnesses board |
| `D-f5-b` | Stamping `UsageRecord` with the upstream's `serverInfo.version` | The version is on the MCP `initialize` reply, which the pool holds. Reaching it is a change to R2's pool surface rather than to this reader, and the ledger's `server` kind is resolvable without it |
| `D-f5-c` | A codex-shaped transcript adapter | Its line shape is `{timestamp, type, payload}` and it has no skill concept; the four members this reader wants are not all there. A second harness is a root plus an adapter, and there is nothing to adapt yet |
| `D-f5-e` | A periodic corpus refresh | `start()` scans once, detached, so a long-lived daemon's window stops advancing until it restarts. Once is right for the first pass — a cold corpus is ~150 seconds — and a timer is a separate decision about how often to re-read somebody's session directory, which is the kind of thing that should be asked for rather than defaulted |
| `D-f5-d` | A durable per-day rollup that survives log rotation | `UsageStore`'s argument — *the aggregate is what makes history disposable* — applies here too. The window this item answers for is bounded by what `invocations.jsonl` holds, and it reports that horizon |
