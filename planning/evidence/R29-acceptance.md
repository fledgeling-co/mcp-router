# R29 — acceptance evidence

**Branch** `ai/r29` · **Bundle** `planning/evidence/R29/` · **Gates** run at the tip recorded below.

Every row cites an artifact by path and the value read from it. Nothing here was measured against
a live Claude Code session belonging to other work: the two proofs build their own session
registry, bind their own socket, and boot their own router in their own `HOME`.

---

## 1 · The brief's open question, settled

The brief asked, and made it a precondition: *is there any programmatic way to make a live session
re-read, or does it strictly require the slash command?* **There is, for the tool list, and it
needs nobody.**

| # | Claim | Evidence |
|---|---|---|
| 1.1 | Claude Code opens a standalone `GET /mcp` SSE stream after `initialized` and holds it | `GET /mcp -> standalone SSE stream OPENED`, `planning/evidence/R29/exp-A-session-id-sent.log:2` |
| 1.2 | Pushing `notifications/tools/list_changed` down it makes the client re-fetch, unprompted | `PUSHED notifications/tools/list_changed` at `…32.121Z` then `tools/list #2 answered with 2 tool(s)` at `…32.124Z` — **3 ms** — `planning/evidence/R29/exp-A-session-id-sent.log:4-5` |
| 1.3 | It happens mid-task, with no model and no person | the receiving session was inside a 25-second `sleep` for the whole window; same log |
| 1.4 | A stateless server is not excluded — the `mcp-session-id` header is not the discriminator | identical result with the header suppressed, `planning/evidence/R29/exp-B-session-id-suppressed.log:4-5` |
| 1.5 | The router already served that stream and kept no reference to it | `Stateless: a transport and server per request`, `src/router.ts:409` at `bb3359a` |

The fixture that produced 1.1–1.4 is committed at `planning/evidence/R29/fixture-push.mjs`, so
the measurement is repeatable rather than asserted.

**What this does not settle.** Skills, plugins and harness config are not in the MCP protocol and
have no equivalent notification. For those the socket message is the only lever and it can only
ask — §3.

---

## 2 · The primary path, against the real router

`planning/evidence/R29/e2e-live-reload.log` · `node scripts/e2e-live-reload.mjs` · **16/16, exit 0**

| # | Requirement (from the brief's acceptance sketch) | Row in the log |
|---|---|---|
| 2.1 | *Changing an extension reaches every live session without a person typing a command* | `the attached session was told, unprompted — 1 notification(s)`, and `(it arrived 87ms after the add)` |
| 2.2 | …and the session actually sees the change | `and re-fetching now returns the new tool — first__alpha, second__beta` |
| 2.3 | A removal reaches it too | `a removal reaches an attached session too — 1 notification(s)` · `and the tool it served is gone from the re-fetch — 1 tool(s)` |
| 2.4 | The path people type is covered, not only the app's | `a manifest rebuilt by \`mcpr index\` from another process reaches the attached session — 1 notification(s)` |
| 2.5 | *A session that is mid-task is not corrupted by the arrival* | §1.3, plus the re-fetch in 2.2 is the client's own housekeeping |
| 2.6 | *Sessions that have exited are not unreachable failures* | `the stream is dropped when the client goes — 0` |

### The controls, which are why 2.1–2.6 mean anything

| # | What it refuses | Row |
|---|---|---|
| C1 | A push to nobody reading as a push | `CONTROL: a push with nobody attached reports 0 delivered — delivered=0, streams=0` |
| C2 | Announcing a change that moved no tools | `CONTROL: a change that does not move the tool list announces nothing — 0` |
| C3 | The poller re-firing on an unchanged manifest, twenty times a minute | `CONTROL: the poller does not re-announce an unchanged manifest — 0` |

C1 is not decoration. The SDK's `send()` **returns silently** over a closed stream —
`// Stream is disconnected - event is stored for replay, nothing more to do`,
`node_modules/@modelcontextprotocol/sdk/dist/esm/server/webStandardStreamableHttp.js:835` — so a
`delivered` count built on a resolved promise reports a push to nobody as a push to everybody.
`LiveReload` counts bytes that actually left the response instead.

### It can go red

Mutation: `LiveReload.register` made a no-op (`this.streams.add(stream)` → `void stream`), so the
registry holds nothing. Result **11/14, exit 1**, failing exactly the three rows that carry the
claim: `the router holds a notification stream — 0 stream(s)`, `the attached session was told —
0 notification(s)`, `a removal reaches an attached session too — 0 notification(s)`.

---

## 3 · The secondary path, against a fixture socket this item owns

`planning/evidence/R29/e2e-session-push.log` · `node scripts/e2e-session-push.mjs` · **29/29, exit 0**

The fixture is a unix socket the test binds itself, in a temporary `HOME`, with a registry it
writes. `listSessions` is never called without an explicit home, so the real registry is not read.

| # | Claim | Row in the log |
|---|---|---|
| 3.1 | The auth line goes **first**, then the user frame — the order the transport requires | `the FIRST line is the auth frame — auth` · `the fixture received exactly two lines — 2` |
| 3.2 | The frame carries the target's session id, so a reused pid is refused at both ends | `the user frame carries the target session id — r29-fixture-session-id` |
| 3.3 | *The push names what changed* | `the message names what changed` |
| 3.4 | It is attributed rather than arriving as an anonymous peer | `the message is wrapped so the receiving transcript attributes it` |
| 3.5 | It tells the receiver the truth about itself | `the message says the slash commands in it will not run` |
| 3.6 | *A session that cannot reload says so* — five classes, not one | `a dead pid reads as exited` · `a registered session whose socket is gone reads as noSocket` · `a session with no key file reads as unauthenticated, not unreachable` · `a procStart spelled in local time reads as recycled, not reachable` |
| 3.7 | *A stale socket is a normal condition, not an error* | `the exited row is counted, not treated as a failure — 1` · `and nothing was aimed at it` · exit 0 |
| 3.8 | A socket file with nothing behind it is a refusal, not a delivery | `a socket file with nobody behind it is reported refused, not delivered — refused (connect ENOENT …)` |

### The controls

| # | What it refuses | Row |
|---|---|---|
| C4 | A dry run that looks like a delivery | `CONTROL: a dry run emits no bytes at all — 0 line(s)` · `CONTROL: a dry run reports no delivery — skipped` |
| C5 | A dry run that measured nothing | `CONTROL: a dry run still names who it would reach` |
| C6 | A sweep over an empty registry reporting a target | `CONTROL: an empty registry reports 0 considered and 0 targeted` |

### It can go red, and the mutation is the one the plan predicted

Mutation: `parseProcStartUtc(r.procStart)` → `Date.parse(r.procStart)`, i.e. comparing the two
spellings of one instant rather than the instant. Result **11/29, exit 1**, and the two arms that
matter come back **exactly inverted**:

```
FAIL  a live session with a matching procStart is reachable — recycled
FAIL  a procStart spelled in local time reads as recycled, not reachable — reachable
```

A router shipping that mutation reports **nobody reachable at the moment everybody is**, on every
machine not running at UTC, and every check that does not compare the two spellings passes.

---

## 4 · A defect this proof found in its own subject

The first run of `e2e-session-push.mjs` used a hard-coded "surely dead" pid of `4194303`. macOS
`ps` rejects that outright — `ps: process id too large` — prints **nothing for the pids that were
fine**, and exits non-zero. `processStarts` read the empty output as "nobody is alive" and
reclassified **every live session on the machine as exited**.

One junk row in a registry the router does not own would have silently disabled the whole feature
while reporting success. Fixed in `processStarts` by falling back to a per-pid pass when the batch
answers for nobody; the regression arm is
`a registry row whose pid \`ps\` refuses does not blind the sweep — the live session read reachable`.

---

## 5 · Boundaries, so nothing here is read as more than it is

- **`delivered` is not `reloaded`.** §3 reports that bytes reached a session's inbox. The router
  cannot observe compliance and does not claim it. The word `reloaded` appears nowhere in the
  outcome vocabulary.
- **§1's mechanism carries no payload.** `list_changed` has no field for what changed, so *"the
  push names what changed"* is met by §3 and not by §2. Stated in `README.md` rather than left to
  be discovered.
- **The socket ask ships off.** `notifySessions` defaults to false; `GET /sessions` reports its
  state, and `e2e-live-reload.log` asserts it: `the socket ask is off unless it was turned on`.
- **Two populations, never merged into one number.** A session attached to the router has a
  stream; a session in the registry is a session on this machine. `mcpr sessions` and
  `GET /sessions` print them separately.
- **Not verified here:** anything against a real Claude Code session on this machine, deliberately
  and by instruction. §1 used a session started for the purpose and torn down; §2 and §3 used
  fixtures. Behaviour against the thirteen live sessions is **unmeasured**, not proven.
