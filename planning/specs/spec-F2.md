# F2: The design system in SwiftUI

**ID:** F2
**Status:** Ready for Work
**Created:** 2026-08-14
**Last updated:** 2026-08-14

## Feature description

*(Original brief, verbatim from `planning/features-to-triage/F2-design-system.md`.)*

# F2 — The design system in SwiftUI

**Depends on:** F1.

Turn `DESIGN.md` into code, so no surface ever hardcodes a colour or a font size.

- Colour: label tiers `--t1..t4`, grounds, fills, and the four system hues, as an
  asset catalogue with light + dark. **Light must be authored, not inverted** — it does
  not exist yet and DESIGN.md §10 records that as owed.
- Type: the eight-role SF ramp as `Font` extensions. Nothing off the ladder.
- The icon set: SF Symbols at matched weights where one fits, authored assets where
  none does. The prototype's 21-symbol sprite is the inventory.
- Control styles matching the kit ladder (Mini 16 → XL 36), the inset-rounded selection
  fill at radius 8, and the focus ring.
- **The breaker** as a reusable `View` with its three lit states and the two springs
  from DESIGN.md §7. This is the app's signature element and its construction is
  load-bearing: the slot must be wider and taller than the toggle so it reads in the
  dormant state, which is where two prototype rounds failed.
- The nine state containers from DESIGN.md §5 — empty, loading, partial, error, offline
  — as composable views, so a surface cannot ship populated-only by accident.

Reference: `design/mocks/prototype.html`, `DESIGN.md` §§2–7.

---

## Triage — 2026-08-14

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*

- **Where it shows up:** a **new** reference screen inside the Mac app and inside the
  iPhone app, both *(internal — development builds only)*. **Nothing customer-facing
  changes in this item**, and that is the point: it supplies the shared look and the
  standard screen states every later item is built from, so those items stop inventing
  their own.
- **What users will see — per surface:**
  - Reference screen, Mac *(new)*: a six-section list — colour, type, icons, controls,
    the breaker, and the standard screen states — beside a panel that renders the chosen
    section, plus a light/dark/system switch so both appearances can be compared without
    changing the machine's setting.
  - Reference screen, iPhone *(new)*: the same six sections and the same switch, in the
    phone's own navigation.
  - The breaker section: a lever that can be flicked so the two speeds — fast and
    overshooting on the way up, slow and settling on the way down — can actually be
    watched, which has never been observed running.
- **Behaviour changes:**
  - Both apps follow the machine's light/dark setting, and the light appearance has been
    **designed** rather than derived by flipping the dark one.
  - The nine standard screen states arrive with real wording for the unhappy paths —
    including that "can't reach it" means *the router is not running*, and offers to
    start it.
  - Every colour and text size now comes from one named set, so a screen cannot quietly
    invent its own.
- **Design reference:** `design/mocks/light-appearance.html` is the canonical visual
  reference for the light appearance, the nine states and the reference screen's layout.
  `design/mocks/prototype.html` remains the dark reference and is unchanged.

**Assumptions**

- `[Layout]` Light is authored to reproduce dark's *measured* contrast, not its opacity numbers. *(copying opacity lands elsewhere)*
- `[Experience]` All four status colours are re-chosen for light rather than reused. *(reused, every one is unreadable)*
- `[Layout]` Amber moved toward yellow to separate it from red. *(21° apart defeats colour-blind readers; now 40°)*
- `[Layout]` Hovering darkens a resting surface in light, brightens it in dark. *(white is the ceiling)*
- `[Experience]` The one prominent button keeps a white label despite measuring below target in dark (rather than near-black). *(Apple's kit wins per the design authority)*
- `[Layout]` The breaker's body grows so its indicator lamp sits inside it (rather than overhanging). *(overhanging, it gets cut off)*
- `[Experience]` Reduced motion removes the lever's animation, never the state change. *(state must survive)*
- `[Data & scope]` The reference screen ships only in development builds. *(not customer-facing)*
- `[Operations]` Existing screens that misuse a status colour are reported, not changed here. *(other items own them)*
- `[Experience]` The gallery is a reference surface, not a playground; no editing. *(scope)*
- `[Layout]` The design authority gains one row per value, each carrying both appearances side by side. *(a combined row cannot be read back)*
- `[Data & scope]` The drift check is widened to compare **both** appearances, and is proven by breaking it. *(otherwise light drifts unwatched)*
- `[Layout]` Control sizes, selection radius, focus ring and breaker geometry become individually recorded values. *(today they are prose no check can read)*
- `[Experience]` The focus ring follows the keyboard section of the design authority, beyond the sections the brief cites. *(the brief stops one section short of it)*
- `[Data & scope]` The shared look lives in one place both apps draw from, kept apart from the part the router's tests import. *(a copy per app is two systems)*
- `[Operations]` A check fails the build when a screen writes a raw colour or text size instead of naming one. *(the drift check cannot see literals)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage F2` before the planner picks this up.*

---

### The nine states, with real copy

Required by the design authority: every spec written against it carries its own state matrix, with
real wording for the unhappy paths. Placeholder copy hides both layout and comprehension failures.
The servers board is the canonical surface; each state below ships as a reusable container, so a
later screen cannot go out populated-only by accident.

| State | What the person sees | Action offered |
|---|---|---|
| **Default** | The populated board — one row per declared server, its lever showing whether it is running. | — |
| **Empty** | "No servers declared yet" · "MCP Router reads the servers your agents already have configured. Point it at a config, or declare one by hand." | Add server… |
| **Loading** | Placeholder rows at the real row height and shape, so nothing jumps when the data lands. Never a spinner over a blank pane. | — |
| **Partial** | "6 of 8 servers loaded" · "Two entries name a transport this version does not read. The other six are live and usable." | Show the two |
| **Error** | "Could not read servers.json" · "The file is there but line 12 is not valid JSON, so nothing was loaded rather than some of it. Fix the line and it will reload on its own." | Reveal in Finder |
| **Success** | The change happens in place — the lever rises, the subtitle changes. No toast; macOS does not announce a click. | — |
| **Offline** | "The router is not running" · "Nothing is listening on 127.0.0.1. Your agents will fall back to spawning their own servers until it starts." | Start the router |
| **Disabled** | The action dims where it is, reason readable: "Available once the server has run at least once. It has not been called yet." | — (dimmed, never hidden) |
| **Overflow** | A long name truncates with the full value readable in the inspector. The row height never changes. | — |

Every control additionally carries resting, hover, keyboard-focused, pressed and disabled.

### Acceptance — what must be true

Checkable outcomes, not intentions. Each is a pass/fail a person or a gate can settle.

1. Both appearances are **authored**: every colour resolves to a different value in light than in
   dark, and changing any light value on its own turns the drift check red.
2. Every colour and text size named in the design authority exists in the product, and every one in
   the product traces back to the authority — in **both** appearances.
3. Each of the eight text roles renders at its stated size and line height; nothing renders off the
   ladder.
4. All 21 icons in the reference resolve to something drawn; a name with no drawing fails to build
   rather than rendering blank.
5. The five control sizes, the selection fill's radius and insets, and the focus ring's width all
   come from recorded values, each checked against the authority.
6. The breaker shows one dormant and three lit states; in **every** one its slot is at least as wide
   as its lever and strictly taller, so the recess stays visible. Breaking that turns a test red.
7. The lever rises fast with overshoot and falls slowly without it; with reduced motion on, the
   animation is gone and the state change still happens.
8. All nine states above render with the copy above, in both appearances.
9. The reference screen opens in both apps in a development build, and is absent from a release
   build.
10. A screen that writes a raw colour or text size instead of naming one fails the build.
11. The scaffolding shells no longer carry their own private colour bridge; both draw from the
    shared one.

### Cross-family review — 2026-08-14

`gpt-5.6-sol` at `max` effort, read-only, grounded in the repository *(wire-verified: `model:
gpt-5.6-sol`, `reasoning effort: max`)*. **Verdict: MATERIAL DEFECTS** — all five findings accepted
and resolved above before this spec was marked ready. Accepted 5 · rejected 0 · escalated 0.

- **High — adding light values would not actually have been checked.** The reader that compares the
  authority against the product takes one value per row and ignores any further column, and the name
  check compares names only. A light column would have sat silently unwatched, and a combined fills
  row would have parsed as one nonsense name. *Resolved:* one row per value carrying both
  appearances, the reader widened to both, proven by breaking it.
- **High — nowhere compliant to put the shared look.** Both apps link only the part the router's
  tests import, which must stay free of interface code; putting the shared views in each app instead
  would make two systems. *Resolved:* one shared place, separate from that part, that both apps draw
  from.
- **Medium — the geometry could not be built without hardcoding.** Control sizes, selection radius
  and focus ring are prose in the authority and are explicitly skipped by the check. *Resolved:*
  recorded individually. Also correctly caught that the focus ring lives one section past the range
  the brief cites.
- **Medium — the nine-state matrix was missing**, though the authority requires every spec to carry
  its own. *Resolved:* added above with real copy.
- **Medium — no acceptance criteria**, and the existing check cannot see a hardcoded value at all.
  *Resolved:* eleven checkable outcomes above, including a build failure on raw values.

## Plan — 2026-08-14

Implementation plan: `planning/plans/plan-F2.md` (Plan size: Large).

No scope narrowing: the plan carries every clause of the feature description and every triage
assumption. Its "Out of scope" entries are the two shared-surface changes triage already recorded as
report-only (the prototype's decorative use of indicator colours, and the pre-existing dark-appearance
shortfall of `--fail`/`--accent` as text on a raised surface), plus unrelated router work.


---

## Pause checkpoint — 2026-08-14

Written by the ORCHESTRATOR, not the runner: the runner died mid-turn on a gateway 503
(`no-eligible-account`, 9 of 11 accounts over reserve) and could not write its own.

**Pipeline position.** Phases 1-3 DONE (design representation, triage, plan — commit
`a723ee4`). Phase 4 DONE through checkpoint 1 (`aee928f`, `fb5215b`). Phase 5 gap-fix was
IN FLIGHT: the runner had just recorded two codex lane failures (deadline, then empty `-o`
file, both times) and, per protocol, was running the Phase D completeness critic as a
logged in-family downgrade when it died.

**State on disk.** Branch `ai/f2`, 3 commits, worktree CLEAN, `make test` exit 0 with
**65 tests**. Nothing is uncommitted.

**Diagnosed but unfixed.** Nothing outstanding was recorded. The last completed act was
"All four guards proven to fail and restored green", so the red-green pass on checkpoint
1 is done.

**Next three steps.**
1. Re-run the Phase D completeness critic. The codex lane failed TWICE at `max` on
   deadline/empty output — go straight to a single-question scoped call at `high`, or log
   the in-family downgrade, rather than burning a third turn on the same lane.
2. Finish the presentation layer the earlier agent had started: the `MCPRouterUI` target
   and its bindings.
3. Phase 6 acceptance evidence, then Phase 7 commit and STOP before merge.

**Gotchas.** The gateway pool is shared with another live fleet in `~/Dev/hopper`; a 503
here is capacity, not your code. `make acceptance` needs an Accessibility grant and fails
safe (exit 2) without one.

**Re-read before continuing** (paths only): `planning/features-to-triage/F2-design-system.md`,
`planning/specs/spec-F2.md`, `planning/plans/plan-F2.md`, `DESIGN.md`,
`planning/practices/SWIFT_PRACTICES.md`.

---

## Progress — 2026-08-14 (resumed after the gateway 503)

Picked up from the pause checkpoint above. Phases 1–4 were already on disk; this pass ran the
Phase D completeness critic, resolved what it found, and produced the acceptance evidence.

### Out-of-family completeness critic

`gpt-5.6-sol`, read-only, scoped to three questions over the delivered code and the two acceptance
lists. **Logged downgrade:** `max` effort had already failed twice on this item (deadline, then an
empty output file), so this ran at `high` with a narrowed scope rather than burning a third turn.
Wire-verified from the session log: `"model":"gpt-5.6-sol"`, `"reasoning_effort":"high"`.

**Verdict: MATERIAL DEFECTS — 17 findings. Accepted 13 · rejected 2 · folded 2.** Each was checked
against the source before being accepted; the two rejections are recorded with their reasons rather
than quietly dropped.

| # | Finding | Outcome |
|---|---|---|
| 1 | "Every breaker dimension is parity-checked" had no check — only invariants | Accepted. `### Breaker geometry` table (19 rows) + `breakerRows` parser + set-and-value parity. |
| 2 | Nothing stopped a shell regrowing a private colour bridge | Accepted. Lint rule over both shells. |
| 3 | "Light reproduces dark's measured contrast" was never computed | Accepted. WCAG luminance + compositing; every documented ratio recomputed from the shipped value. |
| 4 | "`MCPRouterKit` imports no UI framework" was unenforced | Accepted. Lint rule. |
| 5 | `lightIsAuthored` exempted `.raised`, which never needed it | Accepted. Exemption narrowed to `.onAccent`. |
| 6 | Nothing asserted `--onAccent` is white in *both* appearances | Accepted. Positive assertion + the dark 3.23:1 deviation pinned. |
| 7 | Hover polarity used the red byte as a luminance proxy | Accepted. Real relative luminance. |
| 8 | Lint missed `Color.white`, `.foregroundStyle(.red)`, `Font.custom(size:)`, `.font(.title)` | Accepted. Four new patterns. |
| 9 | The authored icon was skipped by the drawing check | Accepted. `ConduitMark` path asserted non-empty and full-frame. |
| 10 | Reduce Motion was untestable inside the view | Accepted. Extracted to `spring(raised:reduceMotion:)`, a pure function, and tested. |
| 11 | Empty/partial/error copy was length-checked, not verbatim | Accepted. Asserted exactly. |
| 12 | The Debug-only gallery claim was proven for macOS only | Accepted. iOS bundle sweep added. |
| 13 | `SurfaceState` had no exhaustive switch; gallery listed states by hand | Accepted. `StateContainer` switches over all nine; the gallery drives off `allCases`. |
| 14 | Gallery sections had no per-section identifiers | Accepted. Derived per case. |
| 15 | Control geometry "not proven to come from tokens" | **Rejected.** `selectionFill`, `focusRing` and `ControlScale.height` all read `MetricToken` today; the finding describes a hypothetical future hardcode, and the lint that would catch it cannot tell a design radius from a 1pt hairline. |
| 16 | Breaker invariants checked only `.standard`, not "every state" | **Rejected.** Slot and toggle dimensions are state-independent by construction; only the offset varies, and `recessVisibleThroughout` already checks both ends of the travel. |

### Red-green proof

Every new guard was seen to fail before it was trusted. 13 of 13 proven — each broken, observed red,
restored, observed green.

Swift: documented light contrast ratio · breaker housing height · reduce-motion suppression ·
`onAccent` light value · `ConduitMark` path · empty-state title · section-identifier uniqueness.
Lint: named SwiftUI colour · shorthand system colour · system text style · `Font.custom` size ·
`MCPRouterKit` UI import · shell colour bridge.

### Three harness defects found while producing the evidence

All three made the gate lie, and none would have been visible from a passing run.

1. **The pixel gate was photographing the desktop.** `screencapture -R <rect>` captures a screen
   *region*, so it returned whatever was on top at those coordinates — a run reported the background
   as `#292C33`, which is the terminal's colour; the saved capture contained a terminal and a
   keychain dialog and no part of the app. Every accessibility assertion passed in the same run,
   because the AX tree does not care what is on top. Now captured by window id (`-l`), which reads
   the window's own backing store. No region fallback: a fallback restores the failure silently.
2. **`bundle_contains` was a coin flip.** `strings … | grep -q` under `pipefail` returns 141 when
   `grep -q` exits at the first match and `strings` writes into the closed pipe — so a *successful*
   match intermittently read as failure. Three identical runs against one unchanged bundle gave two
   passes and one failure. The dangerous half is the Release assertion, which is `if
   bundle_contains …; then fail`: a suppressed match there is a silent pass, so the check that the
   gallery is not shipping could never have caught it shipping. Now a direct binary `grep -qaF`.
3. **The iOS assertion measured the simulator's setting, not the app.** It asserted the dark ground
   unconditionally, which was correct only while every surface took the dark value regardless of the
   device. With dynamic colours it failed reporting `#ECECEE` — the light ground rendering correctly
   on a simulator in light mode. Now it forces each appearance in turn, which is strictly better
   evidence: the phone is asked for dark and answers dark, asked for light and answers light.

### One product change fell out of the evidence

The gallery window titled itself after the selected section, so the Window menu offered "Design
system" and opened a window called "Colour" — a window you cannot find again in the menu that opened
it. The title is now stable and the section rides in `navigationSubtitle`, which is where macOS puts
that context anyway.

### Gate evidence

- `make all` — lint 0 violations in 26 files, `no-raw-design-values: clean`, both platforms build,
  **75 tests in 14 suites** (was 65 at the pause).
- `make acceptance` — 11 assertions, exit 0, **six consecutive runs** confirming the flake is gone:
  macOS renders `#1E1E1E`; the gallery's light appearance renders `#ECECEE`; iOS renders `#1E1E1E`
  in dark and `#ECECEE` in light; the gallery is in both Debug bundles and absent from Release.

Stopped before merge, per the fleet protocol.
