# G23 — Design-of-record honesty alignment

The instruction is inverted from the obvious one: **the build's refusals are the guardrail, so the
design moves.** `DEF-042` is a defect against the design, and bringing the build into line with it
would delete four honesty guards that are covered by tests.

## What the build refuses, measured

Four refusals, each a named constant with a test over it. None of them changed on this branch.

| Refusal | Named at | Test |
|---|---|---|
| Run counts and evaluation on Skills | `public static let observationFooter`, `app/Sources/MCPRouterKit/Skills/SkillPresentation.swift:69` at `34cde4f` | `#expect(SkillPresentation.observationFooter.contains("never reaches the router"))`, `app/Tests/MCPRouterKitTests/SkillPresentationStateTests.swift:185` at `34cde4f` |
| No model-graded evaluation, permanently | `public static let evalsSubtitle =`, `app/Sources/MCPRouterKit/Checks/CheckCopy.swift:181` at `34cde4f` | `#expect(CheckCopy.evalsSubtitle.contains("No model-graded evaluation exists in this product"))`, `app/Tests/MCPRouterKitTests/CheckTests.swift:188` at `34cde4f` |
| What a check is not | `public static let evalsFooter =`, `app/Sources/MCPRouterKit/Checks/CheckCopy.swift:185` at `34cde4f` | — |
| No trend or velocity on Discover | `static let trendingNote = `, `app/Sources/MCPRouterKit/Registry/RegistryPresentation+Notes.swift:83` at `34cde4f` | — |

## What the design of record drew against them

`design/mcp-router-console.html`, the design of record settled 2026-08-22, still drew two of the
four. Discover already carried its refusal — `Why there is no "trending" band` — and the Servers
board carries no evaluation pill, so the console mock had already resolved half of `DEF-042` before
this branch.

- **Skills board.** A `Runs` column: one header and seven fixture cells, `86 · 142 · 31 · 57 · 12 ·
  4 · 0`, with no sentence anywhere on the board saying where the figure came from.
- **Skill inspector.** A `Use, by version` bar chart, `64 · 19 · 3`, captioned *"Every run records
  the version that was live at the time"*.
- **Checks board.** Its subtitle omitted the denial the build states permanently and even while
  loading, and it carried no equivalent of `evalsFooter`.

## What changed

The fabricated figures are removed and replaced by the build's own sentences, in the idiom the mock
already uses for the trending band. `DESIGN.md` §6 gains the table above as `(specified)`, so the
ruling is readable before either mock is.

The superseded `design/mocks/prototype.html` is **governed by that table rather than re-cut**, and
that is a decision. Re-cutting it moves two denominators keyed to it — eleven surfaces' control
lists in `planning/test-campaign/evidence/design-controls.json`, and the whole in-design half of
the vocabulary vector in `planning/test-campaign/bin/vocab-differential.py`. Its own source records
why prose inside it is not the fix either: *"the vocabulary differential greps this file for
control names"*, `design/mocks/prototype.html:901` at `34cde4f`.

`planning/test-campaign/evidence/design-controls.json` named the **prototype** as `designOfRecord`
and the console as `secondSource` — the two the wrong way round, while its own
`secondSourceReason` field quoted the Contract correctly. Its generator justified that on
`campaign.json` naming the prototype, which `campaign.json` has not done since 2026-08-22. Both are
corrected; the harvested `surfaces` object is byte-identical, which is asserted rather than claimed.

## Measurement, through the mock's own census

Not a reading of the diff. `scripts/acceptance/mock-affordances.py` derives the inventory from the
mock, so a removed row leaves the census rather than a spreadsheet. Base is `HEAD` at `34cde4f`.

| Frame | affordance | covered | elements | uninventoried |
|---|---|---|---|---|
| `b-skills v-ideal` base | 77 | 131 | 269 | 20 |
| `b-skills v-ideal` after | 78 | 124 | 247 | **13** |
| `b-checks v-ideal` base | 35 | 77 | 118 | 0 |
| `b-checks v-ideal` after | 36 | 77 | 119 | 0 |

Seven uninventoried strings left the Skills frame and **none entered**: `64`, `19`, `3`, their three
version labels, and the caption. The one sentence that replaced them is a `callout`, so it enters
as an affordance rather than as unmeasured text — the first draft used a `small tert` div and
scored `uninventoried 14`, which is why the element class is what it is.

`design-controls.json`: `surfaces` compares equal to `HEAD`'s, 14 surfaces; three header keys moved.

## Gates

Run whole, in the worktree, after `scripts/worktree-preflight.sh` and `npm run build` (`make lint`
depends on `tools`, which refuses to run while `dist/index.js` is missing — *"A skip is not a
pass"*).

| Gate | Exit |
|---|---|
| `make test` — `Test run with 2084 tests in 264 suites passed` | **0** |
| `python3 planning/citation-gate.py` — `control 0 · blocking 0 · ratchet 0`, over 1773 scanned files | **0** |
| `python3 planning/evidence-citation-gate.py` | **0** |
| `mock-affordances.py` over `b-skills` and `b-checks` | **0** |
| `make lint` — every member green except one, which is not this branch's | **2** |

`make test` reports the same 2084 in 264 as `main`, so this branch moved no test.

**`make lint` exits 2 on two sweep controls that time out, and the timeout is stale rather than
this branch's.** `sweep-control-gate.py` gives each declared control 120 seconds;
`scripts/acceptance/acceptance-lanes-selftest.sh` is the control for two registry rows, and it no
longer finishes in that. Three measurements place it:

- Back-to-back on this commit, same tree: one run exited **0** at *"13 arms, all held"*, the next
  exited **1** with 3 assertions failed. Non-deterministic, so not a property of the branch.
- Timed here: **3:55 wall at 5% CPU**, so 95% of it is I/O wait rather than work.
- Timed from the internal-disk checkout at `5ceef5d`, which does not carry this branch: **2:57 wall
  at 8% CPU, exit 0, 13 arms all held.** It blows the 120-second budget there too.

Its own registry row, added `2026-08-27`, records the runtime it was registered at: *"It runs the
same 19 seconds as the selftest's own row"*. It is now roughly nine times that on both disks, so
`make lint` cannot reach exit 0 on any tree in this repository until either the script or the
budget moves. Filed here rather than worked around; the branch does not touch
`scripts/acceptance/`, and this bundle's commit changes five files, none of them in that directory.

Every other member was observed green at this commit, including a full-coverage citation-gate run —
the denominator is checked, because a degraded run of the same gate reported `ratchet 0` having
scanned **781** files with **1249 skipped as non-text**, against the healthy **1773 / 256**. A green
over a ninth of the corpus reads identically to a green over all of it, so the scan figure is
quoted rather than the verdict alone.

`git status` after every run shows a clean tree, so no gate wrote to it.

## What this branch does not do

- **`DEF-042` is not closed in either registry.** Its claim is false of the design of record at this
  tree, but the row is carried twice with two different vocabularies —
  `planning/test-campaign/defects.in.json` has it `open-owner` among 19 defects, and
  `planning/test-campaign/inventory.json` has it `open · owner-decision` among 61 — and the pass
  that found it (the design-size fidelity witness pass) has not been re-run here. Guessing the
  closing word without re-measuring is the failure the registry exists to prevent, so the status is
  left for the campaign owner with this bundle as the evidence.
- **The prototype is unchanged**, deliberately, for the reason recorded in `DESIGN.md` §6.
- **Settings.** The build carries a `Control token` group, `public static let controlTokenGroup`,
  `app/Sources/MCPRouterKit/Shell/SettingsPaneCopy.swift:26` at `34cde4f`, that the design of record
  draws on no pane. That is the design trailing the build rather than an honesty violation, so it is
  named here and not drawn.

## Environment

The worktree lives on `/Volumes/LLMs`, reached through the `.worktrees` symlink. That volume became
unreadable to this session for roughly twenty minutes — `Operation not permitted` on every open and
every directory listing, while `stat` and the mount itself stayed healthy — and then flapped for the
rest of the run, taking `git status` and several reads down with it. Both long gate runs were
started only after sampling thirty consecutive successful accesses, because a dropout mid-run
reports as a gate failure rather than as an I/O failure. Every worktree in `git worktree list` is on
that volume, including the ones spelled under `/Users`, so this is a fleet-wide exposure rather than
this branch's. It is also what makes the scan-denominator check above load-bearing: the failure mode
is a gate reading fewer files and reporting clean, not a gate erroring.
