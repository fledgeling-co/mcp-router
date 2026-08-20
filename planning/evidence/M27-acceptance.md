# M27 — acceptance evidence

`The sidebar foot's loopback readout and the child-process label` · branch `ai/m27` ·
worktree `.worktrees/M27`
Brief `planning/features-to-triage/M27-sidebar-foot-readout.md` ·
Design of record `design/mocks/prototype.html` (amended here) · `DESIGN.md` §2, *The sidebar foot*

Append to this file, never rewrite it. Read it **before** testing anything: if a row exists and
`git diff <that SHA>..HEAD` does not touch the files behind it, that row *is* the evidence, and the
right thing to do is skip the check and say so.

---

## What changed under which screen

Two elements, both in the **shared sidebar wrapper** — so the surface is SURF-001, the shell, and
the predicate has to hold on all eight destinations rather than on one. Nothing on any board's
content zone changed. `SettingsPresentation.RouterFacts.endpoint` was re-pointed at the shared
`LoopbackAddress` composition and its rendered string is unchanged, which the unit lane asserts
(`http://127.0.0.1:9999/mcp` for port 9999).

**Not re-verified, and why.** The eight boards, the menu bar, the keyboard, the window frame and
restoration are M1's, M3's and M8's; this branch touches none of the files behind them. Their
evidence is `planning/evidence/M1-acceptance.md`, `M3-acceptance.md` and `M8-acceptance.md`, and
re-running them against unchanged code has one possible outcome.

## The rendered lane

`scripts/acceptance/mac-shell.sh`, extended rather than duplicated: the two new assertions ride the
**existing** eight-destination walk, so the pass is still one launch, one sweep, quit. The app is
launched with `open -g`, never activated, and every read is an accessibility query by pid.

Two things about the assertion are worth the next runner's attention:

- **It is bound to the sidebar by geometry**, not by presence anywhere in the window. Settings draws
  `127.0.0.1` in its own Endpoint row at x≈942, which is the content zone; the campaign's own
  differential recorded exactly that. A window-wide grep would have reported the foot line present
  on the one board that never had it.
- **The expected port is read out of `Control/Fixtures/servers.json`**, not typed. The line under
  test is the one whose whole defect class is a hard-coded port, so a hard-coded port in its oracle
  would be the same mistake one layer out.

| Screen | How verified | Commit | Result |
|---|---|---|---|
| SURF-001, the shell, on all eight destinations | `scripts/acceptance/mac-shell.sh` — the eight-destination walk. Per board: `sidebar_address` over the AX dump, bounded left by the sidebar outline's x, right by its trailing edge, and below by the `Child processes` label's y; whole-field match on `^(Router endpoint, )?127\.0\.0\.1:[0-9]+$` | `c84ddc8` | **8 of 8** read `127.0.0.1:8971`, Settings included — the board whose own Endpoint row at x≈942 is what a window-wide grep would have matched |
| The count card's label, all eight destinations | Same walk. Substring `Child processes` inside the same sidebar bounds; its y is then the bound the address is held below | `c84ddc8` | **8 of 8**. It was 0 of 9 when the campaign measured it |
| The observed port is the served one | The oracle reads which recording `FixtureControlAPIClient` decodes out of the client's own source, then that file's `port` | `c84ddc8` | `servers-pending-auth.json`, port **8971**, printed by the run. The script previously read `servers.json` — a file the app does not serve |
| The foot's fourth state — offline | Second launch, `MCPROUTER_SCENARIO=offline`. Two readers: the canonical one, and `sidebar_anything_endpoint_shaped` for anything host-and-port shaped. Plus the label's absence | `c84ddc8` | **Nothing endpoint-shaped in the sidebar, and no label.** `"The router isn't running"` verbatim, no counts |
| The foot's fourth state — unauthorized | As above. The router answers 401, so the poll failed and no port was ever observed | `c84ddc8` | **Nothing endpoint-shaped, and no label.** `"This app isn't authorised to talk to the router"` verbatim |
| A35's readout label, still in the tree | Pre-existing assertion: an element whose whole text matches `^[0-9]+ of [0-9]+ declared servers running$` | `c84ddc8` | **Pass** — and it is what refused `.combine`. See below |
| Invisibility | `frontmost` recorded at start and asserted unchanged; `check_invisible` after each block | `c84ddc8` | The app never came to the front. The run's own closing line: *"all of it without once coming to the front"* |

Whole run: **exit 0**, `planning/evidence/M27/mac-shell-run.txt`.

## What the run refused, which is the part worth reading — **SUPERSEDED, see the section below**

**`.accessibilityElement(children: .combine)` on the count row failed A35's assertion, measured.**
Two out-of-family reviews asked for it and the reasoning was good — one element, one VoiceOver
stop, the label joined to the reading it heads. A35's gate requires an element whose *whole* text is
`N of M declared servers running`; a combined row publishes `Child processes, N of M …` and the run
went red at *"the readout's accessibility label is not in the tree"*. The row therefore merges into
neither one element nor none: `.ignore` (what shipped) discards the label, `.combine` breaks A35,
and leaving it alone publishes both as self-describing stops. `SidebarFootTests` pins all three.

Three defensible forms, one survivor, and only the running app could say which.

## The captures, and what binds them to what they show

`planning/evidence/M27/captures.tsv` carries a row per destination: the destination, the
**CGWindowID** the capture was taken by, the bundle path the pid was executing, the exact string the
foot assertion read out of the accessibility tree in that same iteration, the file name, and the
timestamp. Captures are by window id rather than by screen rectangle, which is the only route that
photographs *this* window rather than whatever sits over a region.

Two of the eight are committed — `sidebar-foot-Activity.png` (the ordinary case) and
`sidebar-foot-Settings.png` (the board that draws its own `127.0.0.1` in the content zone, so a
naive check would have called the foot present there when it was not). The other six were captured
in the same run and are in the tsv; they are not committed because eight window captures is 1.9MB
and this directory has no precedent for images.

## The environment, recorded rather than hidden

The first two attempts at this run were lost to machine load, not to the product. Load average was
**170 to 295** throughout, from other sessions on this machine: the first run failed at
*"the app is running and put no window on screen within 20 seconds"*, and a hand check afterwards
found the same build launching and drawing a window fine. The passing run raised
`MAC_APP_WAIT_{GONE,START,WINDOW}_TICKS` to 400 (100s). That changes no assertion — those bounds
only decide whether an environment stall is reported as a product failure, which is what the
script's own failure text says it is claiming.

---

## Correction, 2026-08-21 — the row combines after all, and A35 was the thing that was wrong

The section above records `.combine` as refused by the on-glass gate, and shipped the unmerged row
on that basis. **That reasoning was wrong and the shipped form was worse for a VoiceOver reader.**
Two out-of-family lanes read the delta — `gpt-5.6-sol` (OpenAI) and `gemini-3.7-flash-high`
(Google) — and reached the same finding independently, both at their top severity: the unmerged row
makes every screen-reader user traverse two stops for one metric, the first of which —
`Child processes` — carries no value at all, and the second of which names the quantity differently
(`declared servers`). A third lane, `grok-4.6` (xAI), stalled after reading the wrong tree and
returned no findings; it is recorded as **inconclusive**, not as a pass.

The refutation is in A35's own text, thirty lines above the assertion that refused the merge.
`mac-shell.sh:273-278` matches the destination rows as a **prefix**, and says why: *"a row that
carries a badge announces it as part of one sentence — 'Servers, 1 need attention' rather than
'Servers' and a loose number. That is the point of the label, so the assertion has to allow for
it."* The readout's line at `:306` was anchored `^…$` instead. It could afford to be, because this
row **had no label to combine with** — that missing label is the defect M27 exists to fix. So the
anchor recorded the absence of a combined form rather than a decision against one, and treating it
as a contract let a gate written before the element existed pick the element's shape.

Widened to A35's own stated tolerance rather than obeyed:
`^(Child processes, )?[0-9]+ of [0-9]+ declared servers running$`. The sentence is still matched
whole, so a row announcing a bare number still fails — this is wider, not weaker.

**And the guard that was supposed to pin all three forms could not fail.** Both reviewing families
found it: `components(separatedBy:)` never returns an empty array, so the `.first` / `.last` reads
under every `#require` were non-`nil` even when the delimiter was absent entirely, and each
diagnostic string was unreachable. Splitting on the first member-indented `}` was the second half:
correct today by layout, silently truncating the body to something a `!contains(…)` assertion passes
against the moment a nested closure closes at that indent. Replaced with a brace-balanced
`ShellTestSupport.declarationBody(of:in:)` that throws on a missing marker, on an ambiguous one, and
on an unclosed one, with `theDeclarationReaderCannotPassVacuously` exercising all three.

| Screen | How verified | Commit | Result |
|---|---|---|---|

### A fourth form, considered and not taken

`grok-4.6` — the lane that returned last, after the change above was already made — reached the
same verdict on A35 independently, which makes it **three families of three** agreeing that the
anchored line was the stale half. It then proposed a form none of the other lanes named: one
element carrying `.accessibilityLabel("Child processes")` and
`.accessibilityValue("N of M declared servers running")`. That is arguably the better AX modelling
of a label-and-number pair, and its stated advantage is real — the gate's column map puts AXTitle,
AXValue and AXDescription on separate fields, so A35 would match the value field with **no widening
at all**, and the whole question of editing another item's assertion would not arise.

Not taken, and the reason is recorded rather than assumed away: its advantage rests on SwiftUI
mapping `.accessibilityValue` to AXValue, which that lane flagged as the one speculative part of its
own finding. The shipped `.combine` reaches the same single stop with the same spoken sentence
through a documented modifier. And A35's line needed the widening on its own merits — all three
lanes called it stale independently of which product form replaced it — so the edit is a wrong gate
corrected rather than a right gate bent to fit, which is the distinction `SWIFT_PRACTICES.md` §7
draws. If a later item measures the AXValue mapping on glass, this is the form to revisit.
