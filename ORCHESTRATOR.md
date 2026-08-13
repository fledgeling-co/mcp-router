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
| External model CLIs | **On.** No opt-out marker in this repo. The three out-of-family gates route to codex `gpt-5.6-sol` at `max`, read-only |
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

---

## Wave plan

Waves are the dependency DAG's topological levels. Slots refill on completion rather
than barriering on whole waves, so the real overlap is greater than the table implies.

| Wave | Items | Peak slots | Gate to leave |
|---|---|---|---|
| 1 | F1 | 1 | Both targets build; CI green; `SWIFT_PRACTICES.md` exists |
| 2 | F2 · F3 · R1 | 3 | Design system renders every token; control client passes against recorded fixtures |
| 3 | M1 · R2 · R3 · I1 | 4 | Mac shell navigable; iOS pairs; Swift router relays a real call |
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
| F1 | Swift workspace, kit, three targets | foundation | — | — | Opus | **Merged** `0924040` | — | `make all` exit 0 on the merged tree · 31 tests · both targets build · **A12 (CI) unmet — never executed, branch unpushed** |
| F2 | Design system in SwiftUI | foundation | F1 ✓ | `?only=mac` + `DESIGN.md` §§2–7 | Opus | **Paused — capacity** | `ai/f2` (4) | green, 65 tests · died mid Phase-D critic · checkpoint in spec |
| F3 | Control-API client and models | foundation | F1 ✓ | — (surface: `src/control.ts`) | Opus | **Paused — capacity** | `ai/f3` (2) | green, 93 tests · 28 files orphaned, rescued by orchestrator · died entering red-green pass |
| R1 | Router: core, config, manifest | router | F1 ✓ | — | Opus | **Paused — capacity, RED** | `ai/r1` (6) | **does not compile** — `VectorRegistry.swift:68` actor-isolated default · 24 files rescued red |
| R2 | Router: pool, relay, passthrough | router | R1 | — | Opus | Untriaged | — | — |
| R3 | Router: control, auth, usage, registry | router | R1 | — | Opus | Untriaged | — | — |
| R4 | Parity harness and cutover | router | R2, R3 | — | Opus — never downgrade | Untriaged | — | — |
| M1 | Mac shell, menu bar, keyboard | mac | F2, F3 | `?only=mac` | Opus | Untriaged | — | — |
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

## Needs input — not blocking any wave

| # | Question | Blocks |
|---|---|---|
| 1 | Apple Developer team ID and signing identity for Developer ID + notarization, and the App Store Connect app record for iOS | F1 can build and test unsigned; **release** artifacts for both platforms are blocked until these exist |
| 2 | Bundle identifiers — `app.fledgeling.mcprouter` / `.ios` assumed unless told otherwise | F1, changeable later but noisier after the App Store record exists |
| 3 | The phone currently queues but cannot install, narrowing the original "or the user can remote install them" | I3 ships the narrower behaviour; widening it is a later item, not a change to this fleet |

---

## Changelog

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
