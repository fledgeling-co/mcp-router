# F1: Swift workspace, shared kit, and the three targets

**ID:** F1
**Status:** In Review — built, gated and accepted on `ai/f1`; held before merge for the orchestrator to serialise finalisation
**Created:** 2026-08-13
**Last updated:** 2026-08-14

## Feature description

*Verbatim from `planning/features-to-triage/F1-swift-workspace.md`.*

> # F1 — Swift workspace, shared kit, and the three targets
>
> **Depends on:** nothing. Everything else depends on this.
>
> Replace the single hand-rolled `app/MCPRouter.xcodeproj` with an XcodeGen-driven
> workspace carrying three targets and one shared library:
>
> - `MCPRouterKit` — models, control-API client, design tokens, formatting. Shared by
>   both apps and by the Swift router's tests.
> - `MCPRouter` (macOS 15+) — the app. **Direct distribution**: Developer ID, hardened
>   runtime, notarized DMG, **no App Sandbox** (it spawns arbitrary MCP subprocesses and
>   rewrites `~/.claude.json`, both of which the sandbox forbids). Entitlements must be
>   written for this, not retrofitted.
> - `MCPRouter iOS` (iOS 18+) — the companion. App Store/TestFlight, sandboxed, no
>   entitlement it does not use.
>
> Also owed: `.swiftformat` + `.swiftlint.yml`, a `Makefile`/`just` entry for
> `generate → build → test`, a CI workflow that builds both targets and runs tests on
> macOS runners, and `planning/practices/SWIFT_PRACTICES.md` — the two inherited practices
> docs are TypeScript/Next.js and carry no Swift guidance at all, which is a real gap for
> every runner after this one.
>
> The existing 12 Swift files in `app/Sources/` are a partial scaffold from an earlier
> session; treat them as a starting point to fold in, not as authority.

---

## Acceptance criteria

The oracle for every later stage. Each clause is independently verifiable; evidence must be
a measurement, an exercised command, or a red-green test — never "it looks right".

| # | Clause | Evidence type |
|---|---|---|
| A1 | `xcodegen generate` produces the project from `project.yml` with no hand-edited project file tracked in git | exercised command + `git ls-files` |
| A2 | The macOS app target builds clean from a cold `DerivedData` | exercised build |
| A3 | The iOS app target builds clean for the simulator | exercised build |
| A4 | `MCPRouterKit` builds and its tests pass via SwiftPM, with no Xcode dependency | exercised `swift test` |
| A5 | Both app targets link `MCPRouterKit` and use a symbol from it — the sharing is proven, not declared | build + a test asserting the symbol resolves in each target |
| A6a | The macOS target declares App Sandbox **off** — read from the entitlements file itself | file assertion |
| A6b | The macOS target sets hardened runtime **on** — read from the *generated build settings*, which is where it lives (it is not an entitlement) | `xcodebuild -showBuildSettings` assertion |
| A7 | The iOS target declares no entitlement it does not use | file assertion |
| A8 | The kit exposes **one enumerable token registry**, and a test compares its key set against the tokens named in `DESIGN.md` §2 **in both directions** — a token in the doc with no constant, or a constant with no doc entry, fails | red-green test |
| A9 | For every key present in both, the test compares **normalised typed values** (hex case-folded, opacity parsed to a number, sizes to a number), so prose/whitespace/typography edits to `DESIGN.md` cannot cause a false failure while a real value change always does | red-green test, incl. a deliberate drift proving it fails |
| A10 | `swiftformat --lint` and `swiftlint` both run clean over the Swift tree | exercised command |
| A11 | One `make` entry point runs generate → build → test and exits non-zero on any failure | exercised command incl. a deliberate failure |
| A12 | A CI workflow builds both app targets and runs the kit tests on a macOS runner | workflow file + local equivalence run |
| A13 | `planning/practices/SWIFT_PRACTICES.md` exists and is binding-quality: agent protocol, rule sections, self-review checklist | file review |
| A14 | The router's Swift MCP SDK is **not** added in F1; when any Swift package pin is added it is an exact version, never a range | dependency assertion |
| A15 | Both app shells launch and render — not merely compile | screenshot of each running app |
| A16 | No type the kit exposes for a control-API PATCH carries a `command`, `args` or `env` field — the control API cannot be made to rewrite a command line | type-level assertion + test |
| A17 | Both targets' bundle identifiers are asserted from the generated build settings, not assumed | `xcodebuild -showBuildSettings` assertion |
| A18 | Both targets' deployment targets (macOS 15.0, iOS 18.0) are asserted from the generated build settings | `xcodebuild -showBuildSettings` assertion |
| A19 | A Release configuration exists carrying the Developer ID posture, and an **unsigned** build still succeeds — signing is configured, not required, so no runner is blocked on credentials that do not exist yet | exercised build of both configurations |

**Explicitly out of scope for F1** — archive, code-signing with a real identity, notarization, and DMG
packaging. The brief names them as the macOS distribution posture, and F1 wires the posture (A6a,
A6b, A19); it cannot *exercise* it, because the developer account and signing identity are an open
question at the fleet level. Producing and notarizing a signed artifact is a separate later item and
is reported as a deferred child rather than silently dropped.

---

## Triage — 2026-08-13

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** **nothing customer-facing changes.** This is foundation work — the
  scaffolding both apps are later built on. Two throwaway launch screens appear *(internal —
  new, and deliberately temporary)*, one per device, and both are replaced wholesale by the
  later shell items.
- **What users will see — per surface:**
  - Mac launch screen (new, temporary): the app name, its version, and one sentence saying the
    real surfaces arrive with the shell item. Dark graphite ground, the house type scale.
  - iPhone launch screen (new, temporary): the same, sized for the phone.
  - Nothing else. No server list, no activity, no settings — those are later items.
- **Behaviour changes:** none. Nothing the router does changes; the existing installed setup is
  untouched.
- **Design reference:** the house design document is authoritative for the two launch screens'
  colour and type. The interactive prototype is not a reference here — it carries no surface
  this item builds.

**Assumptions**
- `[Data & scope]` The shared kit carries token *values*; the visual component layer belongs to the design-system item. *(brief splits them; avoids two owners for one surface.)*
- `[Data & scope]` The connection seam, stated precisely because the brief and the later client item both lay claim to it: this item owns the **wire data shapes, the error cases, and the connection contract**; the later client item owns **transport, sign-in, live updates, and the callable operations**. *(the brief's "client" wording overlapped the later item; this split gives every surface exactly one owner.)*
- `[Data & scope]` Bundle identifiers `app.fledgeling.mcprouter` and `app.fledgeling.mcprouter.ios`, spelled out rather than implied. *(recorded as the standing assumption; supersedes the older scaffold's.)*
- `[Data & scope]` Lowest supported versions: current-1 on Mac, current-1 on phone. *(stated in the description.)*
- `[Operations]` Builds are unsigned locally and in automation; the release posture is *configured* but not exercised. *(account details not yet supplied; blocks release only, not the build.)*
- `[Operations]` Packaging a signed, notarized installer is a separate later item, not this one. *(cannot be exercised without credentials that do not exist; reported as a follow-on rather than dropped.)*
- `[Operations]` The older per-project signing settings are removed from the shared layer. *(they force a signing identity that no runner has, and would fail every build.)*
- `[Operations]` The generated project file is no longer tracked. *(the whole point of generating it; ends merge conflicts between parallel runners.)*
- `[Operations]` Automation runs on hosted Mac machines. *(no self-hosted runner exists.)*
- `[Experience]` The two launch screens state plainly that they are temporary rather than showing invented data. *(house rule: never display a number the product does not observe.)*
- `[Experience]` The earlier session's visual theme file is discarded, not folded in. *(it contradicts the house design document on both colour and type.)*
- `[Experience]` Its small text-formatting helpers *are* folded in. *(they match the house document and are already proven.)*
- `[Operations]` A plain build file rather than the newer task runner. *(the task runner is not installed on this machine; the plain one always is.)*
- `[Operations]` No external protocol library is added by this item. *(the router item owns that choice and its exact pinning.)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage F1` before the planner picks this up.*

**Codex cross-family spec review — 2026-08-13**

Reviewer: `gpt-5.6-sol`, read-only, wire-verified. **Verdict: MATERIAL DEFECTS — all findings
resolved below; status flipped only after resolution.**

*Lane note, recorded rather than hidden:* the first two attempts at `max` effort produced **no
output** despite exit 0 and a correct wire header — a stale `~/.codex/models_cache.json` missing
`base_instructions` (cleared; the CLI rewrites a cache it cannot re-read, so the errors recur), then
turn-budget exhaustion across eight files. Per the effort ladder the gate was re-run **once at
`high` with narrowed scope**, which returned in 90s. This is a **logged downgrade**: the review that
landed is `high`, not the `max` the gate specifies, over 2 files rather than 8.

| # | Finding | Disposition |
|---|---|---|
| Q1 | The connection surface has **two owners** — the brief assigns "control-API client" here while the assumptions assign the full client to the later item, and A16 requires PATCH types here | **Accepted** — seam restated above as wire shapes + errors + contract here, transport/auth/operations there |
| Q2 | Bundle id conflicts with the existing scaffold; `CODE_SIGN_STYLE: Manual` + `DEVELOPMENT_TEAM` conflict with unsigned builds; sandbox/hardened runtime agree | **Accepted** — this item wins on both; signing settings move out of the shared layer into a Release configuration (A19); iOS id spelled out |
| Q3 | A8/A9 brittle — parsing free-form markdown fails on harmless edits, and arbitrary constants are not enumerable so completeness drifts silently | **Accepted in substance** — rewritten as an enumerable registry with a **bidirectional** key-set comparison and normalised typed values (A8, A9). **Partially rejected:** its proposed fix of adding a machine-readable block to the design document is a **shared-surface change** this item may not make; it is reported to the orchestrator instead |
| H1 | Developer ID / notarized installer promised, but no criterion verifies archive, signing or notarization | **Accepted** — explicitly scoped out, posture-only criteria kept (A19), packaging reported as a deferred child |
| H2 | A6 conflated hardened runtime with an entitlement, and `codesign` evidence is unobtainable from an unsigned build | **Accepted** — split into A6a (sandbox, from entitlements) and A6b (hardened runtime, from build settings); the signed-artifact check moved to the packaging item |
| H3 | Bundle identifiers and deployment targets are foundational but never asserted | **Accepted** — added as A17 and A18, asserted from generated build settings |

Accepted 6 · partially rejected 1 (the shared-surface half of Q3) · rejected 0 · escalated 0.

---

## Plan — 2026-08-13

Implementation plan: `planning/plans/plan-F1.md` (Plan size: Large).

Its cross-family review returned **MATERIAL DEFECTS** on the first draft — 18 findings, all
accepted and resolved. Two of them changed clauses in the table above rather than only the plan,
and are recorded here so the acceptance table and the plan cannot drift:

- **A16's evidence type changed** from a reflection check to an **encoded-JSON key-set assertion**.
  `Mirror` sees only stored-property labels, so it would miss a computed property or a `CodingKeys`
  mapping that still puts `command`/`args`/`env` on the wire.
- **A5's evidence type changed** from a per-target test bundle to **a screenshot showing a
  kit-sourced value on screen**. The intent is unchanged — the sharing must be proven, not declared
  — and a rendered token value proves the symbol resolved in that target without adding two UI-test
  bundles this item has no other use for.

**Scope-narrowing check:** the plan excludes archive, code-signing, notarization and DMG packaging.
Triage recorded this as a deliberate exclusion with its reason (no signing identity exists yet), and
criteria A6a/A6b/A19 keep the *posture* in scope, so this is a disclosed exclusion rather than a
quiet descope. A packaging follow-on is reported to the orchestrator.

---

## Gap-fix — 2026-08-14

Closes the findings from the Phase D out-of-family completeness critic (`gpt-5.6-sol`, `max`
effort, read-only, wire-verified — `/tmp/gate-F1-critic.md`), whose verdict on the first
implementation was **MATERIAL DEFECTS**. Every finding below is resolved in code on `ai/f1`, with
the evidence that was actually run.

The critic's central objection is worth stating plainly, because it shaped all four code fixes: a
guard that has never been *seen* to fail is not evidence that it works. Four of its five HIGH
findings were checks that passed for the wrong reason — they could not fail even when the thing
they protected was broken.

| # | Finding (severity) | Resolution | Evidence |
|---|---|---|---|
| Q1/Q2 | Metric parity was not bidirectional (HIGH) — an unmatched documented row hit `guard let token = … else { continue }`, so a metric in `DESIGN.md` with no `MetricToken` passed silently | Exact name-set comparison in both directions, `Issue.record` on an unmatched row, and a test asserting an excluded row must not *also* carry a token — exclusion cannot be used to skip a value check | **Red-green:** inserted the critic's own bypass row `\| Inspector width \| 320pt \|` into `DESIGN.md` §2 → **2 tests failed** (`documented metrics with no MetricToken: ["Inspector width"]`); row removed → 31 green. `DESIGN.md` restored, `git diff` clean |
| Q1 | `canonicalHex` split on whitespace (MEDIUM) — `` `#FFF`@7.5% `` failed the hex check and threw, so a re-spacing edit that changed no value turned the suite red | Hex and opacity extracted independently, by syntax rather than by token position | New test asserts four spacings of the same pair — `` `#FFF` @7.5% ``, `` `#FFF`@7.5% ``, `` `#FFF`  @ 7.5% ``, `#fff @7.5%` — all yield `#FFFFFF` / `0.075`, and that a cell with no alpha is opaque rather than zero |
| Q1 | `ServerPatch` did not match the router (HIGH) — it carried `acceptPendingChange`, which `PATCH /servers/:name` silently ignores | Shape corrected to the four fields the router actually reads; approval modelled as its own `ControlAPIClient` operation, mirroring the separate `POST /servers/:name/approve` | Verified against the handler itself: `src/control.ts:375` reads `projects`, `warm`, `idleMs`, `placard`; `src/control.ts:347` is the separate approve route. Test asserts the encoded key set **equals** `permittedWireKeys` |
| Q4 | The command-line guarantee was weaker than claimed (HIGH) — a `public var command: String?` left nil is omitted by the synthesised encoder and sails past a JSON-only assertion; a caller's `keyEncodingStrategy` could rename a field onto a forbidden key | Three independent checks: encoded JSON, **stored properties** via `Mirror` (sees a nil field the encoder omits), and `ServerPatch.encodedBody()` — the one sanctioned serialisation path, which fixes the encoder configuration rather than accepting one and validates the key set of the bytes it returns | `encodedBody()` throws `ControlWireError.forbiddenKeys` / `.unpermittedKeys`; a test proves the comparison rejects a body that *does* carry `command`, so the allowlist is exercised rather than merely never handed anything bad |
| Q3 | The zero-test guard had four holes (MEDIUM) — `\|\| true` defeated `pipefail`, `2>/dev/null` made a compile failure read as an empty suite, and it counted *discovered* rather than *executed* tests | Listing status checked on its own with diagnostics kept; the gating count now read from the xUnit report `swift test` writes | **Red-green ×2.** Compile break → `error: could not enumerate tests — this is a build or toolchain failure, not an empty suite` plus the real diagnostic (previously: a misleading "zero tests discovered"). One suite disabled → `discovered 31` / `executed 25`, proving the two counts are independent |
| Q5 | `spec-F1.md` and `plan-F1.md` were never on the branch (HIGH) — the audit ran with no versioned acceptance criteria | Both committed to `planning/` on `ai/f1` | This file and `planning/plans/plan-F1.md` are tracked on the branch |
| Q5 | CI configured but never executed (HIGH) | **Not fixed, and not claimed.** The workflow is delivered; it has never run, because this runner is forbidden to push and the orchestrator serialises finalisation | Recorded as an explicitly unproven claim below rather than asserted green |
| Q5 | Release artifacts deferred (MEDIUM) | The formal deferral is now the committed record (the scope-narrowing note above), not an untracked claim | Packaging reported as a deferred child |
| Q5 | "Workspace" vs project (LOW) | **Wording amended to match the artifact.** XcodeGen 2.45.4 emits a `.xcodeproj` only; a standalone `.xcworkspace` would have to be hand-authored and tracked, which contradicts A1's "no hand-edited project file tracked in git". The shared library is a local SwiftPM package the generated project references directly, which is what a workspace would have been for | `xcodegen --version` → 2.45.4; `app/project.yml` declares the local package; both app targets link `MCPRouterKit` |

### Second out-of-family review round — 2026-08-14

The fixes above were sent back to the same out-of-family reviewer. It returned **MATERIAL
DEFECTS** a second time, with two findings that were both real. They are recorded here because a
gate that only ever confirms the author is not a gate.

*Lane accounting, stated rather than hidden.* Two `max`-effort attempts produced **no output**: the
run exhausted its turn budget inside the 600s bound (the first spent it dispatching its own
verifier subagents). Per the effort ladder the gate was re-run **once at `high` with a
single-question scope over three files**, which returned in ~90s — the same downgrade, for the same
reason, that the triage gate recorded. **This round's verdict is `high`, not `max`.** Both findings
below were independently reproduced locally before being fixed, so the evidence does not rest on
the reviewer's word.

| # | Finding | Assessment | Resolution + evidence |
|---|---|---|---|
| a | `encodedBody()` validates `data` and then returns it, but the only test of it passed `warm: true`. A bypass conditioned on a value the test never supplies — `if warm == false { return … }` — puts `command` on the wire with the suite green | **Real, as a coverage defect.** The proposed edit is sabotage-level, but the coverage gap it exploits is genuine: one input does not exercise a function's input space | The test now pushes **seven** representative shapes through `encodedBody()` — empty, each field alone, both `warm` values, fully populated. **Red-green:** injecting the reviewer's exact edit fails two shapes, naming the key (`encodedBody put a forbidden key on the wire … ["command", "warm"]`); removed → 31 green |
| b | The discovery count matched only lines ending in `()`, the Swift Testing spelling. A healthy XCTest-style listing (`Suite/testName`) counts zero, so the gate **fails a suite that is fine** | **Real.** This is the false-failure direction of the same brittleness the first round flagged, which the first fix did not address | Discovery now counts non-blank listing lines; the shape of a line was never the signal. **Red-green:** XCTest-style listing counts 2 under the new rule and **0** under the old one; an empty listing still counts 0 and still fails |

Accepted 2 · rejected 0. One correction carried back into the record above: the first round's
executed-count fix read `tests="N"` and ignored `skipped="N"`, so a suite that skipped every test
would have reported them as executed. The real report does carry `skipped`, and the count now
subtracts it — verified on a synthetic report where `tests=2 skipped=2` yields `executed=0`, and on
multi-suite input where `(5-2)+(4-1)` yields 6.

**What is still not proven, stated plainly:** nothing expressible in Swift stops a future edit from
adding an early `return` above the validation in `encodedBody()`. The tests remove the cheap
version of that mistake — a bypass hiding in an untested input — and no more than that. The
server-side rule is the durable one, and it belongs to the router item: the control API should
reject unknown keys rather than silently ignore them.

### Unproven claims — stated rather than dressed up

- **A12 (CI) is configured, not demonstrated.** `.github/workflows/swift.yml` calls the same
  Makefile targets a local run does, so the commands cannot drift — but no workflow run exists,
  because the branch is unpushed by instruction. Whoever finalises F1 should require one green run
  before treating A12 as met.
- **A2, A3, A15** are execution attestations. The tree is consistent with them and they were
  re-run during gap-fix, but a repository cannot itself preserve a screenshot's provenance.

### Deferred children discovered
Reported to the orchestrator rather than registered here (the ledger has a single writer):

1. **Signed, notarized macOS packaging** — archive → Developer ID sign → notarize → staple → DMG,
   plus iOS distribution validation. Depends on F1 and on a developer account and signing identity
   that do not yet exist. This is the blocker's actual shape: not work that was skipped, but work
   that cannot be exercised until a credential exists.
2. **A machine-readable token block in `DESIGN.md`** — the critic's proposed fix for parsing
   free-form markdown. It is a shared-surface change this item may not make, so it is reported.
   The parser is hardened instead, which is the part that was in scope.

---

## Acceptance — 2026-08-14

Native lane, not web: there is no web surface, no Playwright harness and nothing to serve. The
acceptance question for F1 is narrow and specific — *did the shared library reach the screen* — and
it is the one question a build gate structurally cannot answer.

**What was added:** `scripts/acceptance/shells.sh`, wired as `make acceptance` and invoked as a CI
step. It launches both shells and asserts each renders a value that came from `MCPRouterKit`. This
replaces the hand-run screenshot that previously stood behind A5 and A15.

**Two oracles, because neither is sufficient alone.** The rendered pixel is sampled and compared to
`ColorToken.ground`, read out of the source rather than pinned as a copy, so the gate follows the
token. The accessibility tree is walked for the on-screen strings. Only the first proves anything
*drew* — Apple states the accessibility tree is not necessarily one-to-one with what a sighted user
sees, so a green AX walk over a window that painted nothing is possible, and dropping the pixel
assertion would leave this asserting much less than it appears to.

**Run record.** Green twice directly and twice through `make acceptance`; the whole `make all` gate
green alongside it (0 lint violations across 12 files, BUILD SUCCEEDED for both targets, 31 tests
executed).

**Red-green, because a gate that cannot fail is decoration.** `ColorToken.ground` was changed
`#1E1E1E` → `#1E1E1F` — one digit — without rebuilding, reproducing the real drift case where the
token moves and the screen does not. The gate failed: `macOS background rendered #1E1E1E, expected
ColorToken.ground #1E1E1F`, exit 1. Restored → green.

### Clause evidence after acceptance

| Clause | Evidence | Re-runnable? |
|---|---|---|
| A1, A10, A11, A14 | `make all`, `make test`'s own guards, `swift package show-dependencies` | Yes — `make all` |
| A2, A3, A19 | `make build-mac` / `build-ios` / `build-mac-release` | Yes — `make all` (A19 via its own target) |
| A4, A8, A9, A16 | 31 tests in 4 suites, including the parity and control-contract suites | Yes — `make test` |
| **A5, A15** | **Both shells launched; rendered background sampled = `#1E1E1E` = `ColorToken.ground`; AX tree carries the on-screen strings** | **Yes — `make acceptance` (was hand-run before)** |
| A6a, A6b, A7, A17, A18 | Entitlement files and `xcodebuild -showBuildSettings` | Hand-run — asserted by reading generated settings, not yet a script |
| A12 | Workflow file calls the same Makefile targets | **No — never executed; the branch is unpushed** |
| A13 | `planning/practices/SWIFT_PRACTICES.md` | File review |

### Sweeps — ran, or skipped with the reason

Scaled to the feature, as the method requires. F1 is two deliberately temporary launch screens with
no data, no network calls, no interaction, no roles and no realtime, so most sweeps have nothing to
act on. Recording that is the point; a sweep silently skipped reads as a sweep passed.

| Sweep | Outcome |
|---|---|
| 6a State matrix | **Skipped** — the shells have exactly one state. There is no empty, loading, error or partial to force, because nothing is fetched. The nine-state matrix belongs to the surfaces built on this one |
| 6b Fault injection | **Skipped** — no network call, no I/O, nothing to fail. The shells read a constant |
| 6c Interaction integrity | **Skipped** — zero interactive elements. The AX walk confirms this rather than assuming it: the tree carries static text and no controls |
| 6d Keyboard + a11y floor | **Partial.** The AX walk establishes the strings are exposed to assistive technology. A contrast/Dynamic Type audit needs `performAccessibilityAudit()`, which needs an XCUITest target this item does not add — named as a gap, not swept under |
| 6e Data-shape stress | **Ran, at the library layer** — the parser suite covers shorthand/full hex, four spacings of a colour+alpha pair, prose-valued cells, separator and header rows, and a missing document. The shells render no data |
| 6f Security surface | **Ran, at the contract layer** — the control-API PATCH shape cannot carry `command`, `args` or `env`, asserted three ways with the bypass exercised. There is no running surface to probe yet |
| 6g Multi-user / realtime | **Skipped** — no accounts, no sharing, no realtime channel in this item |

**Rendered-quality review: deliberately not run, and named rather than skipped silently.** The two
screens are scaffolding that the shell items replace wholesale, and their conformance to the design
document is already machine-checked in both directions by the token parity suite. A judged visual
review belongs to the first item that ships a real surface. That is a scope call, not a clean bill
of visual health.

**Axes held constant, so the run record does not imply breadth it lacks:** one appearance (dark —
the product has no light appearance yet), one macOS window size, one simulator device, one
appearance-independent colour sample per shell. Dynamic Type was not varied.
