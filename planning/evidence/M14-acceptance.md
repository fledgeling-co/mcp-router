# M14 acceptance — the two refusals, and the gate that could not tell them apart

Branch `ai/m14`, worktree `.worktrees/M14`, from `317d957`. Measured 2026-08-15.

M14 was scoped from a red gate on `main`:

```
FAIL: every destination has a board, but the Release bundle still contains 'isn't built yet'
      — the scaffold outlived the surface it stood in for
```

**That failure text was a misdiagnosis, and measuring it is what set the design.** On a clean
`make build-mac-release` (exit 0), counting occurrences per file in `Release/MCPRouter.app`:

| Needle | Count | Where |
|---|---|---|
| `isn't built yet` (what the gate grepped) | **1** | `Contents/MacOS/MCPRouter` |
| `This part of the app isn't built yet.` (`surfaceAbsent.reason`) | **1** | same file |
| `Select a server first.` (`needsServerSelection`, control) | 1 | same file |
| `ScaffoldCopy` | **0** | — |
| `ScaffoldedDestination` | **0** | — |
| `ScaffoldPane` | **2** | same file |
| `BoardRegistry` (control) | 17 | same file |

The scaffold **is** gone — M6's deletion worked, and both types it declared are absent from the
shipping binary. The sole hit was a **live menu help tag** that shared a substring with the deleted
pane's copy, deliberately, since M1. Three consequences, all load-bearing:

1. A bytes grep **cannot ask about reachability.** The control row proves it: a reason literal is
   compiled in because `reason` is a `public` computed property on a `public` enum, whether or not
   any path reaches it. "No command reports this case" has to be asked of the model.
2. The needle must be a **type the file no longer declares**, never the file's name — `ScaffoldPane`
   sits at 2 because the *path* survives in metadata, and would have failed for a benign reason.
3. Changing `surfaceAbsent`'s sentence to make the old grep pass would have been changing the
   product to suit a check. It was proposed, reviewed, and dropped (see the reviews below).

## What was actually broken

`MenuCommand.swift:319-321` returned `.surfaceAbsent` unconditionally for `.pairPhone` and
`.exportLibrary`, under a comment reading *"Still owned by items that have not shipped."*

M6 shipped the pairing surface. `InboxBoard.swift:215` is
`Button(InboxCopy.pairingButton) { board.pairing.open() }` — an **always-enabled** in-pane
*Pairing…* button — and `ShellCommandRouter.swift:147-152` routes `.pairPhone` to the **same call**.
So the board offered the action and the menu said it did not exist: the shell disagreeing with its
own window, which is the defect M4 fixed for `Add marketplace…` and which reappeared one item later.

**This item does not claim pairing works, and that distinction was forced by the review.** Verified
in source: `ShellPairingFactory.choice(isDebugBuild:environment:)` returns `.noTransport` for any
non-Debug build and deliberately ignores the environment; `NoTransportInboxService.availability()`
is `.noEndpoint`; `PairingSheet.swift:75` says in its own comment *"The state a Release build
reaches is `noEndpoint`"* and renders **"Pairing is not available in this build"**. `Pair iPhone…`
carries an ellipsis, and `DESIGN.md` §3.4 fixes its meaning as *opens a further view*. The view
exists, ships, and states its own unavailability adjacent to the thing (§6). That is what the
command now reports — no more.

## Why the suite never caught it

`SkillsMenuTests.othersStillAbsent` asserted, against the **real registry**, that `.pairPhone` was
`.surfaceAbsent` — under the title *"The two commands whose surfaces have not shipped still say
so"* and the comment *"Narrowed by exactly what shipped, never relaxed."* Correct when M4 wrote it;
a green test **pinning a falsehood** from the moment M6 shipped. It rotted in the same window as
the code and asserted the rot.

Three more sites had rotted the same way and are re-pointed: `MenuCommandTests.gatingMapIsPerCommand`,
`ShellMenuContextTests.commandItemsReadTheLiveContext`, and the walker test at
`ShellMenuContextTests:37-39` — which asserted **every** disabled item's tooltip equals
`surfaceAbsent.reason`, passing only because every disabled command happened to share one string.
It now compares each item against **its own** command's reason, which the old form could not do:
it could not tell a walker writing the *right* reason from one writing *a* reason.

`ShellScaffoldRetirementTests.placeholderIsNotReintroduced` never reached the sentence either — it
iterates `ShellTestSupport.shellFiles`, which lists `MCPRouterUI/Shell/` only, while the string
lives in `MCPRouterKit/Shell/MenuCommand.swift`. The source-level guard against exactly this string
was watching the wrong directory.

## The gate

| Clause | How verified | Result |
|---|---|---|
| **G1** — every board present ⟹ no command reports `surfaceAbsent` | `mac-shell.sh`, counted from the A22 oracle compiled from this tree | pass — 0 |
| **G2** — `File / Pair iPhone…` enabled with empty `AXHelp` | `mac-shell.sh`, named row against `items.tsv` from the backgrounded app | pass |
| **G2b** — `File / Export library…` dimmed, with a reason of its own | `mac-shell.sh`, named row; added by the Phase D critic | pass — `This feature hasn't been built yet.` |
| **G3** — each `featureUnbuilt` command dimmed with its **own** sentence | `mac-shell.sh`, derived, conditional on the oracle's count | pass — 1 exercised |
| **G4** — Release bundle carries neither scaffold type | `mac-shell.sh`, bytes over every file in the bundle | pass |
| `make lint` | exit code captured directly, never through a pipe | 0 |
| `make test` | whole suite | 0 — **1379 tests / 169 suites**, unchanged from `main` |
| `make build-mac` / `make build-mac-release` | | 0 / 0 |
| `mac-shell.sh` | whole script, on the final tree | **0 — 39 assertions, 0 failures** |
| Invisibility | frontmost sampled after every phase | pass — never frontmost; ended on Ghostty |

### The gate was proven able to fail — each assertion for its own reason

Every mutation was rebuilt before the gate ran. **Without a rebuild each one reports BLOCKED (exit
2), not red** — the freshness check is doing its job, and a blocked run would not have proven
anything. Restored by re-applying the original edit, never `git checkout --`.

| Mutation | Result |
|---|---|
| `.pairPhone` → unconditional `.surfaceAbsent` (the shipped defect) | **G1 red** — *"every destination has a board, but 1 command(s) still report surfaceAbsent"*, naming `File / Pair iPhone…` |
| `.pairPhone` → `.featureUnbuilt` | **G1 GREEN, G2 red** — the load-bearing one. Re-classifying the command satisfies the derived assertion completely; only the named row catches it |
| `.featureUnbuilt`'s sentence collapsed into `.surfaceAbsent`'s | **G1, G2 and A22 all green, G3 red** — *"Export library… has no feature at all, but explains itself with the missing-board sentence"* |
| `enum ScaffoldCopy` reintroduced **and referenced** | **G4 red** — 11 occurrences in the Release binary. An *unreferenced* type is dead-stripped and would not have reddened, which is why the mutation makes it used |
| `.pairPhone` gated on `.servers` instead of `.inbox` | `gatingMapIsPerCommand` and `theTwoUnshippedCommandsAreOneNow` **red** — the partial-context form; every full-set assertion stays green, which is the point |

**Why G2 is hand-written where everything around it is derived.** M11 moved A22's expectation into
a compiled oracle so it could not rot, and recorded as its own finding M2 that a derived oracle
*cannot* falsify the gating map — a mutation moves expectation and app together. The second
mutation above is that finding made concrete: G1 is green while the user-visible bug is on screen.
G2 is the one row that can only be satisfied by the command actually being usable and silent.

**What G3 adds over A22, stated because most of it is overlap.** A22 already walks every
non-`enabled` row and compares `AXHelp` to the oracle's reason, so G3's presence and dimming checks
are a second reading. The assertion that is *only* in G3 is the last one: an unbuilt feature must
not explain itself with the missing-board sentence. A22 cannot catch that — it compares rendering
to oracle, so if both were the missing-board sentence it passes. The third mutation proves the
distinction is real.

### Two false reds and one false block, all load, none a defect

Runs of this harness kept dying **before reaching the M14 block**, at a different place each time:
*"could not select the 'Settings' row through the accessibility API"*, `axkit: no window` during
restoration, *"could not select Evals"*, *"the key probe does not hold keyboard focus"*, and
`_LSOpenURLsWithCompletionHandler() failed … error -600` — LaunchServices refusing to start the app
at all. Load average was between **207 and 418** throughout; another project was running full Swift
builds on the same machine.

**Recorded rather than hidden, because re-running until green is how a real race gets buried** —
this fleet's own `D-p` lesson. The discriminator applied here: every one of these landed in an
AX-driven section M14 does not touch, none ever landed on G1–G4, and G1–G4 passed in every run that
reached them, including the four mutation runs. Three unrelated tests (`PoolReapingTests`,
`ControlStreamTests`, `ActivityReconnectTests`) also failed once under the same load and were green
again on the restored tree. The final green is a whole-script exit 0 on the exact committed tree.

## The Phase D completeness critic — `grok-4.6`, AMEND, 5 findings

Run against the real `git diff`. Four were defects in this change and were fixed; two are
pre-existing and are registered.

| # | Finding | Disposition |
|---|---|---|
| 1 | **G3's zero-count arm cannot fail, and its pass text was false.** Recategorising `Export library…` as `needsServerSelection` takes the skip branch, leaves G1 and A22 green, and the gate would have printed *"every feature the menu offers exists"* — something it has no way to know | **Accepted, and closed two ways.** The skip arm now prints only what was observed, and **G2b** was added: a named row asserting `Export library…` is dimmed with a reason of its own that is not the missing-board sentence. Symmetrical with G2, and falsifiable for the same reason |
| 2 | **A comment claimed `placeholderIsNotReintroduced` "scans every shell source"** — it walks `ShellTestSupport.shellFiles`, which is `MCPRouterUI/Shell/` only and cannot see the Kit file that actually ships the sentence | **Accepted.** The comment now states the guard's real extent. A guard believed wider than it is, is worse than a narrow one |
| 3 | **A comment claimed `scaffoldTypesStayDeleted` asserts the two types "at source level"** — it reads `ScaffoldPane.swift` alone, so a `ScaffoldCopy` elsewhere would not fail it | **Accepted.** Corrected to say the test covers this file and the gate covers the shipping artifact wherever the types are declared |
| 4 | **`spec-M1.md:276-278` still asserted a disabled command reads the missing-board sentence** — a second prose site, in a file already in the diff | **Accepted.** Narrowed, naming `Export library…` as the command that now reads the other sentence |
| 5 | **`SkillsMenuTests.theTwoUnshippedCommandsAreOneNow` is named for the opposite of what it asserts** | **Accepted.** Renamed `pairingIsLiveAndExportIsNot` |
| — | *"`Pair iPhone…` is enabled while Release pairing is `noEndpoint`; the shell now agrees with the board and both over-claim"* | **Rejected, with the reason already in the spec.** The command opens a further view (§3.4) and that view is honest. The critic's own words are that the shell now *agrees* with the board — the alternative is a dimmed menu item beside a live in-pane button, which is the defect this item exists to remove. Gating both on `PairingAvailability` is a decision about pairing, not about a menu, and is out of scope by §6 |
| `D-m14-c` | *"`Export library…` keeps the ellipsis while its arm says the feature does not exist"* — `…` promises a further view there is none of | **Real, and pre-existing.** M1 chose the title and `MenuCommandTests.ellipsisRule` pins it; the command is permanently dimmed so it opens nothing either way. Changing a title is an inventory change. **Registered, not fixed** |

## What changed

- `MenuCommand.swift` — `CommandAvailability.featureUnbuilt` added **on the type**, which is what
  the type's own rule protects; `.pairPhone` derives from `.inbox`; `.exportLibrary` declares
  `.featureUnbuilt`. `CommandContext`'s docstring corrected — it said the type has "exactly those
  two refusals and no third", which this change makes false in a file it owns.
- `mac-shell.sh` — the sentinel grep replaced by G1–G4; the oracle's `switch` extended;
  `SURFACE_ABSENT_REASON` derived by re-running the same oracle binary with an empty installed set
  rather than written into the script.
- `ScaffoldPane.swift` — comments only. They described a `SENTINEL` read that no longer exists and
  a gate that no longer greps that string.
- The four rotted test sites, plus `MenuCommandTests` gaining an assertion that the two sentences
  stay **distinct** — pinning both literals is not enough, because someone collapsing one into the
  other would edit both literals in the same pass and the file would stay green.
- `spec-M1.md` — the `Export library…` inventory row, and the prose naming the reasons.

### `spec-M1.md` is committed on this branch, against the fleet's docs-stay-in-main rule

Stated because it is a deliberate exception. That table is a **test oracle**:
`MenuCommandTests.inventoryMatchesTheModelBothWays` parses it, and `repoFile` resolves to the
worktree's copy. `.exportLibrary`'s answer in `CommandContext.none` genuinely changes, so the row
must change in the same commit or the branch is red on checkout. M11 could leave the table alone
because no `.none` answer had changed; M14 is the first item where one does. `spec-M14.md` and
`plan-M14.md` remain uncommitted in the main tree as the rule requires.

`Pair iPhone…`'s row is deliberately **unchanged**: that column records the answer with no board
installed, where `surfaceAbsent` is still correct.

## Not fixed, and why

| # | Finding | Why not here |
|---|---|---|
| `D-m14-a` | `.featureUnbuilt`'s sentence is generic rather than naming the feature | Naming it needs an associated value — changing every `==` against the case, at six test sites and the gate's `switch` — or moving reason resolution from `CommandAvailability` onto `MenuCommand`. Both exceed this item. Becomes necessary the moment a second command takes the case |
| `D-m14-b` | `⌘E` is still bound to a permanently unusable command | Pre-existing, inert (a dimmed command's chord does nothing), and listed in `spec-M1.md`'s inventory |
| `D-m11-b` | Enabling `.pairPhone` adds one more command that renders enabled but no-ops with no focused window | Already registered by M11 as accepted-and-not-fixed. This extends the existing set by one rather than creating the class |
| — | Gating the menu on `PairingAvailability` | The board's own `Pairing…` button is not gated on it either. Changing both is a decision about pairing, not about a menu |
| — | G1's inverse (a boardless destination ⟹ some command reports `surfaceAbsent`) | Removed after review: unsound, and a false-red the first time a `Destination` is added with no command gated on it. That branch is unreachable today and reports rather than asserts |

## The review lanes

Codex is account-limited until 2026-08-20 and was **not probed**, per the fleet's standing note.
All three gates ran on **`grok-4.6`**, out-of-family, per the owner's instruction. The lane was
smoke-tested before use and every dispatch asserted on **both** the exit code and the presence of
real review content — V1 measured that grok exits 0 carrying only an error payload when session
init fails, so `$?` alone would have logged reviews that never ran.

| Gate | Verdict | Outcome |
|---|---|---|
| Spec | **AMEND**, 6 findings | All dispositioned in `spec-M14.md` §8. It killed the first design — which rewrote `surfaceAbsent`'s live copy so a grep would pass — and found that Release pairing is `noEndpoint`, which was verified in source before being accepted. Its suggested Release needle (`ScaffoldPane`) was **corrected by measurement**: 2 occurrences, because the file name survives |
| Plan | **AMEND**, 5 findings | Two mutations could not have reddened what the plan claimed (`.exportLibrary → .enabled` moves oracle and app together; an unused `ScaffoldCopy` is dead-stripped) and were **re-aimed rather than swapped**. It also caught that every gate mutation without a rebuild is BLOCKED not red, and independently reached the same conclusion about `spec-M1.md`'s tree |
| Phase D critic | see below | Run on the actual diff |
