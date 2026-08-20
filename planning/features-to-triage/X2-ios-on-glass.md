# X2 — the iOS on-glass instrument, and the six cases it takes off `n/a`

**Category:** ios · test instrument **Found:** 2026-08-20, from the campaign's `n/a` reasons.

The campaign's `ios-glass` lane carried **six cases recorded `n/a`** — CASE-0020, 0021, 0022 at
the `outcome` rung and CASE-0120, 0121, 0122 at `raster-visual` — all four reasons variations of
one sentence:

> Simulator has no Mac accessibility tree; MCPRouterIOS ships no URL scheme; simctl screenshot of
> the default Settings tab cannot be attributed to Discover; activating Simulator.app is refused.

Each clause is true of the instruments that were being used. None of them is true of the
instrument iOS actually provides.

## What was missing

`MCPRouterIOSTests` is a **unit** target hosted by the app. It constructs a view in the app's
process and reads it back through a hand-rolled walk of `UIView.accessibilityLabel`. Everything it
proves is true, and none of it involves a tab being tapped.

That gap has a name in this codebase already. `PhoneShell.content(for:)` documents the exact
failure it is shaped to prevent:

> making `awaitingKey` return nil for the three remaining tabs would not have retired the
> placeholder — it would have routed Triage, Queue and Library to the **final `else`**, so all
> three would have rendered Settings while every "no awaiting copy is compiled" check stayed green.

A suite that never selects a tab cannot tell that failure from success. The `switch` makes it a
compile error, which is stronger than a test — but only for that one shape of the bug. Nothing was
watching the rendered result.

## What this adds

A `bundle.ui-testing` target, `MCPRouterIOSUITests`, and a scheme of its own,
`MCPRouterIOSGlass`, so `make test-ios` stays the fast in-process suite and the on-glass lane is
asked for by name.

XCUITest answers all four clauses of the `n/a` reason:

| The clause | What replaces it |
|---|---|
| no Mac accessibility tree reaches the Simulator | XCUITest reads the tree **iOS** publishes, in the Simulator, out of process |
| the app ships no URL scheme | it does not need one — the runner taps the tab bar, which is how a person reaches a tab |
| a `simctl` screenshot cannot be attributed to a surface | the capture is taken **after** that surface's own identity assertion passed, and `xcresulttool export attachments` writes the test id beside every PNG |
| activating Simulator.app is refused | `xcodebuild test` against an already-`simctl boot`ed device never opens it |

Five cases, each carrying the assertion that would fail if the surface were substituted:

- `testEachTabRendersItsOwnSurface` — five tabs, five navigation bars, compared **against each
  other**. Five tabs rendering one surface is the failure it is built for.
- `testDiscoverRendersTheRoutersCatalogue` — SURF-012 publishes rows, and does not publish
  Settings' never-paired copy.
- `testDiscoverTracksWhatTheRouterReturned` — metamorphic. The same surface under `populated` and
  under `empty` must not render the same amount, or the screen is not reading the router at all.
- `testTriageQueueAndLibraryEachRenderTheirOwnSurface` — SURF-013, plus the discriminator that
  Library owns a search field and Queue must not have grown one.
- `testPairingIsReachedFromSettingsAndRendersItsPreflight` — SURF-014, reached the way a person
  reaches it: Settings → Pair Mac → the camera pre-prompt → *Enter the code instead* → the typed
  field. Both captures are ones the campaign recorded as never photographed.

## The bound this does not exceed

`XCUIScreenshot` carries **no per-frame status**, so a capture here cannot rule out a stale frame
the way `SCFrameStatus` can on the Mac. What stands in its place is attribution: the runner takes
the picture in the same test, after that surface's assertion has already passed. The campaign
records it in those terms and claims nothing the instrument does not offer.

It also does not prove pairing works. DEF-001 stands: the phone stores a paired-Mac record without
contacting the Mac, and the Mac's sheet says pairing is unavailable in this build. This target
photographs the surface honestly, including the part that is a placeholder.

## Rule 1 is intact

`planning/practices/UI_VERIFICATION.md` rule 1 — never steal focus — is why the four **macOS**
`n/a` rows stay `n/a`. `axkit`'s own source records the measurement: a menu item's action reaches
the window through `@FocusedValue`, an inactive app has no focused scene, and `AXPress` there
returns `.success` while doing nothing. So ⌘1–⌘7 and the `NSStatusItem` popover cannot be driven
from the background, and rule 1 says to leave that for a human rather than take the screen. This
item does not touch them.

## What the lane found on its first run

Three findings, all invisible to the in-process suite because it never selects a tab.

### DEF-X2-a (fixed here) — the tab bar announced the icons, not the tabs

The five tab buttons read back as `["discover", "inbox", "tray", "book", "settings"]`. `IconView`
labels itself with `Icon`'s raw value so an icon standing alone as a control still announces
something, and inside a `Label` that label **wins**, dropping the title. VoiceOver therefore called
Triage "inbox", Queue "tray" and Library "book" — three of five announcing a word that appears
nowhere in the interface.

`.accessibilityHidden(true)` on the icon was tried first and measured **inert**: the labels came
back byte-identical. Stating `.accessibilityLabel(tab.title)` on the `Label` is what moved them to
`["Discover", "Triage", "Queue", "Library", "Settings"]`. One line of product change, and the
comment beside it records both measurements so the inert one is not tried again.

### DEF-X2-b (open) — a fresh install is told its pairing is corrupt

On the simulator, Settings renders **"Can't read this phone's pairing"** — the `.unreadable` state
— on an install that has never paired anything. The surface's own source says why that is wrong:

> Folding absent into an error state would greet a user with "Can't read this phone's pairing" on a
> phone that has never paired anything, and offer to fix a problem that does not exist.

`KeychainPairingStore.load()` maps `errSecItemNotFound` to `.missing` correctly, so the simulator is
returning a different status — almost certainly `-34018 errSecMissingEntitlement`, which is what an
unsigned build with an empty entitlements file gets from the Keychain. That makes the immediate
cause an artifact of how this lane builds, and it leaves a real product question behind it: every
status other than `errSecItemNotFound` currently renders the corrupt-record surface, including
`errSecInteractionNotAllowed` on a background launch before first unlock, which
`kSecAttrAccessibleAfterFirstUnlock` permits.

Two candidate fixes, neither taken here because the choice is not this item's to make: give the iOS
target a keychain access group so the Keychain answers on an unsigned build, or narrow the
`.unreadable` branch so only *present and undecodable* reaches it and an unavailable Keychain gets
its own state. `testPairingIsReachedFromSettingsAndRendersItsPreflight` stays red and names it.

### DEF-X2-c (open) — Discover renders the same catalogue whatever the router returned

Launched with `MCPROUTER_SCENARIO=empty`, Discover still drew the populated bands: GitHub with
"2,984 sessions on Smithery", DeepWiki with "2,332 sessions on Smithery", and dated rows under
Recently changed. The first version of this check compared element counts between the two runs and
read **19 against 19** — a metric a real difference could not have shifted, since most of that total
is chrome. Re-aimed at the empty state's own headline, it now says what is actually wrong.

Whether the fixture ignores the scenario for the registry route, or the launch environment does not
reach the model, is not settled here. `testDiscoverTracksWhatTheRouterReturned` stays red and holds
the observation.

## `test-ios-glass` is now in `make all`

It was held out while two of five cases were red, because a known-red lane in the whole-repo gate
either blocks every unrelated commit or invites someone to soften the two assertions — and those
assertions are the only reason the findings are visible. The stated condition was that it joins
`all` when DEF-X2-b and DEF-X2-c close.

Both closed on 20 Aug 2026 — they became DEF-013 and DEF-017 — and the lane has since run 5 of 5 on
eight separate runs against the device it owns. It was wired into `all` on the same day. It costs
roughly two minutes and adds no new requirement, because `test-ios` already needs a booted
simulator, and it is the only stage in that list which proves the app *runs* rather than that its
views construct.
