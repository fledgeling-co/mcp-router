# spec-M14 — a shipped menu tells the user the app is not built

| | |
|---|---|
| ID | M14 |
| Status | Ready for Work |
| Category | mac |
| Depends on | M1 ✓ · M6 ✓ · M11 ✓ · M13 ✓ |
| Branch | `ai/m14` · worktree `.worktrees/M14` |
| Owns this wave | `app/Sources/MCPRouterKit/Shell/MenuCommand.swift` · `scripts/acceptance/mac-shell.sh` |
| Brief | `planning/features-to-triage/M14-menu-says-not-built.md` |
| Review | `grok-4.6`, out-of-family. **AMEND**, 6 findings; §8 records each and what was done |

---

## 1 · What is wrong, measured rather than asserted

`MenuCommand.swift:319-321` returns `.surfaceAbsent` **unconditionally** for two commands, under a
comment reading *"Still owned by items that have not shipped."*:

```swift
// Still owned by items that have not shipped.
case .pairPhone, .exportLibrary:
    return .surfaceAbsent
```

and `:90` gives `.surfaceAbsent` the headline *"This part of the app isn't built yet."*

**M6 shipped the pairing surface.** `InboxBoard.swift:215` is
`Button(InboxCopy.pairingButton) { board.pairing.open() }` — an **always-enabled** in-pane
*Pairing…* button. `ShellCommandRouter.swift:147-152` routes `.pairPhone` to `.openPairing`, which
does `select(.inbox)` then `inboxBoard.pairing.open()` — **the same call the button makes**.
`BoardRegistry.installed` contains `.inbox`, and `ShellCommandRouterTests` pins the routing.

So the board offers the action and the menu says the action does not exist. That is the shell
disagreeing with its own window — the exact defect M4 fixed for `Add marketplace…`, recorded in
`SkillsMenuTests`' own docstring, reproduced one item later.

### What "true" means for `Pair iPhone…`, argued rather than assumed

**A Release build cannot complete a pairing, and that is by design.** Verified in source, not taken
on report:

- `ShellPairingFactory.choice(isDebugBuild:environment:)` returns `.noTransport` for any non-Debug
  build and **deliberately ignores the environment** — its docstring explains why: a Release build
  talked into a fixture would draw a QR encoding an endpoint nothing is listening on.
- `NoTransportInboxService.availability()` is `.noEndpoint`.
- `PairingSessionModel.open()` sets `phase = .noEndpoint` and returns before minting a code.
- `PairingSheet.swift:75` says in its own comment: *"The state a Release build reaches is
  `noEndpoint`"*, and renders `InboxCopy.Pairing.noEndpointTitle` — **"Pairing is not available in
  this build"**.

So this item does **not** claim pairing works. `Pair iPhone…` carries an ellipsis, and `DESIGN.md`
§3.4 fixes its meaning: *`…` means "opens a further view"*. The further view exists, ships, and
states its own unavailability adjacent to the thing (§6). The command therefore reports what is
true of **itself**: it opens the pairing view. The claim about transport belongs in the sheet,
which already makes it honestly.

The falsifier, stated so a later reader can check it: if the in-pane *Pairing…* button were ever
gated on `PairingAvailability`, the menu item would have to be gated the same way, and `.inbox`
alone would stop being the right predicate.

### `.exportLibrary` is genuinely unbuilt

`ShellCommandRouter.shellOperation` puts it in the `.none` bucket and there is no export surface
anywhere in either target. Nothing about it is context-dependent.

### The Release gate, and what it is actually catching

`mac-shell.sh:1125` fails with

> every destination has a board, but the Release bundle still contains 'isn't built yet' — the
> scaffold outlived the surface it stood in for

**Measured on `ai/m14` at `317d957`, clean `make build-mac-release`, exit 0**, counting occurrences
per file in `Release/MCPRouter.app`:

| Needle | Count | Where |
|---|---|---|
| `isn't built yet` (what the gate greps) | **1** | `Contents/MacOS/MCPRouter` |
| `This part of the app isn't built yet.` (the full `surfaceAbsent` reason) | **1** | same file |
| `Select a server first.` (`needsServerSelection`, control) | 1 | same file |
| `ScaffoldCopy` | **0** | — |
| `ScaffoldedDestination` | **0** | — |
| `ScaffoldPane` | **2** | same file |
| `BoardRegistry` (control) | 17 | same file |

Three things follow, and all three shape the design:

1. **The scaffold is genuinely gone.** `ScaffoldCopy` and `ScaffoldedDestination` are absent from
   the shipping binary. M6's deletion worked. The gate's own failure text — *"the scaffold outlived
   the surface it stood in for"* — is a **misdiagnosis**.
2. **The single occurrence of the sentinel is `surfaceAbsent.reason`.** The gate is red because a
   live help tag shares a substring with the deleted pane's copy, which it shared *on purpose* at
   M1, and the gate matches the shared fragment rather than either sentence.
3. **A bytes grep cannot express reachability.** `Select a server first.` is present as a control;
   a reason literal is compiled in because `reason` is a `public` computed property on a `public`
   enum in `MCPRouterKit`, whether or not any path reaches it. `ScaffoldPane` is present at 2
   despite the *type* being deleted, because the **file path** `ScaffoldPane.swift` survives in
   metadata — so the needle must be a type name the file no longer declares, never the file name.

### Why no test caught it

`SkillsMenuTests.othersStillAbsent` asserts, *against the real registry*:

```swift
#expect(MenuCommand.pairPhone.availability(in: real) == .surfaceAbsent)
#expect(MenuCommand.exportLibrary.availability(in: real) == .surfaceAbsent)
```

under the title *"The two commands whose surfaces have not shipped still say so"* and the comment
*"Narrowed by exactly what shipped, never relaxed."* It was correct when M4 wrote it and became a
green test **pinning a falsehood** the moment M6 shipped the pairing surface. The test rotted in
the same window as the code and asserted the rot, which is why the suite stayed green.

---

## 2 · The two cases that must be separated

| Case | Meaning | True of | Changes when |
|---|---|---|---|
| **destination absent** | the surface this command acts on is **not compiled into this build** | nothing, now — all eight boards ship | a `Destination` is added without a board |
| **feature unbuilt** | the thing this command does **does not exist in the product at all** | `.exportLibrary` | someone builds export |

Different facts, different lifetimes, different sentences. Conflating them is what let a shipped
command keep a not-shipped reason: only one refusal meant "no", so `.pairPhone` kept the one it was
given at M1 and nothing could tell it had stopped being true.

---

## 3 · The design

### D1 — a third refusal, `CommandAvailability.featureUnbuilt`

`CommandAvailability` gains one case. Its docstring says *"Exactly two reasons exist, and they are
on the type rather than at each call site so a third cannot be invented in passing"* — the third is
being added **on the type**, once, deliberately, which is precisely what that sentence protects.
The docstring is updated to say three and why.

| Case | Reason | Change |
|---|---|---|
| `.surfaceAbsent` | `This part of the app isn't built yet.` | **unchanged** |
| `.featureUnbuilt` | `This feature hasn't been built yet.` | new |
| `.needsServerSelection` | `Select a server first.` | unchanged |

**`.surfaceAbsent`'s sentence is deliberately left alone.** An earlier draft of this spec changed
it so the sentinel would leave the binary and the existing bytes grep could pass. The review
refuted that, and it was right: the sentence is *honest for its own case* — a build genuinely
missing that board — and rewriting live copy so a grep stops matching is changing the product to
suit a check that §1.3 already proved cannot ask the question it is being asked. §3.3 retargets the
check instead.

Only one command reports `.featureUnbuilt`, so its sentence is generic rather than naming the
feature. The review asked for per-command copy (*"Export isn't available yet."*); that needs either
an associated value — which breaks `==` at six test sites and the gate's `switch` — or moving
reason resolution from `CommandAvailability` onto `MenuCommand`, a refactor of the
`ShellMenuReasons` seam. Both are larger than this item. **Registered as a deferred child rather
than done here**, and it becomes necessary the moment a second command takes this case.

### D2 — `.pairPhone` derives, `.exportLibrary` declares

```swift
case .pairPhone:
    return context.installedDestinations.contains(.inbox) ? .enabled : .surfaceAbsent
case .exportLibrary:
    return .featureUnbuilt
```

`.pairPhone` follows exactly the rule `.addServer` follows for `.servers` and `.addMarketplace` for
`.skills`: **the board that hosts the sheet is the board it depends on.** `.exportLibrary` is
context-independent, because no context makes an unwritten feature exist.

### D3 — the gate distinguishes the two cases

M11 moved A22's expectation into a **derived** oracle: `mac-shell.sh` compiles `MenuCommand.swift`
and `Destination.swift` at gate time and asks `availability(in:)` with the real registry, so the
expectation cannot rot when a board ships. That property is preserved. The substring grep at
`:1120-1129` is replaced by four assertions:

| # | Assertion | Kind | Can fail when |
|---|---|---|---|
| **G1** | no destination lacks a board ⟹ **no command reports `.surfaceAbsent`** | derived, structural | a command is hardcoded to `.surfaceAbsent` while every board ships — M14's own defect |
| **G2** | `File / Pair iPhone…` is `enabled=1` with **empty** `AXHelp` in the running app | **named, hand-written** | pairing is re-dimmed, or the reason is not cleared |
| **G3** | every command the oracle reports as `.featureUnbuilt` is dimmed carrying that sentence | derived, rendered | export goes live in the model but not on screen, or vice versa |
| **G4** | the Release bundle contains neither `ScaffoldCopy` nor `ScaffoldedDestination` | bytes | either scaffold type is reintroduced |

**G2 is deliberately hand-written, against this repo's general preference for derivation.** M11's
own M2 finding is the reason: a derived oracle *cannot* falsify the gating map, because a mutation
moves the expectation and the app together. G1 alone is satisfied by moving `.pairPhone` onto
`.featureUnbuilt`, or `.needsServerSelection` — every one of which leaves the user-visible bug in
place. G2 is the row that names the command this item exists to fix, and it can only be satisfied
by the menu item actually being usable and silent. It rots only if pairing is deliberately
withdrawn, which is a deliberate edit.

**G3's tripwire is conditional on the oracle's own count, not `>= 1`.** An unconditional "at least
one `.featureUnbuilt` command" would make *shipping export* a gate failure. When the oracle reports
none, the branch is skipped and says so.

**G4 replaces the sentinel grep rather than deleting it.** The check's stated purpose is that the
placeholder must not outlive the boards; §1 measured that the right needle is the deleted *types*,
which are at 0, and that the file name is at 2 and therefore unusable. This keeps the only gate in
the repo that reads the shipping artifact, and points it at something it can actually answer.

The `SCAFFOLDS_REMAIN` branch is kept and inverted rather than deleted: when a destination genuinely
has no board, G1 flips to requiring **at least one** `.surfaceAbsent` report. `main` cannot reach
that branch today, and this spec records it as **unexercised** rather than claiming it proven.

### D4 — the tests that pinned the falsehood

`SkillsMenuTests.othersStillAbsent` is re-pointed and split, because one assertion has become two
different truths. Its replacement asserts `.pairPhone` **enabled** against the real registry, and
`.pairPhone` **`.surfaceAbsent`** against a context without `.inbox` — the second is what makes the
rule falsifiable per-command, which M11's M2 finding says a full-set assertion alone cannot do.

---

## 4 · Acceptance criteria

| # | Criterion | Oracle |
|---|---|---|
| **A1** | `.pairPhone` reports `.enabled` against `BoardRegistry.installed` | unit |
| **A2** | `.pairPhone` reports `.surfaceAbsent` when `.inbox` is **not** installed | unit — per-command falsifiability |
| **A3** | `.exportLibrary` reports `.featureUnbuilt` in every context, including `.none` | unit |
| **A4** | `.featureUnbuilt`'s reason is non-empty and is **not** `.surfaceAbsent`'s | unit |
| **A5** | With every destination installed, **no** command reports `.surfaceAbsent` | `mac-shell.sh` G1 |
| **A6** | `File / Pair iPhone…` renders enabled and silent in the running app | `mac-shell.sh` G2 |
| **A7** | Each `.featureUnbuilt` command renders dimmed with its own sentence | `mac-shell.sh` G3 |
| **A8** | The Release bundle carries neither scaffold type | `mac-shell.sh` G4 |
| **A9** | `mac-shell.sh` exits 0 | the script |
| **A10** | The inventory table and the model still agree in both directions | `MenuCommandTests` — `.exportLibrary`'s `.none` answer changes, so its row changes with it |

## 5 · State matrix — the File menu's four commands, with real copy

| Command | No boards (`CommandContext.none`) | Eight boards (shipped) |
|---|---|---|
| Add server… | dimmed · *This part of the app isn't built yet.* | enabled, silent |
| Add marketplace… | dimmed · *This part of the app isn't built yet.* | enabled, silent |
| Pair iPhone… | dimmed · *This part of the app isn't built yet.* | **enabled, silent** — the change |
| Export library… | dimmed · *This feature hasn't been built yet.* | dimmed · *This feature hasn't been built yet.* |

Opening `Pair iPhone…` in a Release build lands on the pairing sheet's `noEndpoint` state, which
reads **"Pairing is not available in this build"**. That is the designed state, shipped by M6, and
this item does not change it.

## 6 · Scope

**In:** `MenuCommand.swift`, `mac-shell.sh`, the tests pinning the two commands' availability and
the reason strings, and `spec-M1.md`'s one inventory row plus the prose naming the reasons.

**Out, deliberately:** changing `.surfaceAbsent`'s sentence (§3 D1); per-command `.featureUnbuilt`
copy (deferred child); M9's `Evals`→`Checks` rename; `D-m13-a`/`D-m13-b`; `ScaffoldPane.swift`'s
rename (`D-m6-c`); `ScrollEdge` and the boards; building export; and gating the menu on
`PairingAvailability` (§1 — the in-pane button is not gated on it either, and changing both is a
product decision about pairing, not about a menu).

## 7 · Assumptions

1. **`.pairPhone` depends on `.inbox` and nothing else**, because the board hosts the sheet and its
   own button is ungated. Falsifier named in §1.
2. **Export is genuinely unbuilt**, so `.featureUnbuilt` is unconditional. If an export surface
   later ships behind a destination, D2's arm becomes a context test like the other three.
3. **The oracle's `switch` in `mac-shell.sh` is exhaustive over `CommandAvailability`.** Adding a
   case without editing it is a *compile* failure, which the script maps to BLOCKED (exit 2), not
   to a red gate. That is the script's own documented doctrine (`mac-shell.sh:23-25`, upheld at
   M11's L4) and is stated here so the edit is not forgotten.

## 8 · Review — `grok-4.6`, out-of-family. **AMEND**, all six dispositioned

Lane smoke-tested before use; both the exit code **and** the presence of real review content
asserted, per V1's finding that grok exits 0 on a failed session init. Codex is account-limited
until 2026-08-20 and was not probed.

| # | Finding | Disposition |
|---|---|---|
| 1 | *"`.pairPhone` → `.inbox` is wrong as a claim that pairing works"* — Release is always `NoTransportInboxService` / `.noEndpoint`, and the sheet already says so | **Accepted, and verified in source before accepting.** The spec no longer claims pairing works; §1 argues the narrower and true claim — the command opens a further view (§3.4) that ships and is honest about its own transport — and names the falsifier |
| 2 | *"Option A is wrong: it rewrites live copy so a grep stops matching"*, and the `M7DesignedStateTests` argument is a category error (that list scans `CheckCopy`, never `CommandAvailability`) | **Accepted.** `.surfaceAbsent`'s sentence is now unchanged. The review is right that the old D2 existed only to make the old D4.3 pass |
| 3 | *"Option C: retarget the Release needle at a token only the deleted pane owned"* | **Accepted, with a measured correction.** Its suggested `ScaffoldPane` is present **2×** in the shipping binary because the *file path* survives in metadata. The needles are `ScaffoldCopy` and `ScaffoldedDestination`, both measured 0 |
| 4 | *"G1 can pass for the wrong reason — classify pairing as unbuilt and it is green while the bug remains"* | **Accepted.** G2 added as a named, hand-written row that only a usable, silent `Pair iPhone…` satisfies, with M11's M2 finding cited as why derivation cannot cover it |
| 5 | *"`N >= 1` makes shipping export a gate failure"* | **Accepted.** G3's tripwire is conditional on the oracle's own count |
| 6 | *"Scope creep on a brief that said small"* — the third case, the `.surfaceAbsent` rewrite, the extra source scan, the taxonomy | **Mostly accepted.** The `.surfaceAbsent` rewrite is gone and the extra source-scan test (old D5) is dropped — its premise died with it. The third enum case stays: the brief asks for exactly this separation, and it cannot be expressed with two refusals |
| — | *"Per-command `.featureUnbuilt` copy"* | **Rejected here, registered as a child.** Needs an associated value (breaking `==` at six test sites and the gate's `switch`) or moving reason resolution onto `MenuCommand`. Both exceed the item; the review itself objected to scope creep |
| — | *"`⌘E` remains bound to an unbuilt command"* | **Noted, not fixed.** Pre-existing, inert (a dimmed command's chord does nothing), and listed in `spec-M1.md`'s inventory. Registered as a child |
| — | *"What does enabled mean with no focused window"* | **Already registered as `D-m11-b`**, M11's accepted-and-not-fixed finding. Not re-opened here |

**The plan gate and the Phase D critic both returned AMEND too**, and both changed the work rather
than decorating it. The plan gate found that two of the five mutations could not have reddened what
they claimed — `.exportLibrary → .enabled` moves oracle and app together, and an unreferenced
`ScaffoldCopy` is dead-stripped — so both were **re-aimed, not swapped for easier ones**; it also
established that a gate mutation without a rebuild reports BLOCKED rather than red. The Phase D
critic found that G3's zero-count arm could not fail and printed a claim the gate cannot make,
which added **G2b**, a named row for `Export library…`. Full dispositions in
`planning/evidence/M14-acceptance.md`.
