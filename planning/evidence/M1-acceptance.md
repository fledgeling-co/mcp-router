# M1 — acceptance evidence

`Mac window shell, menu bar, keyboard` · branch `ai/m1` · worktree `.worktrees/M1`
Spec `planning/specs/spec-M1.md` (A1–A37) · Plan `planning/plans/plan-M1.md`

Append to this file, never rewrite it. Read it **before** testing anything: if a row exists and
`git diff <that SHA>..HEAD` does not touch the files behind it, that row *is* the evidence, and the
right thing to do is skip the check and say so.

---

## How this was verified, and why it looks different from the earlier runs

**Every assertion below was taken with the app in the background.** M1 has been through five runs,
and the previous four drove the shell by activating it — `open` rather than `open -g`, and
`tell application … to activate` before every keystroke, because a System Events keystroke only
reaches a frontmost app. That is an honest edit-run loop and it still took the user's screen on
every cycle, which `planning/practices/UI_VERIFICATION.md` rule 1 forbids.

So the harness was rebuilt rather than the testing reduced. `scripts/acceptance/axkit.swift` drives
the app over four routes, each **measured** on 2026-08-14 with Ghostty frontmost throughout:

| What the gate needs | Background-safe route | What was measured |
|---|---|---|
| read the window and the menu bar | AX tree by pid | all six menus, every item, every shortcut and every help tag readable with **no menu opened** |
| a bare `Space` / `Return` / `Esc` | `CGEvent.postToPid` | the probe recorded each key while the app was inactive |
| move the sidebar selection | set `AXSelectedRows` on the outline | title followed, and the outline reported exactly one selected row |
| scroll the content zone | set the scroll bar's `AXValue` | 94% of one row at the content's top edge changed |
| move and resize the window | set `AXPosition` / `AXSize` | frame read back exactly as set |
| quit | `NSRunningApplication.terminate()` | graceful, and it does not activate |

**The gate now asserts its own invisibility.** `check_invisible` runs after every phase and fails if
MCP Router is ever the frontmost application. It fired twice while being written — once on a
too-strict first version that failed when the *user* switched to Chrome, which is why the invariant
is "this app never comes to the front" rather than "the frontmost app never changes".

**One route does not work in the background, and it is recorded rather than papered over.**
`AXUIElementPerformAction(menuItem, AXPress)` returns `.success` and does nothing, and a `⌘2` posted
to the process does the same — because a menu command reaches its window through `@FocusedValue` and
an inactive app has no focused scene. Rather than activate the app to prove one clause, the decision
that needed proving moved into `ShellCommandRouter`, where a unit test reaches it. See A23 below.

---

## Screens verified — at `8858864`

One launch per pass, backgrounded, quit at the end. The Mac shell is one screen with one sidebar,
one menu bar and one content zone; there is no second screen in this item to skip.

| Screen | How verified | Commit | Result |
|---|---|---|---|
| Shell window — three zones | `scripts/acceptance/mac-shell.sh`: `AXOutline` width, `AXToolbar` height and the chrome band above the content, each compared to `MetricToken.sidebar/.unifiedToolbar` read out of the source | `8858864` | pass — 256.0 / 52.0 / 52.0 |
| Sidebar — rows | modal `AXRow` height over the 8 destination rows, checked against `DESIGN.md` §2's documented sizes parsed out of the document | `8858864` | pass — 8 rows at 32.0pt, which §2 documents |
| Sidebar — screen-reader text | AX walk: all 8 destinations, both group headers in sentence case, the readout's sentence | `8858864` | pass |
| Sidebar — badges | AX walk: `Servers, N need attention` and `Cleanup, N never used` present; `Skills` and `Inbox` asserted to carry **no** badge | `8858864` | pass |
| Toolbar title | `AXTitle` of the window is a destination name, never the app's | `8858864` | pass — "Evals" |
| Menu bar — six menus | AX walk of `AXMenuBar`, Apple menu excluded by name | `8858864` | pass — MCP Router / File / Edit / View / Window / Help |
| Menu bar — completeness | 34 inventory rows parsed out of `spec-M1.md`, compared **both ways** against the running menu bar | `8858864` | pass — 0 missing, 0 unlisted |
| Menu bar — shortcuts | `AXMenuItemCmdChar` + `AXMenuItemCmdModifiers` decoded and compared to the inventory's chord | `8858864` | pass — 26 checked |
| Menu bar — disabled reasons | 7 `surfaceAbsent` commands present, reporting disabled, carrying `AXHelp` = the reason read out of `MenuCommand.swift` | `8858864` | **superseded — see `M11-acceptance.md`.** Green as measured, and measured against the wrong oracle: the count of 7 comes from the inventory's *"Availability in M1"* column, which is the answer with **no board installed**. It was already stale here — M3 and M4 had installed the Servers and Skills boards, so the shipped app's answer was 4, not 7 |
| Menu bar — enabled commands | 12 app-declared enabled commands report themselves enabled | `8858864` | **superseded — see `M11-acceptance.md`.** The check covered only `View/*`, `Help/*` and `MCP Router/Settings`, a hand-written list that reached 13 of the 20 commands the app declares and excluded every File and Edit item — which is exactly where the defect M11 found was sitting |
| Selection + title | `AXSelectedRows` set for Servers / Discover / Settings / Activity; exactly one row reports selected and the title follows | `8858864` | pass |
| Keyboard — bare keys | `Space`, `Return`, `Esc` posted to the pid; the content-zone probe reports each | `8858864` | pass |
| Scroll edge | window-scoped `screencapture -l<id>` before and after a real scroll, row-wise diff of the content's top band | `8858864` | pass — 0.943 of one row changed |
| Restoration | frame moved to 180,140,980,620 and Evals selected; terminated; relaunched; both compared | `8858864` | pass |
| Release bundle | scaffold sentinel required present while boards remain; Debug key probe required absent | `8858864` | pass |
| Invisibility | frontmost application sampled after every phase | `8858864` | pass — MCP Router never frontmost |

### What was NOT verified, and why — read this before assuming a gap

| Not verified | Why | Where the evidence is instead |
|---|---|---|
| A ⌘-digit *keystroke* moving the selection end to end | Needs the app frontmost: a menu command reaches its window through `@FocusedValue`, which is nil for an inactive app. Proving it would take the user's screen, which rule 1 forbids | A23's four links below, each measured separately |
| The other screens of the app | They do not exist. `BoardRegistry.installed` is empty and M2–M8 own the boards | — |
| iOS | M1 is macOS-only | I1 |

---

## A23, decomposed — because one link could not be driven honestly

A23 reads "⌘1–⌘7 and ⌘, change the **selected destination**, not merely the title: the sidebar row
reports itself selected and the toolbar title follows it". That is a chain, and each link is
evidenced where it can actually be measured rather than where it is convenient:

| Link | Claim | Evidence | Result |
|---|---|---|---|
| 1 | each chord is bound to the menu item the inventory names | AX read of the **running** menu bar's `AXMenuItemCmdChar` + modifiers, compared to the spec's table | pass, 26 chords |
| 2 | macOS dispatches a ⌘-chord to this process | `⌘H` posted to the pid while inactive; the app hid | pass |
| 3 | the item's operation is a selection | `ShellCommandRouterTests`, exhaustive over `MenuCommand` in both directions | pass, 8 tests |
| 4 | a selection moves the row's selected state and the title | `AXSelectedRows` set on the running app, both read back | pass, 4 destinations |

The residual assumption, stated plainly: **SwiftUI invokes a `Button`'s action when its key
equivalent fires.** That is framework behaviour, link 2 shows the keystroke reaches the app, and link
3 shows what the action does. Before this run, link 3 lived in a closure inside `app/MCPRouter` —
which is not a SwiftPM target — so it had no evidence lane at all except a drive that needed the
front.

---

## Red-green, by mutation — verified at `8858864`

`SWIFT_PRACTICES.md` §7: a test that has never failed is not known to work. Each mutation was applied
to the production source, the named suite run, and the source restored.

| Mutation | Guard that fired | Result |
|---|---|---|
| `⌘,` maps to `.select(.activity)` instead of `.settings` | `ShellCommandRouterTests` | RED (2 issues) |
| the Scene's items go back to `model?.select(.activity)` closures | `assemblyCarriesNoOperation` | RED |
| a stored frame is accepted on bare intersection instead of half its area | `barelyOverlappingIsRejected`, `theMeasuredFailureIsRejected` | RED |
| `save(frame:)` writes nothing | `theStoreRoundTrips` | RED |

**The strongest red-green here was not a mutation — it was the real defect.** A33's assertion in
`mac-shell.sh` **failed** against the previous frame mechanism on this machine, at this commit's
parent, and passes against the new one. That is a gate proven by the bug it caught rather than by an
injected one.

---

## The A33 defect, recorded

SwiftUI's `WindowGroup` gives its window an implicit NSWindow frame-autosave name, and an earlier
revision of this item relied on it and removed the bridge it had written. Re-measured across several
runs on 2026-08-14, that does not hold:

- a programmatic move updated the implicit autosave key on one run and left it at the launch frame on
  the next two;
- the frame the app came back at was one from an **earlier session**, not the last one;
- one relaunch restored the window to `-266,-1172` — off every attached screen, from a frame saved
  while an external display was attached. A window that cannot be seen cannot be moved back.

The name is fragile by construction too: it embeds the root view's *type signature*, so wrapping one
more modifier around `ShellWindow` silently starts a different saved window.

The app now stores its own frame in the same `UserDefaults` as the selected destination, written on
`didMove` and `didResize`, applied once on first appearance, and only when
`ShellFrameRestoration.isUsable` says at least half the window lands on some screen's visible frame.
`ShellFrameRestorationTests` asserts the rules, including the `-266,-1172` frame as itself.

---

## Where this gate is weaker than it looks — stated, not hidden

Three assertions are worth reading sceptically, and each is paired with what carries the rest of the
weight. Naming them here is cheaper than a later reader discovering them and distrusting the whole
file.

**A34's rendered half asserts a signature, not the separator itself.** The hairline is
`accessibilityHidden`, so there is nothing to read; what is measured is that a near-full-width row of
pixels at the very top of the content zone renders differently after a scroll than before. A future
board whose first row is full-width could in principle satisfy that by scrolling under the top edge.
The clause is met by the composition the spec asks for: the *derived* half is
`scrollEdgeThreshold` and `rubberBandingNeverShowsTheSeparator`, which drive `ScrollEdgeState` from
both sides of its threshold, and the rendered half only has to show that something appears there.

**A22's "reports itself disabled" is weaker on a background app than on a frontmost one**, because
macOS dims many of its own items — Close, Undo, Minimize — while an app is inactive. Two things
separate the app's own disabled commands from that artefact, and both are asserted: only the app's
commands carry the reason string in `AXHelp`, and the app's twelve *enabled* commands report
themselves enabled in the same walk, which they could not if inactivity were dimming everything.

**`check_invisible` samples the frontmost application at phase boundaries, not continuously.** A
flash to the front between two samples would go unseen. What makes that unlikely rather than merely
unchecked is that every route the gate uses is a documented non-activating API and the only launch is
`open -g`; the sampling is a backstop against a route turning out to activate, not the primary
mechanism.


| Gate | Command | Result |
|---|---|---|
| build (SwiftPM) | `cd app && swift build` | exit 0 |
| build (Debug app) | `make build-mac` | BUILD SUCCEEDED |
| build (Release app) | `make build-mac-release` | BUILD SUCCEEDED |
| tests | `cd app && swift test` | 551 tests, 77 suites, 0 failures |
| format + lint | `make lint` | 0 violations in 175 files, 0/177 require formatting |
| design values | `scripts/lint/no-raw-design-values.sh` | clean — 21 files scanned, 11 shell files under the extra rules |
| wire codable | `scripts/lint/no-wire-codable.sh` | clean |
| acceptance | `scripts/acceptance/mac-shell.sh` | exit 0, 32 assertions |

The `no-raw-design-values.sh` shell rules carry A36's boundary check: `URLSession`, `Process`,
`NSTask`, `FileManager`, `NWConnection`, `NWListener`, `CFSocket` and `socket(` are forbidden
anywhere in the shell's files, so a direct call a dependency graph cannot see is caught by a grep
that can.

## Out-of-family gate

`codex` was unavailable for this fleet: every call, down to a one-word probe, returns an
account-level usage limit that clears on 20 August, past this fleet's horizon. Recorded as
**`codex: usage limit → claude (downgrade)`**. The Phase D completeness critic was run instead as a
fresh `claude -p` opus-5 session, briefed adversarially — told to refute, and that finding nothing
would be a failed review rather than a pass.

`codex exec` **exits 0 on a usage limit**, so no gate here is keyed on its exit code; the honest
tells are the ERROR line in the log and an empty `-o` file. The weakness travels with this evidence:
every reviewer in this pipeline is now Claude auditing Claude.
