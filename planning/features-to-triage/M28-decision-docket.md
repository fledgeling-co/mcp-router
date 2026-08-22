# M28 — five findings that need a decision rather than a runner

**Category:** owner · **Found:** 2026-08-20 and 2026-08-21, by the test campaign
**Defects:** DEF-042, DEF-049, DEF-008, DEF-057, DEF-033

Each of these is measured, reproducible where reproduction applies, and recorded in
`planning/test-campaign/inventory.json`. None is waiting on investigation. They are here
because the next move is a choice about what this product should be or what it should
promise, and a runner making that choice would be the campaign marking its own homework.

A ship-feature runner should not pick this item up. It closes by the owner answering, after
which each answer becomes ordinary work with an obvious shape.

## 1 · DEF-042 — the design of record draws a feature the product deliberately does not have

Four boards diverge from `design/mocks/prototype.html` in one direction and for one reason.
Skills: the design has `runs`, `last run` and `eval` columns with graded pills; the build
drops all three and prints that a skill is loaded into an agent's context by the client and
never reaches the router, so the router does not see it run. Discover: the design has
install velocity and eval pills; the build prints that measuring a trend needs a history of
these indexes over time, which the router does not keep. Checks and Servers diverge the same
way.

**The build is the correct half.** ORCHESTRATOR.md requires that no number is displayed that
the router does not observe, and every one of these numbers is one it cannot.

**The decision:** re-cut the mock to match what the product honestly shows, or annotate
`prototype.html` as superseded on those four boards and keep it as a historical artifact.
Until one or the other, every design differential re-reports the same four divergences as
new, and SURF-006 and SURF-011 stay `fail` in the campaign against a reference that is
wrong.

## 2 · DEF-049 — `MCPRouterCLI index` exits 0 over a manifest write that did not land

Found by a denial control rather than by reading code. Pointed at a router home with mode
`dr-x------`, `index --force` prints `ok    witness-fixture (1 tools)`, prints
`0 tools cached -> …/manifest.json` eight lines later, exits 0, and the manifest does not
exist. Cause: `ManifestIndexer.record` at `RouterCore/Service/ServicePorts.swift:341` calls
`try? ManifestIO.save(...)`, the third of three call sites that discard the error.

Characterised rather than corrected, deliberately: propagating the error changes the CLI's
exit-code contract, and this project has already taken the opposite decision once on a
sibling path (`AuthRoutes.approve` answers 200 whether or not the bytes landed, pinned in
`ControlApproveDispatchTests.swift:114-118`).

**The decision:** does a failed manifest write become a non-zero exit and a propagated
error, or does the CLI keep answering 0 and instead stop printing `ok` for a server whose
manifest did not land? The second is smaller and fixes the self-contradicting output without
touching the contract. Either way the two counts in one output should not disagree
silently.

### The same swallowed error, one layer up, is user-visible

`AuthRoutes.swift:120` is the third call site and it is worse than the CLI one, because its
failure path produces a *more* optimistic answer rather than a silent one. Traced in the
source rather than inferred:

`AuthStamp.isAfter(left, right)` is `left > right` (`AuthStamp.swift:19-22`). `Describe.swift:216-218`
suppresses a recorded refusal — `return nil` — when `authorizedAt > builtAt`. The approve route
sets `builtAt` to now in memory at `AuthRoutes.swift:113`, then discards the write at line 120.
A failed save leaves the **older** `builtAt` on disk, so `authorizedAt` is after it, the guard
fires, and the refusal disappears. `authorized` is `hasTokens(name) && rejection == nil`
(`Describe.swift:222-225`), and `hasTokens` reads FileAuthStore, which the failed manifest write
never touches — so the route answers `authorized: true` over a manifest that was never written.

That is the same shape as the `index --force` false green above, one layer up and in front of a
person rather than in a CLI's exit code. It argues for the smaller fix on both: stop reporting
success for a write that did not land, rather than changing what the process returns.

**Unverified lead, recorded as a lead.** The approve path sets tools, digest and `builtAt` and
removes `pending` (`AuthRoutes.swift:108-114`); it never removes `error`. If that is right, a
*successful* approve leaves `builtAt` at approximately `authorizedAt`, `isAfter` is false, and a
recorded refusal stays on screen after an authorization that worked. Not measured — no test was
run against it, and it is a third defect if real, separate from either half of DEF-049.

## 3 · DEF-008 — a SwiftUI tab item's accessibility identifier cannot be set

Measured on glass in both places SwiftUI offers the modifier — inside the `.tabItem`
closure and on the view carrying it — and both **clear** the tab button's identifier rather
than set it: the five buttons came back `["", "", "", "", ""]` against a design of
`tab-discover` and siblings, where without the modifier they report the SF Symbol's name.
`.accessibilityHidden(true)` on the icon was tried first and measured inert. The finding is
recorded at `PhoneShell.swift:121-129` so nobody spends the same two runs again.

What ships today: the identifier is the glyph's, the label is the destination's, and
`MCPRouterIOSUITests` queries the tab bar by label, which works.

**The decision:** accept it as a characterised platform limitation and close the defect, or
spend a runner on the one untried route — reaching `UITabBarItem.accessibilityIdentifier`
through UIKit introspection. The cost is fighting the framework for an identifier that
nothing currently needs, since the label-based query already passes. The recommendation is
to accept and close; it is here because closing a defect on "we chose not to" is the
owner's call.

## 4 · DEF-057 — the vendored skills submodule is four minor versions behind what ran

`.gitmodules` vendors `.claude/plugins/fledgeling-plugins` at `main`, and the LEDGER's
allocation notes give the reason: a runner reads the pipeline's skills at a repo-relative
path rather than depending on the machine. For `test-campaign` that is not what happened.
The submodule carries 0.5.0 — five scripts, no `vacuity-check.py`, no `capture-lineage.py`,
no `effect-witness`, no `blindVocabulary`. Every gate this campaign reports ran from 0.9.2
in the machine's plugin cache.

A fresh clone following the documented `git submodule update --init --recursive` gets 0.5.0
and reproduces none of this campaign's numbers. It is also why X7 and X8 cannot be closed
from this repository.

**The decision:** bump the submodule to the version the campaign actually runs and make the
gates read from it, or drop the claim from the LEDGER and record that test-campaign is a
machine dependency. The first costs a bump and a re-run; the second costs reproducibility.

## 5 · DEF-033 — a parity failure that happened once and has not reproduced

The OAuth parity lane failed once inside a full gate and never again. The diagnosis is on
disk: the harness discarded the diagnostic its own script had printed, and the instrument
was repaired 1m58s later in the same commit — so the evidence that would have explained it
was destroyed by the bug that was being fixed. A stale-lock lead was investigated and ruled
out.

No decision is needed and no work is proposed. It is listed so that its openness reads as
deliberate rather than forgotten: it stays open and unexplained on purpose, because closing
an unreproduced failure is a claim nobody can support.

## What closing this item looks like

An answer to 1, 2, 3 and 4. Each answer then becomes a small ordinary change with a clear
shape, filed at that point. 5 needs nothing.

---

## Re-measured 2026-08-22 — three of the five no longer need an answer

The docket was written 20–21 August. The design of record moved on the 22nd and two of its
questions moved with it. Each finding below is measured, and the command is given so it can be
re-run rather than believed.

### 1 · DEF-042 is resolved, and by neither of the two options offered

The docket asked to re-cut the mock or shelve `prototype.html` as a historical artifact. The
owner settled the design of record on 2026-08-22 as `design/mcp-router-console.html`, which
supersedes the prototype — and **the console mock had already answered the substance, by a third
route the docket did not consider: it re-sourced the numbers rather than deleting or keeping
them.**

Counted with `grep -ioc <term> <file>`, console against prototype:

| Term | console | prototype |
|---|---|---|
| `install velocity` | **0** | 2 |
| `eval` | 2 | 29 |
| `trend` | 2 | 7 |
| `last run` | 1 | 2 |
| `runs` | 14 | 29 |

And every survivor is observable, read in context rather than counted:

- Both `trend` hits are one section, `:3138`, headed **"Why there is no 'trending' band"** — the
  honesty guardrail itself, not the defect.
- Both `eval` hits, `:3614` and `:3692`, are about a browser engine's `browser_evaluate` and have
  nothing to do with the boards.
- `Last run` at `:3474` and `Runs` at `:3470` are the **session analyst's own** cadence and last
  run — `41 min ago · 12,400 lines · 3 findings`. The router schedules and runs it, so it observes
  both directly.
- The Skills table's `Runs` column at `:2576` is sourced, and the mock says where: `:2772` —
  *"Every run records the version that was live at the time, so a check result never outlives the
  thing it tested."* That is the session analyst grepping sessions, which is a PRD feature the
  owner asked for by name, not the router observing an invocation it never sees.

`install velocity` is gone outright. So the mock kept the numbers that acquired a source and
deleted the ones that could not have one — which is exactly what the no-fabricated-numbers rule
asks for, arrived at without this docket.

**What remains is ordinary work, not a decision.** The build still drops the Skills runs column,
because the session analyst is not built; that is per-surface work under M17 and M20. And
`campaign.json`'s `designOfRecord` still names the prototype, so SURF-006 and SURF-011 fail
against a reference that is no longer the reference — already recorded in `ORCHESTRATOR.md` as
belonging to the campaign's own session.

### 3 · DEF-008 — accepted and closed by the orchestrator

Nothing needs the identifier: `MCPRouterIOSUITests` queries the tab bar by label and passes, and
both positions SwiftUI offers for the modifier were measured **clearing** the identifier rather
than setting it. The one untried route is UIKit introspection for a value nothing reads.

Naming what the losing option would be better at, which is the test for whose call this is: it is
better at nothing here. So the call is taken rather than asked — closed as a characterised
platform limitation, recorded at `PhoneShell.swift:121-129` so the two runs are not spent again.

### 2 · DEF-049 — the contract question is already answered, in the code, with its reason

**The CLI half is fixed.** The docket names `ManifestIndexer.record` calling `try? ManifestIO.save`
at `ServicePorts.swift:341`. That call is now a `do`/`catch` at `:388-394` returning a
`cacheFailure`, which propagates through `IndexOutcome` (`:320`, `:343`), reaches
`ControlPorts.swift:95`, and drives `cached` at `:108`. The self-contradicting output the docket
asked to fix has a consumer at `:348`.

**And the contract question was decided by whoever fixed it**, in the comment above the function:

> The error is reported, not thrown. Propagating it would change the CLI's exit code and the
> control API's status for a manifest that failed to write, and both are contracts this repo has
> taken a decision on elsewhere (`ControlApproveDispatchTests.swift:114-118`); moving either is its
> own item.

That is the docket's own smaller option, taken, with the precedent cited. Nothing to ask.

### 2b · The "unverified lead" is refuted, and the way it nearly passed is the finding

The docket recorded, as a lead it had not measured, that a *successful* approve leaves a recorded
refusal on screen because the approve path never removes `error`. The first half measures true:
`grep -n 'remove("error")' app/Sources/RouterCore/Auth/AuthRoutes.swift` returns **nothing**, and
`:108-114` removes only `pending`.

**It is still not a defect, because the state it needs cannot exist.** Approve is reachable only
for an entry carrying `pending`, and both implementations clear `error` when they stage one —
node at `src/manifest.ts:246` (`{ ...prev, hash, error: undefined, pending }`) and Swift at
`ManifestBookkeeping.swift:83` (`entry.remove("error")`). So `entry.member("error")` is `nil`, the
`guard case let .string(text)?` at `Describe.swift:208` fails, `rejection` is `nil`, and the
suppression guard at `:218` never runs. The two implementations agree, so it is not a parity
divergence either.

**Worth recording as an instrument finding rather than a product one.** This document, an hour
ago, said the lead was *verified* — on the strength of the grep above, which is true and
insufficient. "Approve never removes `error`" is not the quantity the claim rests on; "an entry
can carry `error` and `pending` at once" is, and it is false. That is `G4`'s shape exactly,
committed by the orchestrator, inside the docket that was re-measuring somebody else's claims.

### 2c · What is left of DEF-049 is real, dispatchable, and not what the docket describes

`AuthRoutes.swift:120` is still `try? ManifestIO.save(...)` — the last of the three call sites.
The docket's stated harm does not follow from it, for the reachability reason above. The harm that
does: **approve answers `200` with `approved: N` while the write is discarded**, so the manifest
still holds `pending`, the tool surface is still held, and the user has been told it was approved.

Same class as the CLI half, so the fix shape is already established here — carry the failure into
the response the way `cacheFailure` carries it into `IndexOutcome`, rather than changing what the
route returns. Filed as **R21**, as ordinary work.

### 4 · DEF-057 — a third option, measured, that the docket did not have

The docket offered bump-and-re-run or drop-the-claim. Measured today:

- `.claude/plugins/fledgeling-plugins` is **546 MB**, of which `plugins/` is 540 MB.
- **`plugins/test-campaign` alone is 8.9 MB** — 1.6% of the whole.
- Vendored `plugin.json` says `0.5.0`; the installed cache says `0.9.2`. Four minor versions, as
  recorded.

And a cost the docket could not have known, because it was measured this morning: **populating
this submodule in a worktree breaks every runner dispatched into it.** 546 MB of plugin skills
land where Claude Code loads them and the runner dies on context. It is now recorded as a
dispatch hazard in `ORCHESTRATOR.md`, and it is the reason every worktree here leaves the
submodule uninitialised.

So "vendor what the campaign actually runs" is available at 8.9 MB with none of that hazard,
which is a different proposition from the 546 MB bump the docket was weighing.

### 5 · DEF-033 — unchanged

Stays open and unexplained on purpose. Nothing to decide, nothing proposed.
