# M2 — Activity: acceptance evidence

**Append only.** One row per screen, per verification. Before testing anything, read this file: if a
screen has a row and `git diff <that SHA>..HEAD` does not touch the files behind it, that row **is**
the evidence — skip the test and say so. A screen that has genuinely never been tested still gets
tested properly, once.

**Scope discipline.** M2 changes exactly one destination's content and the shell's content-zone
routing. The other seven destinations are placeholders and are **not** driven here: an acceptance
sweep over seven identical placeholders proves that a placeholder is a placeholder. The shell's own
clauses belong to `mac-shell.sh` and are re-run only because this item changed `ContentZone`.

**Invisibility.** Every run below launched with `open -g -a`, read the accessibility tree by pid, and
posted keys with `CGEvent.postToPid`. Nothing activated the app, nothing used
`osascript … to activate`, and nothing used `screencapture -R`. Both scripts record the frontmost
application at the start and fail themselves if MCP Router is ever in front.

---

## Runs

| Screen | How it was verified | Commit | Result |
|---|---|---|---|
| Activity — populated | `scripts/acceptance/m2-activity.sh`, `MCPROUTER_SCENARIO=populated`. AX by pid: no scaffold sentinel; two `AXMenuButton`s present; window title `Activity`; **12 call rows** read off `AXButton` descriptions; a row label beginning `failed,`; a label carrying `claude · pid 51310`; the 84-character tool name complete in a label; subtitle `Showing 12 calls · since 7:12 pm · live` | `6dd480d` | **pass** |
| Activity — filters | same run. Both filters are `AXMenuButton` with `AXValue` `All sessions` / `All projects` — §3.6's "shows a value", read off the running control. With no filter set, neither `N of M` nor `Clear filters` is in the tree | `6dd480d` | **pass** |
| Activity — Space is not claimed | same run. M1's Debug key probe reported `none`, `axkit key <pid> 49` posted Space, the probe then reported `Space` — with the Activity board on screen. The board did not take it | `6dd480d` | **pass** |
| Activity — empty | `MCPROUTER_SCENARIO=empty`. `No calls yet` and `Servers stay asleep until an agent asks for one` on screen; **no** error/failed/problem/sorry language anywhere; the disabled-filter reason `Filters need calls to filter` present and containing no claim about when the router started | `6dd480d` | **pass** |
| Activity — loading | `MCPROUTER_SCENARIO=loading` (the scenario suspends `/usage` until cancelled). No `AXProgressIndicator` in the tree, skeleton label `Loading the call log` present, **zero** rows rendered while the request had not returned | `6dd480d` | **pass** |
| Activity — offline | `MCPROUTER_SCENARIO=offline`. `The router isn't running`, `Nothing is listening on the control port`, and `Start the router` — all three verbatim from `ControlAPIError`, read out of the running app | `6dd480d` | **pass** |
| Activity — unauthorised | `MCPROUTER_SCENARIO=unauthorized`. `isn't authorised to talk to the router` and `Re-pair` present — a distinct state from offline, with its own copy and its own action | `6dd480d` | **pass** |
| Activity — feed retrying | `MCPROUTER_SCENARIO=streamReconnecting`. `The live feed dropped` present; **no** `complete up to` anywhere; **no** `Reconnect now` (the ladder is still running); rows still rendered beside the banner rather than replaced | `6dd480d` | **pass** |
| Activity — feed spent | `MCPROUTER_SCENARIO=streamDisconnected`. `stopped retrying` present, `Reconnect now` present, and **no** `after N attempts` — the stream never reports a count | `6dd480d` | **pass** |
| Mac shell — regression after the `ContentZone` change | `scripts/acceptance/mac-shell.sh`, full run. M2 restructured the content zone (the board renders outside the shell's `ScrollView` and reports its own scroll geometry) and re-pointed A34 from Activity, which is no longer a placeholder, onto Servers, which is | `6dd480d`+ | **pass** — full run, exit 0. Scroll edge `#1E1E1E` at rest → `#2F2F2F` scrolled → back, on Servers. 34 menu commands, all shortcuts, all reasons. `Space` still reaches the probe. Destination and window frame restored across relaunch. `boards installed: 1 of 8`, 7 scaffolded, Release carries the placeholder honestly, Debug probe absent from Release. Ended on Ghostty — never frontmost |

## What is proven at the model rather than in the running app, and why

`↑`, `↓`, `Return` and `Esc` are **not** claimed as running-app evidence. M1's `KeyClaimProbe`
claims first responder in the content zone and swallows keycodes 49/36/53, and Debug is the only
configuration in which a fixture scenario is reachable — so the build that can be driven into these
states is the build in which the probe holds three of the four keys. Rather than disable the probe
(which would cost M1's A21 its test surface) or claim evidence the configuration cannot produce,
the key behaviour is proven at `ActivityModel` by `ActivityModelTests`:

- selection moves and clamps at both ends, and selects the newest from nothing;
- the keyboard does nothing at all on an empty board;
- `Esc` clears the selection.

`Space` **is** proven in the running app, because the probe receiving it is exactly the assertion
that the board did not claim it.

## The red-green proving pass

Each gate below was deliberately broken, watched go red, and restored. A gate that has never failed
is not known to work.

| Gate | Mutation | Result |
|---|---|---|
| B5 · row height reads the shared constant | `ActivityColumn.rowHeight` → `MetricToken.controlLarge.leadingScalar` | **red** |
| B7 · the cold mark is a drawn icon | `IconView(.frost …)` → a `Text` holding the snowflake character | **red** |
| B8 · no undeclared indicator colour | the row's mark painted `--live` on success | **red** (3 assertions) |
| B10 · identifiers stay out of the instrument voice | the tool column switched to `monospaced: true` | **red** |
| B4 · the field mapping tracks the spec's table | `case session` removed from `ActivityRowField` | **red** (7 assertions) |
| B14 · filter options are groupings | the per-option count incremented by 2 | **red** (4 assertions) |
| B22 · de-duplication by the router's identity | the id guard short-circuited | **red** (4 assertions) |
| B19 · filtering issues no request | a request counted on every filter change | **red** |
| F3 · no sentence claims the router's uptime | empty copy → "The router has been up since …" | **red** |
| F6 · no sentence claims a completeness watermark | "the newest call here is" → "the history below is complete up to" | **red** (5 assertions) |
| F7 · the given-up state names no attempt count | "stopped retrying" → "stopped after six attempts" | **red** |
| F30 · only the spent feed offers a button | `actionLabel: reconnect` added to the retrying state | **red** |

**One gate was found to be a decoration and is now real.** B5's row height had *no* test: swapping
`MetricToken.tableRows` for `controlLarge` left the suite green. `ActivityColumn.rowHeight` is now
the single value the populated row and the skeleton both draw at, and the test asserts every
`.frame(height:` in the file is that constant — so a literal, a different token, or a second
independent expression all fail. The same mutation is red now.

## Defects this pass found, which a build gate could not have

1. **The feed banner swallowed its own button.** `.accessibilityElement(children: .combine)` folded
   the banner into one static element and took `Reconnect now` with it — the only way back from a
   spent feed, gone for anyone not using a mouse. The acceptance run failed looking for the button;
   a sighted pass would have seen it drawn and moved on.
2. **An authored fixture in the recordings directory would have broken R4.**
   `scripts/acceptance/parity-fixture.sh` replays every `*.json` in `Control/Fixtures` against the
   live TypeScript reference, and `parity-manifest-check.sh` demands a manifest row per file. F4's
   immutability guard caught it here; the failure would otherwise have landed on R4.
3. **B5's gate did not exist**, above.
4. **M1's scaffold-in-Release gate reported the opposite of the truth on a partial set.** It read
   `installed: Set<Destination> = []` as "scaffolds remain" and *anything else* as "every board has
   shipped" — correct while the only reachable states were none and all. With one board of eight it
   concluded every destination had a board and failed the Release build for honestly carrying a
   placeholder that six destinations still need. It now counts both numbers and prints
   `boards installed: N of M`. The first attempt at that count was itself wrong — a `sed` *range*
   ending at `]` ran past the one-line declaration and reported 3 of 8 — which is why the parse was
   verified in isolation before another UI run was spent on it.

## Notes on the harness

- **Accessibility identifiers are not usable on this surface.** SwiftUI propagates the nearest
  ancestor's identifier down the subtree, so every descendant of the shell's content zone reports
  `content` and the board's own per-element identifiers never reach the tree. Measured 2026-08-14.
  The script keys off role, title and value instead — which for §3.6 is the stronger evidence: an
  `AXMenuButton` whose `AXValue` is `All sessions` *is* "a pop-up button showing a value".
- A row's `accessibilityLabel` reaches the tree as **AXDescription**, not AXTitle.
- `RegistryEnrichmentTests`' "an absolute path discards the base's own path" failed once mid-session
  and passed on re-run at the same commit, both with and without this branch's changes. Recorded as
  an observed flake in a merged suite, not as an M2 finding and not silently ignored.
- The first exploratory probe of the frontmost app once read `MCP Router` after a manual
  `open -g` + AX read. It did not reproduce across a staged re-measurement (Ghostty frontmost at
  launch, after selecting a scaffold, and after selecting the board), and both scripts assert
  invisibility at every step and passed. Recorded because an unreproduced observation about the one
  rule that must be believed is worth writing down rather than dropping.

---

# Second pass — after the two-sources gap-fix (2026-08-14)

A gap-fix over the board that had already passed everything above found nine defects in code that
compiled, passed its whole suite and had been driven through the full run recorded at `6dd480d`. The
board's rendered tree changed as a result, so every Activity row above is superseded by the run
below rather than carried forward. The shell run is re-done too, because `ShellWindow.swift` — a
shared file — changed.

## What the gap-fix changed, and why each one needed a UI re-run

| Defect | What a user would have seen |
|---|---|
| `merge()` concatenated response-then-held | On a router returning a full 500-record ring, **every record the stream had delivered** fell off the end of the concatenation and was truncated away. A reconnect on a busy router discarded exactly the half it was reloading to preserve |
| `load()` then `subscribe()` ran in series | Every call the router recorded between the snapshot returning and the socket opening was lost — too old for the stream, too new for the response, and invisible on the board forever. Now `start()` runs both concurrently and the id guard absorbs the overlap |
| `reconnect()` was re-entrant | Two taps stacked two live subscription loops writing into one model |
| `reconnect()` cleared the phase first | A reload that then failed left `condition` on `.populated`: a stale list, a subtitle reading "connecting", no banner, and no way back |
| `historyUnavailable` was gated on `phase == .live` | Same stale-board outcome by a second route |
| The rolled-window filter fallback fired only on a filter change | A reader stranded on a filter option its own menu no longer offers, reachable out of only by the one action they had no reason to take |
| `ContentZone.activityModel` rebuilt the model in `body` | A new `ActivityModel` — and a new subscription — on every body evaluation until the deferred `Task` landed. Now a stored lazy on `ShellModel` |
| `FeedBanner` reconnected in an unstructured `Task` | The work outlived the board it was pressed on |
| `Start the router` / `Re-pair…` were enabled and wired to `break` | A control reporting a capability the app does not have, silent when pressed. §3.4's answer applied instead: dimmed in place with a discoverable reason (spec B44) |

## Runs

| Screen | How it was verified | Commit | Result |
|---|---|---|---|
| Activity — populated | `scripts/acceptance/m2-activity.sh` full run. AX by pid: no scaffold sentinel; both filters present; title `Activity`; 12 rows; a `failed,` row; `claude · pid N`; the 82-char tool name complete in the label; subtitle `Showing 12 calls · since 7:12 pm · live` | `8607c55`+ | **pass** |
| Activity — inspector (**new runtime evidence**) | `axkit press` on the over-long row — background-safe, because a SwiftUI `Button`'s AXPress runs its action on the element rather than through `@FocusedValue`. Inspector opened carrying the full `/Users/...` cwd, the untruncated 82-char tool name, and `warm — the server was already running` in words. B29/B31 had been a model claim with no runtime path at all | `8607c55`+ | **pass** |
| Activity — filters | Both `AXMenuButton` with values `All sessions` / `All projects`. Absence of `N of M` and `Clear filters` now read off the **value column**, and the predicate is proven live against the subtitle in the same column first | `8607c55`+ | **pass** |
| Activity — a record actually arrives (**new runtime evidence**) | `MCPROUTER_SCENARIO=streamLive`: 12 backfill rows → **16** after the feed delivered. Previously unexercisable in principle — every replayed record shared a `CallRecord.id` with a row already on screen, so the de-duplication guard dropped all of them | `8607c55`+ | **pass** |
| Activity — offline, and its disabled action | `Start the router` reports `enabled=0` off the running control, with `This arrives with the item that owns it` on screen. The three `ControlAPIError` strings still verbatim | `8607c55`+ | **pass** |
| Activity — unauthorised | Distinct state, own copy and action | `8607c55`+ | **pass** |
| Activity — empty / loading / feed retrying / feed spent | Re-run unchanged from the first pass and still green: empty carries no error language and the disabled-filter reason claims no start time; loading has no `AXProgressIndicator` and zero rows; retrying offers no button; spent offers Reconnect and names no attempt count | `8607c55`+ | **pass** |
| Activity — Space is not claimed | M1's probe reported `Space` with the board on screen | `8607c55`+ | **pass** |
| Mac shell — regression after the `ShellWindow` change | `scripts/acceptance/mac-shell.sh` full run. 256.0/52.0/32 measured; 34 commands with shortcuts and reasons; scroll edge `#1E1E1E` → `#2F2F2F` → back; destination and frame restored across relaunch; `boards installed: 1 of 8`; Debug probe absent from Release | `8607c55`+ | **pass** |

**Invisibility.** Both scripts recorded `frontmost at start: Ghostty` and `frontmost at end: Ghostty`,
and assert it at every step between. Launches were `open -g -a`; keys were `CGEvent.postToPid`;
nothing activated the app and nothing used `screencapture -R`.

## Red-green proof of this pass's new gates

| Gate | Mutation | Result |
|---|---|---|
| B44 · stripping the offer keeps the words | `withoutAction` also blanks the title | **red** (3 assertions) |
| B44 · one performing branch | `.offline` wired to `model.clearFilters()` | **red** (3 assertions) |
| B44 · the reason is not an apology | reason → "Sorry, this failed." | **red** (6 assertions) |

B45–B49 carry the gap-fix's own red-green tests in `ActivityRecoveryTests` — concurrent start, the
un-truncated live half over a full backfill, the refused second reconnect, the failed reconnect that
still names the problem, and the fallback on arrival.

## A gate that was incapable of failing, and now is not

B17's absence check ran an **anchored** `^[0-9]+ of [0-9]+$` over `spoken`, which joins four AX
fields with spaces — so it could never match anything, and would have passed a board that drew
`9 of 28` with no filter set. That is precisely the failure the check exists to rule out. It now
reads the value column, and the run first proves the predicate can match at all by finding the
subtitle in that same column. An absence check that has not been shown capable of firing is
decoration.

## Suite

`swift test` — **730 tests in 102 suites passed**. `scripts/lint/no-raw-design-values.sh` clean over
42 files, 21 under the geometry and boundary rules; `scripts/lint/no-wire-codable.sh` clean.
