# ORCHESTRATOR.md — MCP Router

**This file is the memory, not the transcript.** A fresh session resumes the whole fleet
from here plus `DESIGN.md` and `planning/features-to-triage/LEDGER.md`. Update it after
every state change, before acting on that change.

---

## Contract

| | |
|---|---|
| Repo | `~/Dev/mcp-router` · public · `fledgeling-co/mcp-router` |
| Integration branch | `main` (pushed; the marketing site deploys from `main` `/docs`) |
| Pipeline root | **`planning/`**, not `docs/` — `docs/` is the live GitHub Pages source for mcp-router.fledgeling.app and Jekyll would publish every spec to the public site |
| Specs · plans · briefs | `planning/specs/spec-<ID>.md` · `planning/plans/plan-<ID>.md` · `planning/features-to-triage/` |
| Practices | `planning/practices/` — inherited from bella-team-files. **They are TypeScript/Next.js and carry no Swift guidance.** F1 owes `SWIFT_PRACTICES.md`; until it lands, Swift runners have no house style to conform to |
| Design authority | `DESIGN.md` at the root. Reference implementation `design/mocks/prototype.html` (interactive, deep-linkable) |
| Worktrees | `.worktrees/<ID>` on `ai/<id>` |
| External model CLIs | **On** (no opt-out marker in this repo) but **the codex lane is UNAVAILABLE — do not probe it.** See below |
| Concurrency | ≤8 slots; the DAG peaks at 5 |
| Merges | **Serialized by the orchestrator.** Runners stop at ready-to-merge |

### Two standing decisions, taken with the user at preflight

1. **Swift ships alongside TypeScript; TS stays the installed default until R4's parity
   gate passes.** The router the user's sessions depend on must not be under a rewrite
   with no fallback. Only R4 flips the installer and deletes `src/*.ts`.
2. **macOS is direct-distribution, unsandboxed** (Developer ID + notarized DMG). An app
   that spawns arbitrary MCP subprocesses and rewrites `~/.claude.json` cannot run under
   App Sandbox, so MAS was never available to it. iOS is the opposite: App Store,
   sandboxed. The entitlements differ per target and are written in F1, not retrofitted.

### Standing constraints every runner inherits

- The Mac app talks to the router **only** over the loopback control API. That boundary
  is what lets R1–R4 swap the router underneath without the app changing.
- `command`, `args` and `env` are never writable through the control API's PATCH.
- The phone **queues**; it never installs. Deliberately narrower than "remote install".
- No number is displayed that the router does not observe. There is no fabricated memory
  saving anywhere in this product.
- The Swift MCP SDK is pre-1.0 and warns that minor bumps may break — pin exact.

### Only test a screen you changed, and only that screen — user instruction, 2026-08-14

Standing, and it outranks any sweep-everything habit in the pipeline skills. Changed a row,
a menu item, one pane? Test that one thing. Changed nothing under a screen since it was last
proven? Do not test it at all — cite the existing evidence. Never relaunch the app or boot a
simulator per screen: one launch, one pass, quit.

The measurement behind it: **M1 and I1 have each been through four runs**, and every relaunch
restarted UI verification from zero because nothing on disk recorded what had already been
proven. The Mac lane drives the user's *real* screen through `osascript`, so they sat watching
the same windows and menus driven over and over. That is their time, not just tokens.

The fix that makes it stick across a relaunch: each UI item keeps
`planning/evidence/<ID>-acceptance.md` — one row per screen: screen · how it was verified
(the actual command or AX path) · the commit SHA · result. Append, never rewrite, commit it,
and **read it before testing anything**. A row whose SHA-to-HEAD diff does not touch the files
behind that screen IS the evidence.

This narrows repetition, never rigour: a screen never yet tested still gets tested properly,
once, and behavioural claims still need behavioural proof. Skips get reported as skips.

### The codex lane is down until 2026-08-20 — read before any out-of-family gate

Verified by the orchestrator on 2026-08-14: every `codex exec` call, down to a one-word
probe at low effort, returns *"You've hit your usage limit … try again at Aug 20th, 2026
1:29 PM"*. That is **account-level**, not per-call, and Aug 20 is past this fleet's
horizon. Do not spend a probe rediscovering it.

Run the three out-of-family gates in-family instead: a **fresh `claude -p` opus-5 reviewer
per gate**, briefed adversarially — told to refute, and told that finding nothing is a
failed review rather than a pass — and record `codex: usage limit -> claude (downgrade)`
in the spec, plan or completion note, so the weakness travels with the evidence instead of
disappearing. This is a logged in-family downgrade, which the skill permits; it is not a
skipped gate.

**The trap that makes this dangerous: `codex exec` exits 0 on a usage limit.** A gate keyed
on `$?` records a pass for a review that never ran. The only honest tells are the ERROR
line in the log and a missing-or-empty `-o` file — assert the `-o` file is non-empty before
believing any codex result, on this fleet or a later one.

### A runner that messages the orchestrator ends its turn

Observed twice on 2026-08-14 (R5, and the stopped R3 duplicate): a runner that calls
SendMessage stops, and `TaskStop` then reports *"no active task"* for it. It stays stopped
until the orchestrator replies, which resumes it from its transcript. So a message is not
an aside — it costs the runner its turn.

Two consequences. Runners: say what you need in one message and expect to be resumed;
don't message mid-phase for something you could decide yourself. Orchestrator: **reply
promptly, because a runner awaiting a reply is indistinguishable from a dead one** — the
liveness watcher will report it quiet in fifteen minutes either way.

---

## Wave plan

Waves are the dependency DAG's topological levels. Slots refill on completion rather
than barriering on whole waves, so the real overlap is greater than the table implies.

| Wave | Items | Peak slots | Gate to leave |
|---|---|---|---|
| 1 | F1 | 1 | ✅ **CLEARED** — both targets build, CI green on a clean runner, `SWIFT_PRACTICES.md` landed |
| 2 | F2 · F3 · R1 | 3 | ✅ **CLEARED** — all three merged; merged-tree `make all` exit 0, 237 tests, lint clean |
| 3 | M1 · R2 · R3 · I1 (+ **F4**, injected) | 5 | Mac shell navigable; iOS pairs; Swift router relays a real call. **F4 must merge before wave 4** — M2 and M3 both read `ServerStateTracker` |
| 4 | M2 · M3 · M4 · I2 · R4 | 5 | **R4 is the parity gate and may not pass on a subset** |
| 5 | M5 · M7 · M8 · I3 | 4 | — |
| 6 | M6 | 1 | Phone → Mac inbox round-trip works end to end |

```
F1
├── F2 ─┬── M1 ──┬── M2
│       │        ├── M3 ──┬── M7
│  F3 ──┘        │        └── M8
│       │        └── M4 ──┬── M5 ── M6
│       │                 └── M7
│       └── I1 ── I2 ── I3
└── R1 ─┬── R2 ─┐
        └── R3 ─┴── R4
```

---

## Ledger

Status: `Untriaged → Spec → Plan → In Progress → Ready to merge → Merged` · `Blocked` ·
`Parked`.

| ID | Title | Category | Deps | Mock (deep link) | Lane | Status | Branch | Outcome |
|---|---|---|---|---|---|---|---|---|
| F1 | Swift workspace, kit, three targets | foundation | — | — | Opus | **Merged** `0924040` | — | `make all` exit 0 on the merged tree · 31 tests · both targets build · **A12 (CI) MET** — run 31747021039 `build-and-test: success` on a clean GitHub runner, 2026-08-14 |
| F2 | Design system in SwiftUI | foundation | F1 ✓ | `?only=mac` + `DESIGN.md` §§2–7 | Opus | **Merged** `22d1802` | — | merged-tree `make all` exit 0 · 75 tests · both appearances authored · tokens tested *against* `DESIGN.md`, so doc and code cannot drift · two recorded deviations (tertiary 50% not 25%; `--onAccent` 3.23:1, kit wins) |
| F3 | Control-API client and models | foundation | F1 ✓ | — (surface: `src/control.ts`) | Opus | **Merged** `13825c9` | — | merged-tree `make all` exit 0 · 147 tests · 23 recorded fixtures + `ControlProbe` · **merge found a real defect**: unanchored `.gitignore` `servers.json` had silently swallowed a source fixture, green on the branch and red only when merged |
| R1 | Router: core, config, manifest | router | F1 ✓ | — | Opus | **Merged** `c30eac9` | — | merged-tree `make all` exit 0 · 237 tests · 224 parity vectors · mutation gate exit 0 · SDK pinned exact `0.12.1`, confined to `RouterCore` which neither app links |
| F4 | ServerStateTracker cannot report failure | foundation | F3 ✓ | — | Opus | **Ready — blocks M2, M3** | — | Defect on `main`, found by M1's plan gate and verified in source: `try?` in `pollLoop` discards every typed `ControlAPIError`, and `phase` is pinned to `.disconnected` whenever `stream` is nil (the default). No §5 failure state is renderable from this type. |
| R2 | Router: pool, relay, passthrough | router | R1 | — | Opus | Untriaged | — | — |
| R3 | Router: control, usage, registry | router | R1 ✓ | — | Opus | **Partial — relaunched, auth split out** | `ai/r3` `2a1121e` | 5 commits, clean tree · **352 parity cases in 48 suites** (B76's "exceed 224" is met — the R5 brief's floor is stale) · `make parity-regen` against the reference `dist/` passes, so vectors are reference-derived not back-fitted · **8 live defects found and fixed** by reading `src/*.ts` — the earlier 5, plus `?limit=`/`?limit=0` returning every record via `slice(-0)`, `projectOf` recording a project literally named `/` (BSD `lastPathComponent` vs node `basename('/')`), and `Authorization`-vs-`authorization` bearer shadowing decided by Swift dictionary hash order · B70's attribution cache was entirely unimplemented and is now `AttributionCache` · spec gate 86 findings/82 accepted, plan gate 29/23 · **Phase D critic still not run** — codex was down, and the in-family downgrade had not happened when the duplicate stopped · **`2a1121e` was committed by the stale duplicate with `git add -A` and contains the surviving runner's in-flight work; kept deliberately, see changelog** |
| R5 | Router: OAuth and the auth routes | router | R3 | — | Opus | **Ready** | — | Split out of R3 by the orchestrator: P4/auth entire (B60–B66, no `Auth/` sources exist), `/approve` and `POST /servers/:name/auth`. R3 blocked twice, once on an interrupt and once on scope; this is the slice that made the turn unfinishable. Carries B76 (must exceed R1's 224) and B69's partial-identity contradiction |
| R4 | Parity harness and cutover | router | R2, R3, R5 | — | Opus — never downgrade | Untriaged | — | — |
| M1 | Mac shell, menu bar, keyboard | mac | F2, F3 ✓ | `?only=mac` | Opus | **Partial — relaunched** | `ai/m1` `6035cc4` | Spec (37 clauses), plan, design mock and the shell models committed, tree clean · 264 tests, lint clean, 6 red-green proofs · both codex gates REJECTed and were fully addressed · **no UI shipped yet**, so every UI clause is unevidenced and the runner said so rather than claiming build gates as UI evidence · plan Phases B/C/D remain |
| M2 | Activity | mac | M1 | `?only=mac&pane=activity` | Opus | Untriaged | — | — |
| M3 | Servers: the breaker board | mac | M1 | `?only=mac&pane=servers` | Opus | Untriaged | — | — |
| M4 | Skills and marketplaces | mac | M1 | `?only=mac&pane=skills` | Opus | Untriaged | — | — |
| M5 | Discover | mac | M4 | `?only=mac&pane=discover` | Opus | Untriaged | — | — |
| M6 | Inbox and pairing (Mac) | mac | M5 | `?only=mac&pane=inbox`, `?sheet=pair` | Opus | Untriaged | — | — |
| M7 | Evals and Cleanup | mac | M3, M4 | `?pane=evals`, `?pane=cleanup` | Opus | Untriaged | — | — |
| M8 | Settings, popover, quarantine | mac | M3 | `?pane=settings`, `?popover=1`, `?sheet=held` | Opus | Untriaged | — | — |
| I1 | iPhone shell and pairing | ios | F2, F3 | `?only=phone&pairing=1` | Opus | Untriaged | — | — |
| I2 | iPhone Discover and detail | ios | I1 | `?only=phone&tab=discover` | Opus | Untriaged | — | — |
| I3 | iPhone Triage, Queue, Library | ios | I2 | `?only=phone&tab=triage` | Opus | Untriaged | — | — |

**Mock note:** every item's mock is a deep link into the single interactive
`design/mocks/prototype.html`, not a separate file. `design/mocks/mac-surfaces.html` and
`ios-surfaces.html` are superseded static contact sheets — do not build from them; they
are pending deletion.

---

## Deferred children — registered, not yet scheduled

Reported by wave-1/2 runners. Each names the item that should absorb it; none blocks a wave.

| # | Child | Absorbed by | Why it was deferred |
|---|---|---|---|
| D-a | Record the HTTP status alongside each recorded fixture | R4 | The fixture set proves the *body* decodes; the status is a second assertion the parity harness will want and the client currently infers |
| D-b | Surface the call-log stream's skipped-record count | M2 | The stream already skips an unreadable record "not silently"; nothing yet displays the count, so a lossy stream looks clean |
| D-c | Expose `usage(limit:server:cwd:)` in Activity's filters | M2 | The client takes all three filters; the Activity mock only offers server |
| D-d | Make the router's caller attribution deterministic rather than `lsof`-raced | R3 | F3's fixture capture raced the async lookup and recorded an unattributable call. Worked around with a capture-time guard; the router-side fix belongs to whoever owns the control API |
| D-e | Signed/notarized macOS packaging | new item, after M8 | Blocked on **Needs input #1**, not on code |
| D-f | Machine-readable token block in `DESIGN.md` | M1 | F2's parity gate parses prose tables today; a fenced block would make it robust to editing |
| D-g | Parity vectors for divergences D1/D3/D4 | R4 | R1 recorded three deliberate divergences from the TypeScript router with **no parity vector**. R4 must not read their absence as agreement |

---

## Needs input — not blocking any wave

| # | Question | Blocks |
|---|---|---|
| 1 | Apple Developer team ID and signing identity for Developer ID + notarization, and the App Store Connect app record for iOS | F1 can build and test unsigned; **release** artifacts for both platforms are blocked until these exist |
| 2 | Bundle identifiers — `app.fledgeling.mcprouter` / `.ios` assumed unless told otherwise | F1, changeable later but noisier after the App Store record exists |
| 3 | The phone currently queues but cannot install, narrowing the original "or the user can remote install them" | I3 ships the narrower behaviour; widening it is a later item, not a change to this fleet |

---

## Changelog

- 2026-08-14 — **F4 died a second time, and left a mutant in the source.** It ran the
  mutation gate as a background task and polled its output file for a sentinel; the task
  was killed at 14:56:09 without writing one, and the poll never returned because the child
  died with the parent. Mutant **M56** was left applied in `ServerStateTracker.swift`
  (`guard snapshot != lastPublished` rewritten to `if false { return }`) — applied to disk,
  killed before it could run or revert. Since F4 must merge before wave 4, that is
  deliberately-broken code one merge away from `main`. Reverted, the real work committed as
  `ca32ee4`, and F4 relaunched in `wf_196b1c68-865` with the cause named in its brief.
  Inherited by the relaunch rather than re-run: M50–M54 KILLED, **M55 SURVIVED** (a real
  coverage gap — no test observes the notification lost when `register` is deferred into a
  `Task`), M56/M57 never ran. Also flagged: `ai/f4` predates the hooks commit, so its diff
  proposes deleting `planning/hooks/*` and reverting `watch-fleet.sh` — rebase before merge.
- 2026-08-14 — **R5 reported a second writer in its worktree; there wasn't one.** It found
  `Auth/` files it did not recognise, a package resolve it did not remember starting, and a
  subagent citing `FileModeWriting.swift` by path. It stopped rather than raced and committed
  only its own files by explicit pathspec (`0fad8c0`) — exactly right given what it believed.
  Checked before answering, because if it had been right the correct action was to stop:
  across every agent transcript in the session, `.worktrees/R5` has **21 Edit/Write calls,
  all from R5 itself**, four of them the very files it disowned. The resolve was its own
  `swift build`; the subagent was the one plan-gate agent it spawned. Cause is almost
  certainly compaction — 323 entries — which its brief already covers with a re-read rule.
  Told to resume; it owns `ai/r5`.
  Its finding was still worth having: **`DELETE /servers/:name/auth` is already shipped on
  `ai/r3`**, so R5 drops it rather than building a second implementation that can silently
  disagree.
- 2026-08-14 — **Watcher, revision 6: a journalled result no longer retires an item.** R5
  exposed the hole — an orchestrator message resumes a stopped runner, that turn journals a
  result, and the runner then works for another half hour with nothing watching it. Liveness
  alone now decides whether to fire; the result only changes what the event means (`STOPPED`,
  owes a report, versus `QUIET`, probably died). Added a third liveness test ahead of both:
  **a live process whose cwd is inside the worktree**, one `lsof` per pass for all items.
  I1 forced that one — its `xcodebuild` writes DerivedData *outside* the worktree, so 18
  minutes of real compiling read as 18 minutes of nothing to a file-mtime check.
  The proving needed a negative control, because the first red run fired **zero** and that
  looked like a pass: R3, M1 and R5 had all started builds between probes, so the new gate
  suppressed everything and a broken gate would have looked identical. `FLEET_REPO` is now
  overridable purely so it can be pointed somewhere no process can match — under that
  control all 8 items fire, R5 included, and the real repo stays silent.

- 2026-08-14 — **Two R3 runners were editing `ai/r3` at once for ~18 minutes, and I put
  the second one there.** When auth was split out into R5 I relaunched R3 with a corrected
  brief ("auth split out") in a new workflow run — and never stopped the original, which
  was still running the pre-split brief in the run that also carries R5. So one branch had
  two writers, and R5's scope had two owners. Found by accident: the liveness watcher's
  denominator listed R3 in two live runs. Both prompts were read before acting, and the
  ledger's own row (*"Partial — relaunched, auth split out"*) named which one was intended.
  The stale runner was not stoppable by `TaskStop` — workflow-inner agents are not tasks —
  so it was stopped by message, told explicitly not to commit, revert or clean, and to hand
  back findings instead. It had already committed `2a1121e` with `git add -A` four minutes
  earlier, sweeping up the surviving runner's in-flight P6 work.
  **Kept, not reset.** `reset --soft` would leave every file byte-identical, so it buys only
  a more accurate commit message — and it would hand a *live* runner an unexpectedly dirty
  index mid-turn. That is the same live-worktree hazard this fleet already got away with
  once, and attribution is not worth spending it on. The content is entirely in-scope R3
  work on R3's own branch; no `Auth/` sources or OAuth routes reached it, so R5 is
  uncontested. Verified rather than assumed: `git ls-tree` for Auth sources, and
  `ControlHandler` carries only `DELETE /auth` and the 401 path, which are control-surface
  and R3's by right.
  Its stop report was worth more than its code: three further live port defects (all now
  fixed on the branch), B70's cache implemented from the reference's real semantics, the
  parity corpus at 352, a **spec** defect where B69's "never a partial identity" cannot
  coexist with B71's equality-with-the-reference, and a correction retiring a plan-gate
  finding as latent rather than live. All of it forwarded to R5, whose brief carried the
  now-stale 224 floor and the unresolved B69 contradiction.
  Two mechanisms changed. Runners are told a message costs them their turn; the orchestrator
  is told to reply promptly, since a runner awaiting a reply looks exactly like a dead one.
- 2026-08-14 — **The codex lane is down fleet-wide until Aug 20**, reported by the R5
  runner and reproduced here with a one-word probe: an account-level usage limit, past this
  fleet's horizon. The three out-of-family gates now run in-family as adversarially-briefed
  `claude -p` opus-5 reviewers, logged as `codex: usage limit -> claude (downgrade)` in each
  artifact. Recorded in the contract above so in-flight runners see it on their next
  pre-call re-grep — that file is the only kill-switch that reaches a running runner — and
  in `planning/fleet-runner.js` so future launches inherit it.
  The dangerous half: **`codex exec` exits 0 on a usage limit.** Any gate keyed on `$?` would
  have recorded a pass for a review that never ran. Only the log's ERROR line and an empty
  `-o` file distinguish them.
- 2026-08-14 — **The liveness watcher was measuring the wrong thing and reported two false
  deaths.** It keyed on one agent's transcript mtime, so it called M1 quiet at 16m while M1
  was mid-build, and F4 quiet at 24m while F4's gate output was seconds old. Two distinct
  causes, one fix: a transcript is appended when an agent *speaks*, and an agent thirty
  minutes into a `swift build` writes thousands of files and not a byte to it; separately,
  the harness retries under a new agentId, leaving the original's transcript frozen forever
  with no journalled result. Liveness is now judged **per item**, from the newest of every
  agent's transcript *and* the item's worktree (walking the tree, plus `.build/build.db`
  directly, since that one file is touched throughout a compile). Item keying folds a retry
  and its corpse into one row for free.
  Proved both directions before trusting it: silent at real thresholds while M1 and F4 were
  working, and **9 of 9 unfinished items firing** at `FLEET_QUIET=0`. The first red run used
  `FLEET_QUIET=1` and printed only 7 — a transcript written that same second reads as 0s of
  silence, which is not `-lt 1`. A denominator two short is exactly what a coverage hole
  looks like, and it took a second run at 0 to show it was the threshold, not the code.

- 2026-08-14 — **I1 returned early and the fleet read it as delivered.** The runner
  finished Phase 1, wrote a genuinely good design report — 12 sections, 30 phone frames,
  both appearances — and ended its turn. A returned turn is a *success* to the harness, so
  `agent()` journaled a result, nothing retried it, and the item looked complete while no
  spec, no plan and no code existed. Its only artifact sat **untracked** in the worktree,
  one `git clean` from gone.

  This is a different failure from a death and hides better: a dead agent leaves an error,
  this one leaves a good report. The tell was liveness, not output — its transcript stopped
  at 12:43 while the other three were still writing. Worth noting the two adjacent states
  it was distinguished from in the same sweep: R2 looked equally idle on disk but was alive
  inside a 10-minute codex plan gate, and an earlier check reported all four worktrees
  untouched, which was a **broken predicate** (`find -newermt` with a relative time returns
  nothing on BSD find) rather than four idle runners. Uniform zeros are a bug until proven
  otherwise.

  Actions: Phase 1 committed by the orchestrator as `af0234f`; I1 relaunched from Phase 2
  in the same worktree on the same branch, with the failure named in its resume brief; and
  `planning/fleet-runner.js` now carries "finish the whole item in one turn — a phase report
  is not a deliverable", with the instruction that a report naming its own incompleteness is
  recoverable while one that looks finished is not.

- 2026-08-14 — **A runner pushed to `main`, and the instruction against it is now a hook.**
  A wave-3 runner committed `04eac69` ("Ignore .worktrees/") in the shared main checkout and
  pushed it to origin. The change is **correct and kept** — an untracked `.worktrees/` is a
  real hazard, one `git add -A` from the root would commit another branch's whole working
  tree — but it moved the integration branch under a merge sequence that assumes one writer.
  Mid-merge it could have corrupted the tree.

  Every runner prompt already said stop before merge, so the instruction is not the control.
  `.git/hooks/pre-push` now refuses any push without `MCPR_ORCHESTRATOR=1`, proved in both
  directions (refused without, allowed with). Worktrees share the hooks directory, so it
  covers wave 3's in-flight runners too — which matters, because a fleet cannot message its
  own workflow-inner agents. `planning/fleet-runner.js` carries the explicit rule for waves
  4–6. The hook is scaffolding for this run; remove it when the fleet finishes.

- 2026-08-14 — **CI red on the merged main, and the test was wrong rather than the code.**
  `31763577290` failed one assertion: the stream-liveness check timed from *before* the
  connection opened, charging URLSession construction and the TCP handshake to stream
  latency, so a contended runner read 0.52s against a 0.36s bound while streaming
  correctly. Replaced the wall-clock budget with the ordering property the docstring
  already stated — the stub records when it sent its last line, and the first record must
  arrive before that instant. No threshold left to tune. Green on `8e9c689`
  (`31764012564`). The first red-green proof was itself void: `swift test --filter` on the
  *display* name matched nothing and reported `0 tests in 0 suites passed`, which is a gate
  that never ran wearing a pass. Re-proved against the function name.

- 2026-08-14 — **Wave 3 launched: M1, R2, R3, I1.** Four slots. All four wire-verified
  `claude-opus-5` on the first launch.

  That first launch **died whole in 27 seconds** — two runners on `Connection refused`,
  two on `Connection lost mid-response`. Recorded because the signature is easy to
  misread as wave 2's capacity outage and the remedy is opposite: `ps -o etime` showed the
  local gateway had been up **2m07s**, so the launch landed mid-restart. Not capacity, not
  code. Nothing was lost — no worktree, no branch, `started=4 results=0` — so recovery was
  a fresh launch, not `resumeFromRunId`, which would have replayed nothing while
  re-asserting an empty cache. Before relaunching, the lane was proved end to end with a
  real one-token request rather than trusted from `/healthz`: a health flag says the
  process is up, not that a request can obtain an account.

- 2026-08-14 — **Wave 2 cleared: F2, F3 and R1 all merged**, serially, each gated on the
  merged tree rather than on its own branch. `22d1802` → `13825c9` → `c30eac9`; final
  merged tree `make all` exit 0, **237 tests**, `no-raw-design-values: clean`. All three
  worktrees removed and branches deleted, each proved merged by `git branch --merged`
  first. Seven deferred children registered above.

  **The merge found a defect no branch gate could have.** F3 was green on `ai/f3` and red
  the moment it merged: five tests failing on one missing fixture. `.gitignore` carried a
  bare `servers.json` for the router's runtime config, and an unanchored gitignore pattern
  matches at *every* depth — so it silently swallowed
  `app/Sources/MCPRouterKit/Control/Fixtures/servers.json`. The file stayed on disk in the
  author's worktree, which is exactly why its own gate passed. Both runtime-state patterns
  are now anchored (`/servers.json`, `/manifest.json`) and the fixture is committed. This
  is the merge-only defect class again: the break existed on no branch.

  Both merges conflicted in `app/Package.swift` and both were purely additive — F2's
  `MCPRouterUI`/`MCPRouterUITests`, F3's `ControlProbe`, R1's `RouterCore` product,
  `RouterCoreTests` and the exact-pinned MCP SDK. Kept all of them; the SDK stays confined
  to `RouterCore`, which neither app target links, so the kit's no-external-dependencies
  promise still holds for everything the apps compile.

- 2026-08-14 — **A12 met and wave 1's exit gate cleared.** `main` pushed
  (`e5a61ce..e15b31d`, 10 commits) and Swift CI executed for the first time: run
  31747021039, `build-and-test: success`. This is the first verification of F1 that did
  not happen on the authoring machine — every prior green was a warm local toolchain.
  The `pages-build-deployment` run also succeeded and `docs/` was untouched in the diff,
  so mcp-router.fledgeling.app is unaffected.
- 2026-08-14 — **Wave 2 relaunched into the contended pool** at the user's instruction,
  riding lifeline's retries rather than waiting for the `~/Dev/hopper` fleet to finish.
  All three wire-verified `claude-opus-5`; two took 503s within the first minutes and
  backed off, as expected. Each carries a RESUME brief naming its existing worktree and
  branch, forbidding a fresh worktree, and pointing at its pause checkpoint.

- 2026-08-14 — **Wave 2 died on capacity, not code.** All three runners took
  `503 no-eligible-account` — "9 of 11 accounts at or over their usage reserve". The
  gateway pool is shared, and `lifeline` shows **another live fleet in `~/Dev/hopper`**
  with agents in flight. Relaunching into that starves again, so wave 2 is **paused, not
  failed**, and nothing has been discarded.

  The journal reads `started=6 results=0`, so a `resumeFromRunId` would replay **nothing**
  — the recovery is a re-run in the existing worktrees on the existing branches, never a
  fresh start, because all three died LATE:

  | Item | Branch | Gate now | Died at |
  |---|---|---|---|
  | F2 | `ai/f2` (4) | `make test` exit 0, 65 tests, clean | mid Phase-D critic, after two codex lane failures |
  | F3 | `ai/f3` (2) | `make test` exit 0, **93 tests** | entering the red-green proving pass |
  | R1 | `ai/r1` (6) | **RED — does not compile** | mid-write of `VectorRegistry.swift` |

  Orchestrator actions taken while the pool is contended:
  1. **Rescued 52 orphaned files.** F3 died with 28 uncommitted and *nothing* on its
     branch; R1 with 24 and a broken build. Both are now WIP commits, R1's deliberately
     red and labelled as such — losing the files is worse than a red commit on a branch
     that is never merged in that state.
  2. **Wrote pause checkpoints into all three specs**, since no runner survived to write
     its own: exact stopping point, what is on disk, the diagnosed-but-unfixed defect, and
     the next three steps. A resume reads those instead of re-deriving state.
  3. Confirmed each branch's gate independently rather than trusting a report.

  **Resume is blocked on capacity, which is the user's call, not a code fix.**

- 2026-08-14 — **Wave 2 launched: F2, F3, R1.** Three slots.
- 2026-08-14 — **F1 merged as `0924040`.** Verified independently rather than on the
  runner's report: protected files diffed clean (`DESIGN.md`, the ledger, this file,
  `install.sh`, `package.json`, `src/`), `make all` re-run to exit 0 on the **merged**
  tree, and the token-parity gate proved able to fail — changing `DESIGN.md`'s ground
  colour by one digit fails the suite. A gate that cannot fail is not evidence.
  Four things the run surfaced, recorded rather than smoothed over:
  1. **Two runner attempts died and were retried by the harness** before the third
     returned; the journal holds three `started` entries and one `result`. The surviving
     runner correctly read the on-disk work as a resume rather than restarting.
  2. **A runner wrote to this file, which its prompt forbids.** Its content was accurate
     and has been absorbed here, but the edit was reverted and re-authored by the
     orchestrator. Ownership is reasserted at every merge rather than trusted to the
     instruction — that is the control that actually holds.
  3. **A12 (CI) has never executed.** The workflow is delivered and calls the same
     Makefile targets, but nothing is pushed, so wave 1's "CI green" exit gate is
     **not met**. Recorded as unmet, not waived.
  4. **~1,800 lines of the earlier hand-rolled scaffold were deleted** (`ServersView`,
     `DiscoverView`, `ServerDetailView`, `MenuBarView`, `ActivityView`, `CleanupView`,
     `SettingsView`, `RootView`). Consistent with the brief, and recoverable from
     `97d4a55` — M1–M8 may want it as reference.
  Also: `make acceptance` needs an Accessibility grant and fails *safe* (exit 2) without
  one, so on hosted CI it will report blocked rather than green.

- 2026-08-14 — A task notification reported wave 2 stopped with "no completion record"
  and instructed a relaunch with `resumeFromRunId`. **Declined — the premise was false.**
  The scanner reports the run `LIVE · session-alive`, one agent still writing, and F2/F3
  worktrees held by live processes with an active `swift test`. Relaunching would have
  dropped a second set of agents into worktrees already being written to. It would also
  have bought nothing: `started=6 results=0`, so the replay cache is empty and a resume
  cold-starts regardless. The notification's `TICKET-123` is lifeline's placeholder id,
  not one of ours. Six starts against three items = the harness retrying; the recurring
  cause on every agent is a **session/usage limit**, which is throttling this wave rather
  than killing it. Left alone; a tracked waiter is armed for the settle. Journal resolves
  under session `bdb1ad3b`, so nothing is orphaned — but note compaction can mint a new
  session id and silently orphan a journal mid-run, which would break any later resume.
- 2026-08-13 — Fleet size confirmed with the user: **all 18 items**. Runner lane verified
  on the wire (`claude-opus-5`), not merely configured. Wave 1 launched: F1 alone, since
  every other item depends on it. Deviation from the skill's serial pre-triage, stated:
  ids are pre-allocated in the ledger and runners are forbidden from writing LEDGER.md at
  all, which removes the shared-write hazard rather than locking around it.
- 2026-08-13 — Preflight: pipeline rooted at `planning/` (docs/ is the published Pages
  source); practices copied from bella-team-files with the Swift gap recorded; router
  work committed as `2e70229`; `DESIGN.md` authored from the verified prototype tokens;
  18 briefs written; ledger and wave plan built. No fleet slot has started.
