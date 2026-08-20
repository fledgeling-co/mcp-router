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
