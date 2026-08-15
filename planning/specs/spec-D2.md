# spec-D2 — Deferred register: Mac surfaces and design authority

**Status:** In Progress · **Lane:** Opus · **Branch:** `ai/d2` · **Base:** `main` `42ea4d3`

This item is a **register, not a feature**. Its deliverable is a triage decision on every child,
each backed by a measurement, plus implementation of only the children that survive triage.

---

## 0 · A finding about the register itself, before any child

**The ledger never enumerates D2's children.** `ORCHESTRATOR.md:164` says "14 children", but the
deferred-children table names `D2` in its *Absorbed by* column for exactly **two** rows
(`D-m13-a`, `D-m13-b`). The other twelve are implied by "the owning item has merged, so the child
is orphaned onto the surface register", which is a rule nobody wrote down and which yields
**≈20 candidates**, not 14, when applied to the Mac surfaces.

So the set below is **reconstructed and stated**, rather than taken. Nine children are named
explicitly in this runner's brief; the rest are the Mac-surface orphans, each dispositioned by
name so none is skipped silently. If the orchestrator meant a different fourteen, this table is
where the disagreement is visible.

---

## 1 · Triage — every child, with the measurement behind the decision

| Child | Verdict | Evidence |
|---|---|---|
| **D-m13-a** Boards render vertically centred | **DO — and the brief is wrong about its scope** | Real, and measured at **209.5pt**, not inferred. But it is **one board, not seven** |
| **D-m13-b** `SettingsBoard` nests a ScrollView | **DO — and the fix is the opposite of the one proposed** | Measured: Settings publishes **3** scroll areas, every other board **2** |
| **D-g1-b** m8 A9 carries no reason | **FOUND-TO-BE-WRONG as a product defect; the CHECK is the defect** | `m8-settings-menubar.sh` measured **exit 0, 21 passed, 0 failed** on a fresh build of `main` |
| **M9** Rename `Evals` → `Checks` | **DO** | The internal vocabulary is *already* `Checks`; only the label lags |
| **M10** Amend `DESIGN.md` §6:279–280 | **DO** | The mandated string names a state that does not exist, and contradicts §6's own last bullet |
| **D-m14-b** `⌘E` on a permanently dimmed command | **DO** | `⌘E` is a standard macOS shortcut; `DESIGN.md` §8 never granted it |
| **D-m14-a** Per-command `.featureUnbuilt` copy | **NOT DOING** | The code states its own trigger condition and it is unmet |
| **D-m14-c** `Export library…` ellipsis | **FOUND-TO-BE-WRONG** | Removing the ellipsis would assert the *false* claim |
| **D-f** Machine-readable token block in `DESIGN.md` | **FOUND-TO-BE-WRONG / obsolete** | The premise describes a parser that no longer exists |
| M12 · D-m11-b · D-w1 · D-b · D-c · D-m6-b…g · M5-b/c/d · D-g1-c | **NOT DOING — out of scope for a register pass** | Each is a feature of its own size; see §6 |

---

## 2 · D-m13-a — the headline, measured before it was believed

### What the brief predicted

> every board renders vertically centred rather than top-aligned … a visible defect on all seven
> boards … roughly 208pt down the pane.

### What was measured

One backgrounded launch (`open -g`, never activated, frontmost `Ghostty` before and after), five
panes selected by `AXPress` on the sidebar row, `axkit dump … window` each time. Topmost
content-zone `AXStaticText` with `x > 450`, `y > 200`:

| Pane | Topmost board text | y | Drop below the content top (191) |
|---|---|---|---|
| **Servers** | `Servers` | **400.5** | **209.5pt** |
| Settings | `Settings` | 208.0 | 17pt |
| Inbox | `Inbox` | 208.0 | 17pt |
| Discover | column header `source` | 286.0 | (header above it) |
| Skills | column header `skill` | 290.0 | (header above it) |

**The 208pt figure is confirmed — to within 1.5pt — and the "all seven boards" claim is refuted.**

### The mechanism, and why only one board has it

`ShellWindow.ContentZone.outerScroll` wraps the board in

```swift
.frame(maxWidth: .infinity, minHeight: scrollableMinHeight)   // 256 × 3 = 768
```

SwiftUI's default alignment is `.center`, so a board shorter than 768pt is centred in it. Servers'
content measures ≈351pt (title at 400.5 → footer ending 751.5), and `(768 − 351) / 2 = 208.5` —
which is the measured 209.5 within rounding. The arithmetic and the AX reading agree.

**Seven of eight boards do not show it because they already compensate**, each carrying
`.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)` — `SkillsBoard:98`,
`SettingsBoard:81`, `DiscoverBoard:96`, `EvalsBoard:102`, `CleanupBoard:87`, `InboxBoard:105`, and
`ActivityBoard` which never enters `outerScroll` at all. Expanding to fill leaves no dead space for
the centre alignment to act on. **`ServersBoard` is the only board that never added it**, ending at
`.frame(maxWidth: .infinity, alignment: .leading)` with no vertical term.

Two of those boards say so in a comment — `SkillsBoard:94` records "~170pt of dead space above the
header, measured in the acceptance capture". So this defect was *found and locally patched* six
times, board by board, and never fixed at the shell. That is the finding worth carrying: the
register recorded it as one board's symptom seven times over.

### The change

The shell owns the frame, so the shell carries the alignment:

```swift
.frame(maxWidth: .infinity, minHeight: scrollableMinHeight, alignment: .top)
```

One term, at the one place that proposes the over-tall frame. It fixes Servers and makes
top-alignment the **shell's contract** rather than each board's private duty, so a board added
later cannot reintroduce it. The six boards' own `maxHeight: .infinity` frames are **kept** — they
do a second job (letting `ConnectionFailurePane` fill the pane) that the shell's alignment does
not replace.

---

## 3 · D-m13-b — the registry is right and the board is wrong

### What the brief predicted

> `SettingsBoard.swift:70` nests a ScrollView inside the shell's own, while being absent from
> `boardsThatScrollThemselves`. … decide which of the two is right.

### What was measured

`AXScrollArea` count per pane, from the same dumps:

| Pane | Scroll areas | Geometry |
|---|---|---|
| Servers | **2** | sidebar `188×475` · shell content `444,192 716×568` |
| Skills | **2** | sidebar · shell content |
| **Settings** | **3** | sidebar · shell content `444,192 716×568` · **its own `444,261 716×699`** |

The nesting is real and **Settings is the only board with it**. The inner scroll view is
**699pt tall inside a 568pt viewport**, so it does not fit its parent — which means the *outer*
scroll is what actually moves, and the header `SettingsBoard` placed above the inner `ScrollView`
to keep it still (`y = 208`) rides that outer scroll and does not stay put. The inner `ScrollView`
achieves nothing it was written to achieve.

### Which half is right — and it is not the half the brief assumed

The brief's framing assumes the nesting is correct and the registry omission is the bug. It is the
other way round.

`boardsThatScrollThemselves` documents its own criterion at `ShellWindow.swift:80–84`: a board
earns its own `ScrollView` when it has **sticky chrome** — "a column header or a filter bar … one
outer scroll would carry the header off the top of a five-hundred-row log". That is Activity, and
Activity alone. **Settings has no column header and no filter bar**; it has a pane title and a
subtitle, which is exactly what Servers, Skills, Discover, Inbox, Evals and Cleanup all have — and
all six of those scroll inside the shell.

So `boardsThatScrollThemselves = [.activity]` is **correct as written**, which is also what M13
independently found when it declined to move Servers into the set. `SettingsBoard`'s inner
`ScrollView` is the anomaly.

**Change: remove the inner `ScrollView` from `SettingsBoard`.** This is strictly smaller than the
alternative — adding `.settings` to the registry would *also* have required giving `SettingsBoard`
an `onScroll` callback mirroring `ActivityBoard.init(model:onScroll:)`, because the scroll-edge
separator reads the shell's scroll view and a board that scrolls itself must report its geometry
back or the separator dies on that pane.

---

## 4 · D-g1-b — the product is correct and the check can fail a correct app

### What the brief predicted

> a REAL PRODUCT FINDING, not a harness one … m8 currently exits 1 on this alone. Fixing it takes
> the whole acceptance suite to green.

### What was measured

`bash scripts/acceptance/m8-settings-menubar.sh` on a clean `ai/d2` at `42ea4d3` with a fresh
`make build-mac`:

```
  ✔ A9 · 'Forget the stored token' is present rather than hidden
  ✔ A9 · its reason is on the element, readable by assistive technology
  21 passed, 0 failed          EXIT=0
```

**m8 exits 0.** The tree was `git status --short` clean; nothing on this branch had been edited.
The product change the brief asks for does not exist to be made — `SettingsBoard.swift:221–223`
already sets `.disabled(!canForget)`, `.help(reason)` and `.accessibilityHint(reason)`, and
`axkit dump` already emits `kAXHelpAttribute`.

### What is actually wrong, and it is the check

A9 asserts the reason string **unconditionally**, without first establishing that the control is
disabled:

```bash
if grep -q "Forget the stored token" …; then
    pass …
    if grep -q "There is no stored token to forget\." …; then pass; else fail; fi
```

`SettingsPresentation.TokenStatus.canForget` is `true` for `.stored` and `.rejected`. In those two
states the button is **correctly enabled** and **correctly carries no reason** — §3.4 requires a
reason on a *disabled* control, not on every control — and A9 fails a correct app. That is a check
whose verdict depends on whether this Mac's keychain happens to hold a token, which is the
"gate that lies" class this fleet has now recorded five times.

It also explains the reading the brief inherited without needing to call anything flaky: G1
measured `20 passed / 1 failed`, this run measures `21 passed / 0 failed`, on 21 assertions both
times — a one-assertion swing on a check that reads machine state the app does not control.

**Change: make A9 assert the pairing it actually means** — read the control's `AXEnabled` from the
dump, and require a reason **iff** it is disabled, and require the absence of one iff it is
enabled. That is strictly stronger than today's check in both directions and is no longer
keychain-dependent.

---

## 5 · The three shared-surface changes

### M9 · `Evals` → `Checks`

Not a taste call, and that is the reason it is being taken. **The codebase already renamed the
concept.** `app/Sources/MCPRouterKit/Checks/` holds `CheckModels.swift`, `CheckCopy.swift`,
`CheckPresentation.swift`, `ServerChecks.swift`, `SkillChecks.swift`; the tests are `CheckTests`
and `CheckHistoryStoreTests`; and `CheckCopy`'s user-facing strings are check vocabulary
throughout ("4 passed · 1 failed · 1 unknown"). M7 renamed its own model layer and left
`Destination.evals.title` saying `Evals`. This closes an internal/external split that is already
half-applied, rather than introducing a name.

**Scope: `Destination.title` only.** The `rawValue`, the `deepLinkSlug` and the enum case stay
`evals` — they are identifiers, persisted in frame restoration and used by the prototype's
`?pane=evals` deep link, and `DESIGN.md` §6 governs words a user reads, not identifiers. Changing
them would break restoration and every mock link in `ORCHESTRATOR.md` for no user-visible gain.

**Cost, stated rather than discovered:** four acceptance scripts read the label
(`mac-shell.sh` ×4, `m7-evals-cleanup.sh` ×6, `m6-inbox-pairing.sh` ×1, `m5-discover.sh` comment)
and `spec-M1.md`'s inventory table is a **test oracle** parsed by `MenuCommandTests`. So this one
string forces `spec-M1.md` to be committed on the branch — the declared exception M14 established
— and forces `m7` and `m6` to be re-run. That is the price and it is being paid knowingly.

### M10 · `DESIGN.md` §6:279–280

The clause reads:

> One name per state across both devices. A skill with no evaluation reads "not evaluated" on the
> Mac and on the phone; never "no eval" on one of them.

**There is no eval runner in this product, in any form.** Nine source files say so in their own
comments, and every board that could have shown an eval dropped the column as fabricated — M3
(`spec-M3.md:74`, D1), M4 (`spec-M4.md:126`), M5 (`spec-M5.md:133`), the Inbox
(`InboxBoardMetrics.swift:34`). So §6 mandates a string for a state the product cannot be in,
and it **contradicts §6's own last bullet** four lines later: *"Numbers the router does not
observe are never displayed."* A design authority that requires a reading the same section forbids
is worse than a silent one, because a future runner will implement the clause.

**Change: replace the example rather than delete the rule.** The one-name-per-state rule is sound
and load-bearing across two devices; only its illustration is dead. It is re-pointed at a state
the product genuinely has, and the absence of evaluation is recorded explicitly so nobody
re-derives it.

### D-f · a machine-readable token block — **refused, with a reason**

D-f was filed against M1 on the premise that "F2's parity gate parses prose tables today; a fenced
block would make it robust to editing". **That premise no longer describes the parser.**
`DesignDocParser` (322 lines, `app/Tests/MCPRouterKitTests/DesignDocParser.swift`) resolves columns
**by header name, per table** — never by position, and the comment records that the positional
version is precisely what made adding a Light column unsafe. It selects data rows **structurally**
rather than against the code's own enum, and says why: filtering by `TypeToken` would make the
document→code direction blind. It strips markdown emphasis, expands `#FFF` to `#FFFFFF`, converts
`@7.5%` to `0.075`, skips headers and separators explicitly, and **throws** on a missing document,
a missing section, a missing column or a short row rather than returning empty.

Adding a fenced token block would put **a second copy of every token value inside the same
authoritative file**. The parity gate would then test the fenced copy while a human edits the
visible table — which is the exact drift the gate exists to prevent, and strictly worse than the
prose, because the two copies would live four lines apart and only one of them would be checked.

**Not done. Recorded as a closed finding rather than an open child.**

---

## 6 · What is deliberately not being done, and why

| Child | Why not |
|---|---|
| **D-m14-a** per-command `.featureUnbuilt` copy | `MenuCommand.swift:100–103` states its own trigger: the associated value "becomes worth doing the moment a **second** command takes it". Exactly one does (`exportLibrary`). Breaking `==` at six sites to make a generic-but-honest sentence name the single feature it already implies is churn against a condition the code says is unmet |
| **D-m14-c** `Export library…` ellipsis | §3.4 says `…` means "opens a further view" and its absence means "**commits now**". An export command opens a save panel on macOS — `Export…` is the kit's own spelling. Removing the ellipsis would make the item claim it commits immediately, which is the *false* reading of the two, and §precedence gives the kit the win. The honesty is already carried by the disabled state and its help tag |
| **M12** staleness + as-of in a destructive dialog | Real (M7 Phase D findings 4 and 8) and a genuine product change with its own state matrix. It is a feature, not register cleanup |
| **D-m11-b** menu commands no-op with the window closed | M11's critic accepted it as a finding and **deliberately** did not fix it; it is `ShellCommandRouter`'s residue across 16 always-enabled commands, not a Mac-surface tidy |
| **D-w1** nothing renders `watch.log` | Needs a surface that does not exist. A board, not a register item |
| **D-b**, **D-c** Activity's skipped-record count and filters | Both add controls and states to a merged board; each needs its own state matrix |
| **D-m6-b/d/e/g** pairing envelope version, popover inbox band, accent-substrate token, readout cadence | `-b` belongs to I4 with the transport; `-d` is a new surface; `-e` is a token addition that moves `DESIGN.md` §2 and F2's gate for one call site; `-g` is a performance cadence change |
| **D-m6-c** rename `ScaffoldPane.swift` | Five acceptance scripts read it **by name**. Renaming it is a five-script change for zero user-visible effect, and M6 declined it for exactly that reason |
| **D-m6-f** `CleanupPresentationTests.weakWindowBoundary` | M7's file, mechanism recorded, not re-run until green — a test-debt item |
| **M5-b/c** registry search for skills, `GITHUB_TOKEN` in settings | Both need a **router route** that does not exist. Router side, not Mac |
| **M5-d** an `axkit` verb that can press a non-`AXButton` | A harness capability, confirmed independently by M7. Not a Mac surface |
| **D-g1-c** m8 fails on any focus change | Observed live during this item — `axkit front` returned `Google Chrome` mid-run because the *user* switched apps. The rule should be "this app did not take the screen", not "nothing moved". Real, and a harness item spanning every script rather than a Mac surface |

---

## 7 · Acceptance

Every assertion is added to `scripts/acceptance/mac-shell.sh`, because every change in §2–§4 is a
change to **the shell** or to a shell-owned label — and the owner's standing instruction is to test
the surface the diff touches and no other.

| # | Claim | How |
|---|---|---|
| **D1** | Every installed board's first content-zone element sits within 40pt of the content top | Select each destination, dump, topmost `x>450, y>200` element's `y` minus the content scroll area's `y` |
| **D2** | The content zone publishes **exactly one** scroll area on every board | Count `AXScrollArea` with `x > 450` per pane; expect 1 |
| **D3** | The sidebar, window title and View menu all read `Checks`, and `Evals` appears nowhere | `axkit dump window` + `dump menu` |
| **D4** | No app-declared command binds `⌘E` | `dump menu`, `AXMenuItemCmdChar` |
| **D5** | A9 requires a reason **iff** the control is disabled | Rewritten in `m8-settings-menubar.sh`, both directions |

## 8 · Mutations

Each rebuilt before it is run, and re-aimed rather than swapped if it cannot redden.

| # | Mutation | Must redden |
|---|---|---|
| M1 | Drop `alignment: .top` from `outerScroll` | D1 (Servers) |
| M2 | Restore `SettingsBoard`'s inner `ScrollView` | D2 (Settings) |
| M3 | `Destination.evals.title` back to `"Evals"` | D3 |
| M4 | Re-add `KeyChord("E")` to `exportLibrary` | D4 |
| M5 | Make `canForget` always `true` | D5's disabled arm |
| M6 | Make `canForget` always `false` | D5's enabled arm |

---

## 9 · Corrections made during implementation — read this before §7 or §8

Written after the work, against measurements. §7 and §8 above contain three instructions that do
not survive contact with the running app; they are left in place so the disagreement is visible.

**§7's `x > 450` and `y > 200` do not identify the content zone.** `AXPosition` is in **screen**
coordinates, so those constants encode where the window happened to sit when §2's table was
measured. Applied literally, the D2 count matched **zero** scroll areas on every pane — and a count
assertion that matches nothing *passes*, by finding none of the thing it forbids. The shipped
assertions locate the content zone from the **sidebar outline's own trailing edge** instead. The
same zone measures x=444 on Servers and x=374.5 on Discover, so no single constant is right even at
one window position.

**§8's M5 and M6 cannot redden.** Both mutate `canForget`, but the control's `.help()` is *derived
from that same property* — `.help(canForget ? "" : reason)` — so mutating it moves the app and the
assertion together and A9 stays green either way. They were **re-aimed at the same semantic claim**
(never swapped): M5 forces `.disabled(true)` with an empty help, M6 forces `.disabled(false)` while
keeping the reason. Each breaks exactly the pairing A9 asserts, and each reddens one arm.

**§5's M9 scope — "`Destination.title` only" — was incomplete.** There were **three** user-visible
copies of the word, not one: `Destination.evals.title`, `CheckCopy.evalsTitle` (the pane's own
heading), and `SkillPresentation.observationFooter` ("evaluations arrive with Evals", which also
promised an eval runner that does not exist). Shipping the stated scope alone would have produced a
half-applied rename in which the shell and the pane it opens disagreed. `CheckCopy.evalsTitle` is
now derived from `Destination.evals.title` rather than spelled twice.

**Also closed, and not in the register:** `spec-M7.md`'s assumption 2 still instructed a future
runner that the rename is "reported, not made" — marked superseded; and `prototype.html`'s sidebar
label still read `Evals`.

**One D- row is closed as harness debt rather than product:** the first draft of D4's sweep used
awk's `and()`, a gawk extension the macOS awk lacks. It passed every green run and mutation M4
because awk short-circuits `&&`; the first row that actually violated the rule made the script exit
**2 (BLOCKED), not 1 (FAILED)**. Fixed to `int(mods / 8) % 2` and re-proved with M4b.
