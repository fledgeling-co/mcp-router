# M27 — the sidebar foot's loopback readout is absent, and the child-process card lost its label

**Category:** mac · **Found:** 2026-08-20, by the campaign's design differential
**Defect:** DEF-043 · **Surfaces:** SURF-001 (shell, all boards) · **Related:** M23, DEF-042

## What was measured

`design/mocks/prototype.html:681` emits, from inside the shared sidebar wrapper:

```html
<div class="sfoot"><span class="dot live"></span>127.0.0.1:8879</div>
```

Because it is in the wrapper, the design paints a live-dot loopback readout at the foot of
the sidebar on **every** board. The build paints none. Across 9 accessibility dumps taken
at 1156×680 — one per destination — the only two `127.0.0.1` hits are the Settings board's
own Endpoint row, at window-relative `x=942`, which is the content area rather than the
sidebar.

Separately, `prototype.html:699-700` labels the sidebar-foot card `Child processes` over a
large numeral and `of N declared`. The build draws the count as an unlabelled, uncarded row
reading `Running   1 of 4`, and the string `Child processes` appears in **0 of 9** dumps.
The number survives; the card and its label do not.

## Why this is a brief rather than a closed defect

The loopback address is exactly the kind of number ORCHESTRATOR.md's honesty rule governs —
*no number is displayed that the router does not observe* — so its removal may have been
deliberate, and DEF-042 records four other places where the build is the correct half of a
design divergence. What is not deliberate either way is that nothing in the campaign had
checked. The measurement above is the first time either element was looked for.

## What to deliver

Settle each of the two independently, and say which way it went and why.

1. **The loopback readout.** Either restore it at the foot of the shared sidebar, showing
   the endpoint the app is actually talking to and a dot reflecting observed reachability
   rather than a constant — or record in `DESIGN.md` that it is deliberately absent and why,
   and annotate `prototype.html:681` as superseded. A readout that hard-codes `:8879` while
   the app talks to a different port would be the honesty rule broken in the other
   direction, so if it is restored, it reads from the same source the Settings Endpoint row
   reads.
2. **The child-process label.** The count is already correct and on screen. Give it the
   design's label and card, or record that the bare row is the intended treatment. This one
   carries no honesty question — `Child processes` names what the number already is — so
   absent a reason to differ, the design wins.

Add on-glass coverage for whichever way each goes, so the next differential compares against
a settled answer. The campaign's Mac lane captures at 980×620 through
`scripts/acceptance/mac-app.sh`; the shell is SURF-001 and its predicate must hold on every
destination, since that is what "in the shared wrapper" means.

## Scope

These two elements of the sidebar foot, and nothing else on the shell. The campaign's
differential names other divergences on these boards; they belong to DEF-042 and to M23's
mock-to-SwiftUI contract, not here. If you find a third divergence in the sidebar while
working, record it and leave it.

**Do not activate MCPRouter to take a capture by hand.** The campaign's standing constraint
is that this lane never activates the app; the capture script is the supported route.

---

## What was delivered — 2026-08-21, branch `ai/m27`

Both elements settled independently, both restored, and one further divergence recorded and left.

### 1 · The loopback readout — restored, without its dot

`SidebarFoot` draws `127.0.0.1:<port>` at the foot of the shared sidebar wrapper, so it is on every
board rather than one. Two things about it are decisions rather than transcription:

**The port is the observed one.** `LoopbackFoot.reading(for:)` takes it from
`ServerStateTracker.TrackerState.port` — the port the router answered on — which is the same value
`SettingsPresentation.RouterFacts.endpoint` reads. Both now compose through one `LoopbackAddress`,
so the two surfaces cannot drift, and `addressIsSpelledInOnePlace` fails the build if a third
surface writes its own. The mock's literal `:8879` is what the honesty rule looks like pointed
outward: the fixture router answers on **8971**, so a build carrying the literal would tell a user
who moved the port to reach for the wrong one. `theObservedPortIsTheOneShown` drives that: the line
reads the fixture's port and is asserted not to end in `:8879`.

**There is no dot, and that is the deviation.** The brief asked for "a dot reflecting observed
reachability". Two out-of-family reviews — `gemini-3.7-flash-high` and `grok-4.6` — independently
refused the mock's `--live` one, and on the same ground: `DESIGN.md` §2 gives `--live` exactly one
meaning, *a child process is running*, and it is already spent correctly on the count in the card
directly above. A green dot beside a card reading `0 of 4` paints that meaning where nothing is
running. A neutral dot was the remaining option and fails §6 instead — a signal meaning "answering"
needs a word for that state, `ControlAPIError` already owns that word, and "not answering" would be
**false for `.unauthorized`**, where the router answers 401 and the poll still fails. So the foot
says where the app is pointed and the card above says how the router is. Recorded in `DESIGN.md` §2
under *The sidebar foot*, and the mock is amended to match.

Its four states are in `DESIGN.md` and driven by tests: skeleton before the first answer, the
address once the router has answered, the address unchanged through a failed refresh (the port is
documented as surviving a failure), and **nothing at all — no line, no divider — when nothing has
ever answered**, because there is no address to show and the card above is already carrying that
state verbatim.

### 2 · The child-process label — the design wins, as the brief expected

`ReadoutCopy.runningLabel` → `childProcessesLabel = "Child processes"`, and the readout now sits in
the card `prototype.html` draws: `--f3` plate, `--line` hairline, §2's card radius, its own margins.
The full-bleed divider above it is gone — a rule above a bordered plate is two separations doing one
job — and the divider now sits where the mock puts it, above the foot line. The old label was also
colliding with the sidebar's own `Running` group header two rows above, which is a different thing.

### 3 · The third divergence, recorded and left

The mock draws the count as a 26px display numeral over `of N declared`; the build draws a
label-left / value-right row and still does. That is a type and density decision rather than a
missing element, so it converts under **M23**'s mock-to-SwiftUI contract with the rest of the board.
`grok-4.6` argued the card should land with the numeral or not at all; the brief scopes this item to
the label and the card, and to recording rather than fixing a third divergence, so the objection is
logged here rather than acted on.

### Coverage

- `app/Tests/MCPRouterKitTests/LoopbackReadoutTests.swift` — one composition for both surfaces, the
  observed port, the four states, and no status wording.
- `app/Tests/MCPRouterUITests/SidebarFootTests.swift` — the running model's foot, the offline
  model's absence, no indicator colour in the file, the card, the label, the single divider.
- `scripts/acceptance/mac-shell.sh` — on glass, inside the existing single-launch walk: the foot's
  address and the `Child processes` label are asserted **on all eight destinations**, bound to the
  sidebar by geometry so Settings' own Endpoint row at x≈942 cannot satisfy it, with the expected
  port read out of the fixture recording rather than typed. The offline lane asserts the line's
  absence.
