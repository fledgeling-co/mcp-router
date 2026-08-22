# M15 gap-fix — four record defects closed, and the guard the product defect never had

`Settings becomes its own window` · branch `ai/m15` · worktree `.worktrees/M15` · base `aae3033`
Parent `planning/progress/M15.md` · Verdict being answered: **Needs More Work**, 2026-08-22, first
verification.

Delivered and ready to verify. Not verified here.

---

## BL-1 — the divergence list now adjudicates, and the rule says what it enforces

`planning/fidelity/settings.layers.json` declared **four** divergences under the rule *"a finding
outside this list is a defect"*, and described all 97 of the run's findings as inside them. Counted
off the ledger's own rows: **49 were not**, and **two of the four carried no finding at all**.
Nobody had added the table up — the sentence and the table were written from different places.

The list is nine now, every citation in `settings.pairing.tsv` opens with `Dn · `, and the number
reaches the generated ledger's citation column. So the split is countable off the artifact the run
wrote rather than off the file making the claim:

    $ L=planning/fidelity/settings.ledger.md
    $ F='| \(absent\|divergent\|extra\|extra-cited\|unclassified\) |'
    $ echo "findings:    $(grep -c "$F" $L)"
    $ echo "adjudicated: $(grep "$F" $L | grep -c '| D[0-9] ·')"
    $ grep -o '| D[0-9] ·' $L | sort | uniq -c
    findings:    97
    adjudicated: 97
      14 | D3 ·
      34 | D4 ·
      12 | D5 ·
       1 | D6 ·
      28 | D7 ·
       7 | D8 ·
       1 | D9 ·

| # | Divergence | Owner | Findings |
|---|---|---|---|
| D1 | the source list is 256pt and the mock draws 200 | M21 | **0** |
| D2 | four of the seven source-list symbols have no `Icon` case | M21 | **0** |
| D3 | the mock is a tab set and the build is a split view | the conversion | 14 |
| D4 | affordances naming capabilities this product does not have | whichever item builds each | 34 |
| D5 | the router is stopped: the mock refuses the window, the build keeps it live | spec-M15 §2 assumption 7 | 12 |
| D6 | a sheet opened from a pane is M18's | M18 | 1 |
| D7 | the mock's affordance census does not reach the structure the build draws | nobody — an instrument limit | 28 |
| D8 | M8's shipped Settings surface, carried forward, that the mock does not draw | M8 | 7 |
| D9 | the mock states figures nothing in this process observes | nobody — `DESIGN.md` §6 | 1 |

**D1 and D2 carrying zero is not a bookkeeping curiosity, it is the finding under the finding.** Both
are about the source list, and the source list is unpaired for D7's reason — the mock draws it
outside every `.v-*` frame, so no census reaches it and no layer compares it. Two of the four
divergences the manifest offered as carrying 97 findings between them could not carry one.

**What the brief asked for and what it took.** The brief named two missing divergences: the
router-stopped state and the M18 handoff. Both are here as D5 and D6. Three more were needed —
D7, D8 and D9 — because 36 findings fell in classes the list had no number for at all, and widening
an existing divergence to swallow them is the move the brief forbade. Each of the three is a real
distinction rather than a bucket: **D7 is an instrument limit** (the mock draws the thing and the
census cannot see it), **D8 is a product difference with an owner** (the mock does not draw it and
M8 shipped it), and **D9 is an honesty rule** (the mock states a figure nothing observes).

**What is still not enforced, stated in the manifest rather than implied.** No layer *fails* on an
untagged citation. `mock_fidelity.py` reads column four as free text, and teaching it this rule is an
edit to the engine, which is outside this brief's scope. The tag makes the adjudication **derivable
from the run's own artifact**; it does not make it automatic. The three lines above are what a reader
runs, and they are in the manifest beside the rule.

## BL-2 — the row count was thirteen and is twenty-two, in all four homes

Counted directly: `design/mcp-router-console.html:1554-1711` carries **30** `.form-row` elements in
`v-ideal` (5 Router, 4 Harnesses, 6 Session analyst, 4 Updates, 4 Security, 3 Menu bar, 4 Advanced).
**Eight** are built — Endpoint, Idle window, Warm set, Control token, Paired devices, Show in the
menu bar, Router log, Configuration — three of those as observed facts with the mock's control left
off. **Twenty-two are not.**

The four homes: `planning/fidelity/settings.layers.json`, `planning/fidelity/settings.pairing.tsv`,
`app/Tests/MCPRouterKitTests/SettingsPaneCopyTests.swift` and `planning/progress/M15.md`.

**The honesty test disagreed with its own docstring by seven rows and neither could see it.**
`absentCapabilitiesAreNotNamed` listed **sixteen** forbidden labels covering **fifteen** of the
twenty-two (plus `Rotate`, which is a control inside a row that *is* built). Seven unbuilt rows —
`Warn about duplicates`, `Check for drift`, `Harnesses to read`, `Frequency`,
`Notify me about findings`, `Hold a version that wants more`, `Update the app itself` — were named
nowhere, so a later runner could re-add any of them from the mock and the test that exists to stop
exactly that would have passed. The list is twenty-three now. None of the seven appears anywhere
under `app/Sources`, checked before adding them.

**The sweep, and why a line-anchored grep was never going to find this.** The claim wraps across two
source lines in three homes and across two **JSON array elements** in the fourth, so
`grep -n "thirteen of the mock's thirty rows"` returns nothing from any of them while all four say
it. Each file is normalised whole instead — every non-alphanumeric run collapsed to one space,
lowercased — which folds line breaks, `#` and `///` markers, JSON string boundaries and the
apostrophe together.

**And an absence check cannot detect its own blindness**, so the corrected phrase is searched by the
same code path in the same run and the four homes must come back. Both halves, against this tree:

    scanned 1137 readable files under /Users/lukerhodes/Dev/mcp-router/.worktrees/M15

    ABSENCE   'thirteen of the mock s thirty rows'
              planning/plans/plan-M15.md   [out of scope: the planner's artifact — recorded, not
                                            this item's to edit]

    CONTROL   'twenty two of the mock s thirty rows'
              app/Tests/MCPRouterKitTests/SettingsPaneCopyTests.swift
              planning/fidelity/settings.layers.json
              planning/fidelity/settings.pairing.tsv
              planning/progress/M15.md

    control held: all four homes carry the corrected figure, read by the same code path
    sweep clean:  no file this item owns states thirteen; 1 out-of-scope occurrence(s) named above
    EXIT=0

**Red-green, because a sweep that is green on the tree it was written against proves nothing.** The
identical script over a `git archive` of the base commit `aae3033`:

    ABSENCE   'thirteen of the mock s thirty rows'
              app/Tests/MCPRouterKitTests/SettingsPaneCopyTests.swift
              planning/fidelity/settings.layers.json
              planning/fidelity/settings.pairing.tsv
              planning/plans/plan-M15.md   [out of scope]
              planning/progress/M15.md

    CONTROL   'twenty two of the mock s thirty rows'

    CONTROL FAILED — the corrected figure is not readable in: … all four …
    EXIT=1

It names the four homes at base and none here. **A fifth occurrence exists and is deliberately not
edited:** `planning/plans/plan-M15.md:652` still reads thirteen. It is the planner's artifact, this
brief scopes the fix to four homes, and it leaves the plan's defects recorded rather than corrected —
so the sweep names it in every run with its reason attached, rather than skipping it silently. It is
the orchestrator's to take or leave.

The sweep is pasted rather than committed: this brief scopes the item to one acceptance script, and
that script is `mac-shell.sh`. Its method is one function — read each file whole, `re.sub(r"[^a-z0-9]+",
" ", text.lower())`, search the flattened string for both phrases, and require the four homes back on
the corrected one — and both of its outputs are above, so it is reproducible in a dozen lines by
whoever next changes the count.

## BL-3 — the duplicate-item guard, and it bit

`mac-shell.sh` gains **A19b**, immediately after the two loops that could not see this. Both loops
ask *"is this item accounted for?"*, and a second identical item answers exactly as the first does.
So A19b counts:

- no `(menu, title)` pair occurs more than once;
- no chord is carried by more than one item.

`AXMenuItemCmdChar` is read **before** control characters are stripped, so `⌘⌫` — whose key has no
printable glyph and arrives as U+0008 — is a chord here rather than an absence. What it cannot see is
an item macOS keys through `AXMenuItemCmdVirtualKey` alone, which the walk does not collect; those
report no command character and are **counted out loud as skipped** rather than folded into the pass.
Two denominators are asserted too (≥30 items, ≥15 distinct chords), because a walk that collapsed to
one item would satisfy both assertions while measuring nothing.

Green on the shipped build:

    ok — all 59 menu items carry 59 distinct menu/title pairs — none is declared twice
    ok — the 36 chords read are on one item each (23 item(s) carry no command character)

**The arm, and the part worth reading is what stayed green.** `CommandGroup(replacing: .appSettings)`
with a `SettingsLink` was put back — the exact block M15 removed — and both configurations rebuilt:

    ok — every one of the 34 inventoried commands is in the menu bar
    ok — no command in the menu bar is unaccounted for
      declared 2 times: MCP Router / Settings…
      ⌘, is on 2 items: MCP Router / Settings…, MCP Router / Settings…
    FAIL: the menu bar declares one command twice, or gives one chord to two commands
    exit 1

The two pre-existing checks **passed on the mutated build**, which is the whole of BL-3: the app menu
carried two identical `Settings…` items on one chord and the standing gate said the menu bar was
complete and unaccounted-for-free. Only the counting guard went red. Reverted, rebuilt, re-run green.

## BL-4 — `planning/evidence/M15-acceptance.md` exists

Seventeen ledger rows per `UI_VERIFICATION.md` rule 2, each naming the AX path or script check that
read it, plus the two checks that came back negative recorded as **negative readings of an
insensitive instrument rather than product failures**, so the next runner does not re-post keycode 53
and get the same nothing.

## Also fixed

`ShellCommandRouter.swift:62` and `:114` said the shipped menu item *"is a `SettingsLink`"*. None is
declared anywhere: declaring the `Settings` scene is what contributes the item, and macOS performs
the actuation. Both lines now say that. The three other `SettingsLink` mentions in the tree —
`MCPRouterApp.swift:115`, `SettingsAndMenuBarTests.swift:20`, `ShellCommandRouterTests.swift:53` —
were checked and are correct: each describes the measurement that found two items, or the draft that
was rejected, not the shipped item.

---

## Gates, measured at this base

| Gate | Result | Exit | Against the brief's figure |
|---|---|---|---|
| `make lint` | `0 violations, 0 serious in 543 files`; `no-raw-design-values` 125 scanned, 84 geometry, clean | 0 | **0 over 543 — unmoved** |
| `make test` | `1710 tests in 212 suites passed` | 0 | **1710 in 212 — unmoved** |
| `scripts/acceptance/mac-shell.sh` | `54 ok lines, 0 failures` | 0 | 52/0 → **54/0**, and the two new lines are A19b |
| `scripts/acceptance/m8-settings-menubar.sh` | `35 passed, 0 failed`, frontmost `Ghostty` before and after | 0 | **35/0 — unmoved** |
| `scripts/acceptance/mock-fidelity-gate.sh settings` | 97 findings, all adjudicated | 1 | by design |
| `python3 planning/ledger-reconcile.py` | `reconciled — no findings across A, B, B-range, C, D, E, F, G, H, I, J, K, L` | 0 | see below |

**`make test` took three runs and the two that failed are recorded, not dropped.** Run 1 lost
`OAuthWireTests.cancellationResumesTheWaiter`; run 2 lost `CallbackLifecycleTests.aListenerBindsOnce`;
run 3 was green. Both are timing-bound loopback tests in `RouterCore`, neither is in this diff, and
both then ran in isolation on the same machine — **8 of 8** and **4 of 4** green. The count was
1710/212 on all three runs, failures included. The machine carried other fleet sessions at a load
average above 500 for the whole pass, which is the likeliest cause and is the honest thing to say
rather than "flake". `CallbackLifecycleTests.aListenerBindsOnce` is the same test M15's own progress
file recorded on two of eight arm runs.

**The reconciler is green, and the brief predicted it would not be.** The brief anticipated exit 1 on
check E naming `G5 (ai/g5)` and told me not to satisfy it by editing shared tracker files. It exits
**0** with no findings across all thirteen checks. The cause is that `main` moved again: it is at
`1d4ce95` *"G5's evidence is confirmed and its attribution is backwards"*, and `git branch --merged
main` now names **26** `ai/*` branches, `ai/g5` **not** among them. So there is no merged branch
without a row, and check E has nothing to report. **No shared tracker file was edited** —
`ORCHESTRATOR.md`, the ledger and every branch registry are untouched in this diff.

---

## What is open

- **Escape and arrow-key traversal are still unmeasured**, and the null-instrument argument the
  verifier accepted is unchanged. Closing them needs an instrument that can hold the keyboard without
  activating the app; `UI_VERIFICATION.md` rule 1 forbids the activation that would settle them with
  today's harness.
- **Requirement 11 is M18's** — no pane in this build opens a sheet.
- **The divergence rule is derivable, not enforced.** A citation with no `Dn` tag is visible in the
  ledger and fails nothing. Making it fail is an edit to `scripts/acceptance/mock_fidelity.py`, which
  this brief's scope excludes; it is the obvious next ratchet and belongs with whichever item next
  touches the engine.
- **`planning/plans/plan-M15.md:652` still states thirteen.** Named in the sweep's output every run,
  with its reason. The orchestrator's to take.
- **`loading` and `error` are still not in `states`**, inventoried in the manifest with M17 as owner.
- **The four plan defects stay recorded rather than fixed**, per the brief: D3's wrong failure mode,
  B1/B6's non-compiling copy-and-keep, `MeasureDump` called surface-generic when it was not, and now
  the row count above. All four are findings about the plan's author.
