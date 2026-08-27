I'll review the I6 branch against the code, not the write-up — starting with the spec, inbox sources, and the diff vs main.Spec is clear on the boundary. Next I’ll read the inbox sources, notification path, and mutation script.I’ve got the core types. Next I’ll read the board/arrival wiring, factory, and tests — that’s where a silent install or a false phone-origin claim would hide.Core wiring is in. Tests, router, pairing factory, and I5 evidence are next — that’s where false claims and unfailable assertions usually live.The many-item category looks like it still ships Decline. I’ll confirm that against the announce path, then read pairing, DESIGN.md, and I5 so the five verdicts are grounded.I’ve got the install path isolated to the review sheet. Next I’ll check pairing-sheeThe A11 mutation left InboxBandTests green — the filter never reaches the announcement suite. Reverting that and checking the split commit that broke the gate.**Refuse.** The boundary is intact. The mutation gate is not: I applied A11 and the suite it names stayed green.

### 1. Install without a human at the Mac

**Nothing found.** `client.add` is reached only from `InboxBoardModel.accept` (`_ = try await client.add(declaration)`, `InboxBoardModel.swift:225` at `2d3805d`), and that is reached only from thThe announcement tests were split after the mutation script was written — I’ll prove whether those mutations still go red, and check the leftover notification/chrome gaps.The announcement suite was split after the mutation script was written. I’ll run one of those mutations to see whether it still goes red.**Do not merge.** The boundary holds. The mutation gate does not, and the notification surface ships a Decline button the spec forbade.

### 1. Install without a human at the Mac?

**No.** Nothing here installs without a human on this Mac.

Checked: `InboxBoardModel.accept` (`public func accept(_ acceptable: AcceptableInboxItem) async {`, `InboxBoardModel.swift:214` at `2d3805d`) is the only `client.add` on this path, and the only UI caller is `InboxReviewSheet.press` (`Task { await board.accept(acceptable) }`, `InboxReviewSheet.swift:260` at `2d3805d`). `InboxNotificationAction` has no install case (`public enum InboxNotificationAction: String, Sendable, Equatable, CaseIterable {`, `InboxArrival.swift:20-24` at `2d3805d`). The delegate switches onto review/decline only (`switch action {`, `InboxNotificationDelegate.swift:76-83` at `2d3805d`). `undoLastDisposition` restores a decline and returns on accept (`public func undoLastDisposition() {`, `InboxBoardModel.swift:265-268` at `2d3805d`). `commitDefaultAction` opens the sheet, never accepts (`public func commitDefaultAction() -> Bool {`, `InboxBoardModel.swift:340-345` at `2d3805d`). `announceArrivals` announces and withdraws; it never calls `accept` (`InboxBoardModel+Arrivals.swift:91-113`). Release still goes through `NoTransportInboxService` (`public static func choice(isDebugBuild: Bool, environment: [String: String]) -> Choice {`, `ShellPairingFactory.swift:38-43` at `2d3805d`). `ScriptedInboxService` / `RecordingArrivalNotifier` live under `app/Tests/`. No timer, no default, no undo-that-expires-into-accept.

A notification Review plus Return on the sheet's `.defaultAction` Install (`Button(acceptLabel) { press() }`, `InboxReviewSheet.swift:201-204` at `2d3805d`) is still a human at the Mac. It is the least-deliberate remaining press, not an unattended one.

### 2. Phone-originated arrival asserted as happening today?

**Nothing found.** Spec I6 states the Release reach plainly (`What a Release build can reach today, stated plainly`, `spec-I6.md:108-114` at `2d3805d`). I6 tests drive `ScriptedInboxService` / `ArrivalTracker`, not a phone. `.arriving` is a clocked fixture (`/// One item now and a second one shortly, so **an arrival while the popover is open** is`, `InboxService.swift:111-119` at `2d3805d`). I6-added copy (`InboxCopy.Arrival.*`, `alreadyHandled`) is format for when a banner fires, not a claim that one can. `InboxCopy.emptyDetail` (“Things you send from your phone land here”) is M6 intended-contract copy, shown on an empty pane.

The nearby false claim is different: `ArrivalNotifierFactoryTests.swift:89-91` says `SilentArrivalNotifier` is “the implementation a Release build runs today.” Release passes `Bundle.main.bundleIdentifier` into `ArrivalNotifierFactory.make` (`@State private var model = ShellModel(`, `MCPRouterApp.swift:23-26` at `2d3805d`) and gets `UserNotificationArrivalNotifier`. Silence in Release is the empty `NoTransportInboxService` snapshot, not this type.

### 3. Assertions that cannot fail for the right reason

**Several. Two of them are the ones this fleet has shipped before.**

**The many-item Decline assertion tests the value, not the buttons macOS draws.** `expect(many.actions == [.review])`, `InboxAnnouncementTests.swift:55` at `2d3805d` expects `many.actions == [.review]`. `UserNotificationArrivalNotifier.announce` (`public func announce(_ announcement: InboxAnnouncement) async {`, `ArrivalNotifierFactory.swift:88-93` at `2d3805d`) stamps every request with the one category built at `public static func category() -> UNNotificationCategory {`, `ArrivalNotifierFactory.swift:54-76` at `2d3805d`, which always registers Review and Decline. A many-item banner therefore shows Decline. The assertion is green against that implementation. Pressing it does not decline: `guard identifier != InboxAnnouncement.manyIdentifier else {`, `InboxNotificationDelegate.swift:72-74` at `2d3805d` sees `inbox.many` and opens the Inbox for every action.

**The mutation script is aimed at a suite the last commit emptied of those clauses.** `7fe67ab` split `InboxAnnouncementTests` out of `InboxBandTests`. Nine mutations still `--filter InboxBandTests` while mutating `InboxArrival.swift`: A8, A9, A9b, A11, A12, A13, A14, A15, Partial (`mutate "A8 an unrecognised action identifier is treated as a review" \`, `i6-mutations.sh:114-187` at `2d3805d`). I applied A11 (`guard seeded else {` → `if false {`). `InboxBandTests`: 11 passed, exit 0. `InboxAnnouncementTests`: `firstSnapshotIsNotAnArrival` went red at `expect(seeded.isEmpty)`, `InboxAnnouncementTests.swift:139` at `2d3805d`. The gate as written would print `GREEN A11`. Reverted; tree clean.

**Also blind, smaller:**

- `// Every action the closed set contains, on a real waiting item.`, `InboxArrivalTests.swift:148-156` at `2d3805d` (A7) calls `board.review` / `board.decline`. It never enters `InboxNotificationDelegate.perform`. A delegate that called `accept` would leave this green.
- `for line in [`, `InboxConformanceTests.swift:170-181` at `2d3805d` (the A22 sentence-case walk) does not list `InboxCopy.Arrival.*`, `Band.overflow`, `partialCapability`, `alreadyHandled`, or `notificationsOff`. Title Case in I6 copy cannot fail it.
- `await notifier.announce(`, `ArrivalNotifierFactoryTests.swift:98-108` at `2d3805d` (`silentNotifierIsInert`) calls `announce` / `withdraw` and asserts nothing about them.

A5 (`InboxBandTests.swift:157`, `headline == InboxCopy.subtitle(...)`) is `f(x) == f(x)` on wording; it can still go red if the call site moves, and the A5 mutation is still aimed at the right suite.

### 4. Notification handling

**Wrong in the ways this API usually is.**

**Delegate is installed in a view `onAppear`, not at launch.** `.onAppear {`, `MCPRouterApp.swift:33-37` at `2d3805d` vs `ShellAppDelegate.swift:157-159` (only `ShellMenuReasons.install()`). `UNUserNotificationCenter.delegate` must be set before the app finishes launching or the response that launched the app is discarded. Quit, leftover banner, click Review or Decline: the press is lost. Decline is worse — the user thinks they declined.

**One category for every banner.** `public static func category() -> UNNotificationCategory {`, `ArrivalNotifierFactory.swift:54-76` at `2d3805d` plus `announce` at 93. Spec ("No `Decline` on the many-item notification.** There is no single item for it to act on,", `spec-I6.md:234-235` at `2d3805d`): no Decline on the many-item notification. Shipped: Decline is on it. `guard identifier != InboxAnnouncement.manyIdentifier else {`, `InboxNotificationDelegate.swift:72-74` at `2d3805d` maps that Decline to “open Inbox”.

**Withdrawal is not “the moment” its item is dispositioned** (`A delivered notification is withdrawn the moment its item is dispositioned by any`, `spec-I6.md:238-240` at `2d3805d`). It is derived on the next `load()` (`InboxBoardModel+Arrivals.swift:84-90`), so up to `pollInterval` (2s, `public static let pollInterval: Duration = .seconds(2)`, `ShellModel.swift:46` at `2d3805d`). A Decline button can sit on a gone item for one poll. The race is named; the spec sentence is still false.

**`willPresent` is `[.banner, .sound]`** (`public func userNotificationCenter(`, `InboxNotificationDelegate.swift:60-65` at `2d3805d`), no `.list`. Frontmost delivery may not land in Notification Center, so the withdraw path has nothing to withdraw.

**A second delta of one item does not replace `inbox.many`.** Same id replaces; a single-item id does not. After “2 arrived” then “1 more”, both banners can exist, and the many title is the delta (`InboxArrival.swift:99`, `manyTitle(arrivals.count)`), so it can read “2 items are waiting” while 3 are.

**Authorization is asked on the first paired snapshot** (`InboxBoardModel+Arrivals.swift:122-126`). Denied is recorded. `announce` still runs. Harmless: the system will not show it. `notificationsAuthorized` is never read by a view (next section).

**App not running:** nothing posts (`trigger: nil` requires a live process). Leftover NC items plus the late delegate is the live case. Frontmost: they opted into a banner, correctly. Twice-delivered same id: the request identifier replaces. `target` is `weak` and the App `@State` model holds it; that part is fine.

### 5. What I would refuse

- Re-aim the nine stale mutation filters, or the gate no longer measures the clauses it names. Proven for A11 on this tree.
- Two categories, or `announce` must register from `announcement.actions`. Otherwise A8 is a comment about a value macOS does not draw.
- Install the delegate in `applicationDidFinishLaunching`, not `WindowGroup.onAppear`.
- `InboxCopy.Arrival.notificationsOff` (`public static let notificationsOff = """`, `InboxCopy.swift:178-181` at `2d3805d`) is never rendered. `notificationsAuthorized` is written (`public internal(set) var notificationsAuthorized: Bool?`, `InboxBoardModel.swift:81` at `2d3805d`, `InboxBoardModel+Arrivals.swift:125`) and never read. `PairingSessionModel.Phase` has no paired case (`public enum Phase: Sendable, Equatable {`, `PairingSessionModel.swift:16-27` at `2d3805d`); `PairingSheet` cannot show the denied-state sentence the spec designed (`Denied is a designed state, not a failure.** Nothing nags and nothing retries. The`, `spec-I6.md:202-207` at `2d3805d`, `switch session.phase {`, `PairingSheet.swift:102-116` at `2d3805d`). Ship the line or delete the copy.
- Spec keyboard table ("`↑` `↓` | popover | moves through band rows — **inbox rows first, then attention rows**,", `spec-I6.md:314-315` at `2d3805d`) extends M8’s popover `↑`/`↓`/`Return` to inbox rows. `MenuBarPopover` has no `onKeyPress` at all. M8 specified the same and also did not implement it ("`↑` `↓` | popover | Moves through band rows. Call rows are not pressable and are skipped.", `spec-M8.md:351-353` at `2d3805d`). I6’s table is still fiction.
- Partial rows are a full-width Review button (`Button { MenuBarRouter.revealInbox(itemID: row.id, on: shell) } label: {`, `MenuBarInboxBand.swift:70` at `2d3805d`). Spec Disabled ("Overflow** | a long name truncates at the tail inside its row; **rows never change", `spec-I6.md:260` at `2d3805d`): “carries no review affordance”. Accept is still impossible (`AcceptableInboxItem` is nil). The affordance is a lie, not a hole.
- `ShellChrome.indicatorUses` (`public static let indicatorUses: [IndicatorUse] = [`, `ShellChrome.swift:39-153` at `2d3805d`) never names the inbox band’s `--attn` stroke. `noUndeclaredIndicatorUse` only checks that the token appears somewhere in the list, so I6’s use cannot fail it.
- `startPolling`’s comment says the menu bar also calls it (`/// Idempotent, and that matters: the window and the menu bar both call it, and two loops`, `ShellModel.swift:361` at `2d3805d`). Grep: only `.task { model.startPolling() }`, `ShellWindow.swift:49` at `2d3805d`. WindowGroup still creates a window today (`LSUIElement` is false), so polling starts. The comment is already false.

The boundary did not move. The proof that it cannot, and the notification the item exists to ship, are not in the state the spec describes.

GROK-EXIT: 0
BYTES:    10009
