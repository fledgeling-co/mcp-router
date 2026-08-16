# I6: Fast Mac approval, with the boundary exactly where it is

| | |
|---|---|
| Status | In Progress |
| Item | I6 — the menu-bar inbox band and the arrival notification (`D-m6-d`) |
| Deps | M6 ✓ (Inbox board, `InboxService`, `InboxBoardModel`) · M8 ✓ (popover, status item, app-lifetime poll) |
| Branch | `ai/i6` · worktree `.worktrees/I6` |
| Design authority | `DESIGN.md` — §2 colour, §5 states, §6 words, §7 motion, §9 forgiveness |
| Out-of-family gate | `grok --model grok-4.6`. Codex is account-blocked. grok **exits 0 when session init fails**, so every gate here asserts on content in its output, never on `$?`. |

---

## Why this item exists

The owner asked for the phone to install servers directly. That work was blocked, and a two-judge
panel found the question he had been asked contained a false binary: the option he chose carries its
own consequence text saying a second confirmation on the Mac would be *"most of the benefit gone"*.
Both judges found that is true **only if confirming means walking to the laptop and opening a
window**.

So the friction is real and the boundary is not what causes it. This item removes the friction and
leaves the boundary where `DESIGN.md` §9 puts it. Grok's phrasing, adopted verbatim as this item's
scope test: **faster consent, not unattended install.**

Every design decision below was checked against one question — *does this make the decision quicker
to reach, or quicker to skip?* The first is what was asked for. The second is what the queue exists
to prevent.

---

## What is being made faster, measured as presses

The path an owner actually walks today, and after. "Presses" counts deliberate user actions from the
moment the phone sends; "notice" is whether anything tells him at all.

| | Today | After I6 |
|---|---|---|
| Notice | nothing. The window is closed, the menu bar says nothing, the Inbox is a pane nobody visits speculatively | a notification, and an `--attn` dot in the menu bar |
| Reach the item | open window → `⌘5` → find the row | press the notification, **or** open the popover and see it |
| Read what it runs | `Review…` → sheet | the capability headline is **on the banner**; the sheet is one press away |
| Install | press | press |
| Decline | open window → `⌘5` → find the row → press | one press, from the notification **or** the popover, no window |

The install still ends at the review sheet, deliberately. The decline does not, deliberately. §"The
boundary" below is the whole argument for that asymmetry.

---

## The boundary, and the two places this design pushed against it

`DESIGN.md` §9: *"The phone queues; it never installs. Pairing grants a remote party the ability to
put executable code on a laptop, so the phone's commit bar sends items to the Mac's inbox for
review."*

Nothing here lets an install happen without a human at the Mac acting. Two shapes were considered
that would have, and both are rejected with their reasons rather than left unmentioned.

### Rejected: `Install` as a notification action

A `UNNotificationAction` press is a human at the Mac acting, so it does not cross the stated
boundary. It is rejected anyway, and on a narrower ground:

**A notification is the least deliberate press available on a Mac.** It appears over whatever the
user was doing, unrequested, positioned where muscle memory dismisses things, and it is the one
surface where a press can land on a decision the user had not decided to make. Installing from it
would move the one-tap-from-remote-request-to-running-code failure off the phone and into
Notification Center. That is the queue's own failure mode wearing different clothes.

**So the asymmetry is the design, and it is `DESIGN.md` §9's "friction scales to blast radius" read
literally:**

| Direction | Blast radius if wrong | Where it can be pressed |
|---|---|---|
| Decline | the sender resends. Reversible in one press through the existing single-slot undo | notification, popover, pane |
| Install | executable code declared on this laptop from a request that arrived over a network | the review sheet, and nowhere else |

### Rejected: the staged install with an undo window

Fable proposed a staged state with a visible undo window rather than a modal yes/no, and the brief
asks for it to be considered. It is the right shape for a reversible action and the wrong one for
this one, for a reason that is exactly the boundary:

**A staged install whose undo window expires is an install nobody confirmed.** The user pressed once
and walked away; the commit is then performed by a timer. The guarantee the queue exists to make is
"a human at the Mac acted", and a timer expiry is not an act — it is the absence of one. A design
that installs on silence is strictly weaker than one that installs on a press, however visible the
countdown.

It is also not buildable honestly today at the layer that would make it safe: the router has no
held-but-declared state for an *added* server. `ControlAPIClient.add` declares it and it is live, so
"staged" could only ever mean the app sitting on the intent for ten seconds — which is the timer
above with no extra safety, not a router-enforced hold.

**Where Fable's shape is right, it is already used and I6 extends it:** declining is staged-and-
reported with an undo, in the popover as well as the pane. That is the same mechanism applied to the
direction whose blast radius it fits.

### The one phone-supplied string that reaches a notification

`InboxEnvelope.deviceName` is asserted by the phone and is rendered in the notification's subtitle
(`Queued from Luke's iPhone`). M6 already renders it on the pane's rows, so this is not a new trust
decision — but it is more prominent here, and it is recorded rather than assumed: **it is a label,
never a capability claim.** Everything the banner says about *what a thing does* comes from
`RegistryCapability.statement(for:)` on the entry the Mac resolved itself, and A9 asserts that.

---

## What a Release build can reach today, stated plainly

**Nothing.** There is no transport (`D-m6-a`, I5's item), so no item can ever arrive, the band is
permanently absent, and no notification can ever fire. `ShellPairingFactory` returns
`NoTransportInboxService` for a Release build and ignores the environment, and I6 does not touch
that rule.

This item is therefore built and proven against `MCPROUTER_PAIRING` scenarios and unit tests, exactly
as M6's surfaces were. Saying so is not a caveat bolted on at the end — it is the same honesty rule
M6 applied to its own pane, and a spec that implied a working notification in a shipped build would
be claiming a state the product cannot be in.

---

## The band

### Where it goes, and why not below the attention band

Directly under the header, **above** the attention band.

The taste argument (the thing you just did should be where you look first) is real but would not be
enough on its own. The structural one is: **the attention band's length is unbounded** — one row per
server wanting a decision — so an inbox band placed after it can be pushed below the fold on a Mac
with several held changes. The band is the one thing this item exists to make reachable in a glance,
and it cannot sit behind a list whose length the user does not control.

### What it contains

```
Nothing waiting · paired with Luke's iPhone        ← InboxCopy.subtitle, --t3
┌────────────────────────────────────────────────┐
│ Local notes            queued 2m ago  [Decline] │
│ DeepWiki               queued 1h ago  [Decline] │
│ Withdrawn entry        queued 15m ago [Decline] │
│ 4 more waiting · open Inbox                   › │
└────────────────────────────────────────────────┘
Declined DeepWiki.                          [Undo]
```

- **The header line is `InboxCopy.subtitle(waiting:device:)` verbatim** — the same function the pane's
  subtitle calls. `DESIGN.md` §6 asks for one name per state taken from one source rather than spelled
  twice, and the popover and the pane are two surfaces describing one queue.
- **No waiting count in the popover's own header.** `{running} · {idle} · {tools}` is untouched. A
  fourth count there would be a second derivation of a number the band already states, and two
  derivations of one number is how the popover and the pane come to disagree.
- **Pressing a row opens the review** — activate, window forward, Inbox selected, that item's sheet
  loaded. M8's held-change route, reused: this is the second legitimate activation in the app, and
  for M8's reason, which is that the destination is a window and a sheet behind an unactivated
  popover is a sheet nobody can reach.
- **`Decline` acts in place.** No window, no activation, no sheet. The row leaves and the report line
  appears beneath the band with `Undo`.

### The cap, and the ordering

**At most three rows** (`MenuBarPresentation.inboxBandLimit`). The call log's cap is six; an
actionable row is heavier than a read-only one — it carries a decision and two controls — so this is
half of it. Past three the popover has stopped being a glance and started being the board, which is
what `⌘5` is for.

**Oldest first, which is the opposite of the pane**, and the divergence is deliberate rather than an
oversight. Two reasons, and the second is what makes it load-bearing:

1. The band is a queue you drain from the front. Newest-first means the top row is always the one
   that just arrived, and the oldest item is never the one you press.
2. **An arrival then appends and never displaces a row under the pointer.** Newest-first inserts at
   index 0 and pushes every row down one, which is a mis-press waiting for a user who was reaching
   for `Decline`. See the arrival state below.

---

## The notification

### When it fires

On a snapshot delta: any item id present now that was not present in the previous snapshot.

**The first snapshot of a session announces nothing**, and its ids are seeded as already-announced.
A queue that was already waiting when you logged in is not an arrival, and five banners at login is
the behaviour that teaches people to turn notifications off — after which the feature is worse than
absent, because it is absent and believed present.

**`announcedIDs` only ever grows.** An id is minted once by the phone, so the only way a seen id can
reappear in a snapshot is if it came back — which is what undoing a decline does, and re-announcing a
row the user just put back would be the app arguing with them.

### Authorization

Requested **the first time a snapshot reports a paired device in this session**, not at launch.
Before a phone is paired nothing can ever arrive, so a launch-time prompt asks for permission to send
notifications the app has no way to generate — the kind of prompt that gets denied on reflex and
poisons the grant for when it matters. macOS prompts only once, so re-requesting on every launch of
an already-paired Mac is a no-op.

**Denied is a designed state, not a failure.** Nothing nags and nothing retries. The pairing sheet's
paired state carries one quiet secondary line saying what that costs, adjacent to the thing and at the
moment it becomes relevant:

> Notifications are off, so nothing will announce an arrival. The menu-bar item still takes its dot.
> Turn them on in System Settings › Notifications.

### What it says

**One item:**

| Field | Content | Source |
|---|---|---|
| Title | the entry name | `InboxItem.title` — what the Mac resolved, or the phone's name only when the entry could not be read |
| Subtitle | `Queued from Luke's iPhone` | `InboxEnvelope.deviceName` — a label, never a claim |
| Body | `Runs a program on this Mac` | `RegistryCapability.statement(for:).headline`, derived by the Mac from the registry |
| Body, Partial | `This entry could not be read, so what it would run cannot be shown.` | local |
| Actions | **Review** (default) · **Decline** | — |

**Two or more:**

| Field | Content |
|---|---|
| Title | `3 items are waiting` |
| Subtitle | `Queued from Luke's iPhone` |
| Body | `Nothing has run. Open the inbox to review them.` |
| Actions | **Review** (opens Inbox, no sheet) |

**One notification per delta, never one per item.** Three arriving together is one banner. The same
rule the status item obeys — an instrument that fires constantly is one the eye learns to skip, and
then it skips the one that mattered.

**No `Decline` on the many-item notification.** There is no single item for it to act on, and
"decline all" is a bulk destructive action nobody asked for.

### Withdrawal

A delivered notification is withdrawn the moment its item is dispositioned by any surface. That is
what closes the race in the state below, and it is cheap: `removeDeliveredNotifications`.

---

## The states — real copy for every one

`DESIGN.md` §5's nine, plus the two the brief names by hand.

| State | The band | The notification |
|---|---|---|
| **Empty** | **absent, not empty.** `InboxBand?` is `nil`, never a band of zero rows — the same nil-versus-empty device `PopoverContent.band` uses, and for the same reason: a view test cannot tell a hidden band from an empty one, a value test can | nothing fires |
| **One item** | header line `1 waiting from Luke's iPhone`, one row, no overflow row | title is the entry name, body is its capability headline |
| **Many items** | header line `7 waiting from Luke's iPhone`, three rows oldest-first, then `4 more waiting · open Inbox` | one banner: `3 items are waiting` |
| **Loading** | absent. No answer is not an answer of none, and a band drawn during loading would claim a queue nobody has read | nothing fires — there is no snapshot to diff |
| **Partial** | the row lists, with the phone's name and no capability line, and **cannot be reviewed into an install** — `AcceptableInboxItem` cannot be constructed for it. `Decline` still works | body: `This entry could not be read, so what it would run cannot be shown.` |
| **Error — the queue could not be read** | the band goes absent and the popover shows `The inbox could not be read` / `The queue could not be read: <detail>.` as its own row above the attention band | nothing fires. A failed read is not evidence that anything arrived |
| **Error — the registry could not be read** | rows list, every one Partial | as Partial |
| **Success** | in place, no toast (§5). The row leaves; `Declined DeepWiki.` + `Undo` appears beneath the band | the item's notification is withdrawn |
| **Offline — router not running** | rows still list. **`Decline` still works** — declining calls the router nothing. Pressing a row still opens the review, where the accept control dims with `The router is not running` | fires normally. The item arrived; the router being down does not unarrive it |
| **Disabled** | a row whose entry could not be read carries no review affordance and says why | — |
| **Overflow** | a long name truncates at the tail inside its row; **rows never change height**. The full name is in the row's help tag and accessibility value | the title truncates by the system, which is the system's job |
| **An item arrives while the popover is open** | **nothing already on screen moves.** Oldest-first means the arrival appends; at or above the cap it does not render at all and only the header line's count and the overflow row change. The report line, if showing, is untouched | fires |
| **An item dispositioned from one surface while another is open** | one `InboxBoardModel` on `ShellModel`, so `rows` is one derivation and both surfaces change in the same frame. Its notification is withdrawn | withdrawn |

### The residual race, named rather than hidden

Withdrawal is not instantaneous, so a user can press a notification action for an item that was
dispositioned microseconds earlier. Both routes are safe and neither is silent:

- **Decline** for an id that is no longer waiting does nothing and records nothing. It cannot
  double-dispose, because `record(_:)` is keyed by id.
- **Review** for an id that is no longer waiting selects Inbox, opens **no sheet**, and the pane's
  report line reads `That item was already handled.`

Reusing the existing report slot rather than inventing a banner is deliberate: the alternative is a
new surface for a state measured in microseconds.

---

## Motion (§7)

| Moment | Feel |
|---|---|
| Band appearing | it is present or absent between renders; the popover materialises from the status item and the band comes with it. No separate entry animation, and never opacity-from-0 |
| A row leaving on decline | the list closes up. Transform only |
| Header count changing | nothing. It is a number in a sentence, not a badge |
| Status dot appearing | M8's, unchanged — a scale bump, transform only |
| Reduce Motion | removes the bump. The state change always happens |

---

## The status item takes its dot for a queued item too

`MenuBarPresentation.statusItemNeedsAttention` and `statusItemLabel` gain a `waiting: Int = 0`
parameter. Existing call sites and M8's tests compile and pass unchanged; the status item passes the
band's count.

This is consistent with M8's three rules rather than an exception to them: **no count in the bar**
(the number is in the popover), **one dot colour** (`--attn`, because both conditions end in a human
deciding), and **`--live` never appears**. A queued item is a second reason for the same dot with the
same meaning, so there is nothing new to learn.

The alternative — a queue filling while the menu bar says nothing — is exactly the failure M8's own
poller section names: a glanceable instrument that silently stops being true.

The label's vocabulary already generalises: one queued item alone reads
`MCP Router, 1 item needs a decision`.

---

## Keyboard (§8)

| Key | Where | Behaviour |
|---|---|---|
| `↑` `↓` | popover | moves through band rows — **inbox rows first, then attention rows**, in render order. Call rows are skipped, as M8 specified |
| `Return` | popover | opens the focused row's destination. M8's contract, extended to the new rows |
| `Esc` | popover | dismisses. `MenuBarExtra(.window)`'s own |
| `⌘5` | anywhere | Inbox. Unchanged |
| `⌘Z` | window | undo the last disposition. Unchanged — **including one made from the popover or a notification**, because there is one model and one slot |

**I6 adds no shortcut and no menu item.** Every command it exposes is reachable from the menu bar
already (`⌘5` reaches the board, `⌘Z` reverses a decline), which is what §3.9 requires.

---

## Acceptance criteria

**T** red-green unit test (proved by mutation) · **M** measurement from the running app · **X**
exercised against a fixture.

### The band

- **A1 (T)** `InboxBand` is `nil`, never a band of zero rows, when nothing is waiting.
- **A2 (T)** The band caps at `inboxBandLimit` rows and its overflow row states the remainder; the
  header line states the true total through `InboxCopy.subtitle`, so the cap never hides a count.
- **A3 (T)** Rows are **oldest first**. Asserted on a snapshot whose queue order and time order
  differ, so a build that forwarded the pane's newest-first ordering fails.
- **A4 (T)** An item added to a later snapshot appends and **moves no existing row's index**.
- **A5 (T)** The band's header line is byte-equal to `InboxCopy.subtitle(waiting:device:)` for the
  same inputs — one wording, one source.
- **A6 (T)** The band sits above the attention band in `PopoverContent`'s render order, asserted on
  the value's own ordering rather than on a view.

### The boundary

- **A7 (T)** **No notification action installs.** Over every `InboxNotificationAction` case and every
  arrival path, `add(_:force:)` is called **zero** times, counted on `RecordingControlAPIClient`.
- **A8 (T)** The notification's action set contains no install action, asserted over the built
  announcement rather than over the delegate.
- **A9 (T)** A resolved item's notification body is byte-equal to
  `RegistryCapability.statement(for:).headline` for the entry the Mac resolved, and **contains no
  string the envelope carried** other than the device name.
- **A10 (T)** Declining from the popover calls the router nothing and is reversible through the same
  single-slot undo the pane uses.

### Arrival

- **A11 (T)** The first snapshot of a session announces nothing and seeds its ids.
- **A12 (T)** A second snapshot carrying a new id announces exactly once; a third carrying the same
  ids announces nothing.
- **A13 (T)** Undoing a decline does **not** re-announce the restored item.
- **A14 (T)** Two arrivals in one delta produce **one** announcement, in the many-item shape.
- **A15 (T)** A failed read announces nothing.
- **A16 (T)** Authorization is requested on the first snapshot reporting a paired device, and not
  again; a snapshot with no paired device requests nothing.
- **A17 (T)** A dispositioned item's notification is withdrawn, by id.

### Safety of the seam

- **A18 (T)** `ArrivalNotifierFactory` returns the silent notifier when there is no bundle
  identifier. `UNUserNotificationCenter.current()` traps in a process with no bundle, which is every
  `swift test` run, so this is the guard that keeps the suite runnable at all.
- **A19 (T)** A route for an id that is no longer waiting opens no sheet and reports
  `That item was already handled.`

### The floor

- **A20 (T)** No raw geometry literal in any view I6 adds; every value from a token or from
  `PopoverMetrics`.
- **A21 (T)** No indicator colour used decoratively. The band spends `--attn` only where something
  wants a decision.
- **A22 (T)** Every string I6 adds is sentence case; Cancel-leads and the `…` rule hold.
- **A23 (M)** `make lint`, `make build-mac` and `make test` are green with a non-zero test count.

---

## What this item does not do

| Suggested id | Title | Why not here |
|---|---|---|
| **D-i6-a** | A live transport | `D-m6-a` / I5. Until it lands, nothing can arrive in a Release build and this whole surface is proven under fixtures |
| **D-i6-b** | Router-enforced staged install | Would need a held-but-declared server state on the control API. Argued above: a timer-committed install is weaker than a pressed one, so this is filed as a mechanism question rather than as a UI one |
| **D-i6-c** | A notification when a *held tool change* appears | The same mechanism would serve the attention band, and the argument for it is the same. Out of scope because the item names the inbox, and because a second announcement source needs its own rate rules |
| **D-i6-d** | Settings row for notification state | M8's pane. I6 puts the denied-state sentence where it is relevant (the paired sheet) rather than editing another item's surface |
