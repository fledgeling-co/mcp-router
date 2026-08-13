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
| F1 | Swift workspace, kit, three targets | foundation | — | — | Opus | **In Progress** | `ai/f1` | run `wf_408f0578-1fb` · wire-verified `claude-opus-5` |
| F2 | Design system in SwiftUI | foundation | F1 | `?only=mac` + `DESIGN.md` §§2–7 | Opus | Untriaged | — | — |
| F3 | Control-API client and models | foundation | F1 | — (surface: `src/control.ts`) | Opus | Untriaged | — | — |
| R1 | Router: core, config, manifest | router | F1 | — | Opus | Untriaged | — | — |
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

- 2026-08-13 — Fleet size confirmed with the user: **all 18 items**. Runner lane verified
  on the wire (`claude-opus-5`), not merely configured. Wave 1 launched: F1 alone, since
  every other item depends on it. Deviation from the skill's serial pre-triage, stated:
  ids are pre-allocated in the ledger and runners are forbidden from writing LEDGER.md at
  all, which removes the shared-write hazard rather than locking around it.
- 2026-08-13 — Preflight: pipeline rooted at `planning/` (docs/ is the published Pages
  source); practices copied from bella-team-files with the Swift gap recorded; router
  work committed as `2e70229`; `DESIGN.md` authored from the verified prototype tokens;
  18 briefs written; ledger and wave plan built. No fleet slot has started.
