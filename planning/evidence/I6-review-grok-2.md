I'll load the review and voice skills, then audit the branch against the nine refused points and the current diff.Reviewing branch `ai/i6` against the prior nine refusals and those five questions. Loading the first review, the reviewer persona, and the current diff.The main…HEAD range includes earlier work; I’ll isolate I6 commits and read the spec plus the install, notification, and mutation paths.Reading the install path, notifier, delegate, and the tests the mutations claim to measure.A comment on `notificationsAuthorized` may still claim a pairing-sheet render. Checking that against the tests, band UI, and factory.A17 may now be blind: commanded withdrawal would keep that clause green if the reconcile is deleted. Checking that and the remaining install/pairing seams.A17 went red; the tree is clean. Drafting the verdict and running the voice lint.🫥 **Refuse.** The boundary still has no unattended-install path, and the spec is honest that no pairing transport exists. `InboxNotificationDelegate.perform` can still call `accept` with every named clause green.

## 1. Install without a human at the Mac?

No.

`client.add` on this path is `InboxBoardModel.accept` (`_ = try await client.add(declaration)`, `InboxBoardModel.swift:232` at `25a7fc9`). The only production caller is `InboxReviewSheet.press` (`Task { await board.accept(acceptable) }`, `InboxReviewSheet.swift:260` at `25a7fc9`). `InboxNotificationAction` has two cases, neither install (`public enum InboxNotificationAction: String, Sendable, Equatable, CaseIterable {`, `InboxArrival.swift:20-24` at `25a7fc9`). `perform` switches onto `InboxNotificationRoute` and calls `openInbox` / `revealInbox` / `declineFromOutside` ("// The mapping is `InboxNotificationRoute`'s, in the Kit, where a clause walks every", `InboxNotificationDelegate.swift:86-95` at `25a7fc9`). `undoLastDisposition` restores a decline and returns on accept (`public func undoLastDisposition() {`, `InboxBoardModel.swift:273-276` at `25a7fc9`). `commitDefaultAction` opens the sheet (`public func commitDefaultAction() -> Bool {`, `InboxBoardModel.swift:348-353` at `25a7fc9`). `announceArrivals` announces and withdraws (`InboxBoardModel+Arrivals.swift:91-120`). Release is `NoTransportInboxService` (`public static func choice(isDebugBuild: Bool, environment: [String: String]) -> Choice {`, `ShellPairingFactory.swift:38-43` at `25a7fc9`). `ScriptedInboxService` and `RecordingArrivalNotifier` live under `app/Tests/`. No timer, no default that accepts, no undo that expires into accept.

A notification Review plus Return on the sheet's `.defaultAction` Install (`Button(acceptLabel) { press() }`, `InboxReviewSheet.swift:201-204` at `25a7fc9`) is still a human at this Mac.

## 2. Phone-originated arrival asserted as happening today?

Nothing found.

Spec I6 states the Release reach (`What a Release build can reach today, stated plainly`, `spec-I6.md:108-114` at `25a7fc9`). I6 tests drive `ScriptedInboxService` / `ArrivalTracker`, not a phone. `.arriving` is a Debug clocked fixture (`InboxService.swift:111-119, 247-252`). `SilentArrivalNotifier` is documented as the no-bundle case, not Release (`/// **Not the implementation a Release build runs.** An earlier version of this comment`, `ArrivalNotifierFactoryTests.swift:173-178` at `25a7fc9`). `InboxCopy.emptyDetail` is M6 intended-contract copy on an empty pane.

Leftover, not this question: `/// Stored as the observable that makes the ask-once rule fail when broken. No view reads`, `InboxBoardModel.swift:86-87` at `25a7fc9` still says `notificationsAuthorized` is rendered on the pairing sheet's paired state. `PairingSheet` has no paired phase (`switch session.phase {`, `PairingSheet.swift:102-116` at `25a7fc9`). The spec says no view reads it ("Not shipped, and the copy for it is deleted rather than left unrendered.**", `spec-I6.md:209-215` at `25a7fc9`). The copy was deleted; the comment was not.

## 3. Are all 31 mutations sound?

I did not re-run the full 31. I read all 31 against their clauses. Filters name the suites the clauses now live in. I applied A17 (`gone = Set<String>()`) on this tree: `InboxArrivalTests` went red at `withdrawalIsSweptOnTheNextRead` (`InboxArrivalTests.swift:331`, `withdrawals.last` was nil). Reverted; tree clean.

Two assertions still cannot fail for the reason they name.

**Blocker:** `perform` is still unreached. A7 (`// Every action the closed set contains, directly through the delegate as well as the`, `InboxArrivalTests.swift:148-154` at `25a7fc9`) still calls `board.review` / `board.decline`. `noRouteInstalls` (`func noRouteInstalls() {`, `InboxAnnouncementTests.swift:198-224` at `25a7fc9`) walks `InboxNotificationRoute`. Neither enters `InboxNotificationDelegate.perform` (`public static func handle(`, `InboxNotificationDelegate.swift:81-96` at `25a7fc9`). A `.review` case that called `accept` would leave A7, `noRouteInstalls`, and the A7 mutation green. The first review named this. The mapping moved; the last hop did not.

The Partial affordance is unasserted. `isReviewable` is `{ !isPartial }` (`public var isReviewable: Bool { !isPartial }`, `InboxBand.swift:68` at `25a7fc9`) and the view keys the button on it (`MenuBarInboxBand.swift:75, 102`). No test mentions `isReviewable`. `InboxBandTests.partialRow` checks `isPartial` and `capability == nil` only (`func partialRow() throws {`, `InboxBandTests.swift:216-227` at `25a7fc9`). `if row.isReviewable` rewritten to `if true` is green against every suite I can see, including all 31 mutations.

## 4. Notification categories, delegate, withdrawal?

Sound on the three things the last review named.

Two `UNNotificationCategory` instances; many has no Decline (`ArrivalNotifierFactory.swift:69-71`, `InboxNotificationCategory.many` at `InboxArrival.swift:111`, asserted at `let manyCategory = try #require(`, `ArrivalNotifierFactoryTests.swift:127-135` at `25a7fc9`). Delegate attached in `applicationDidFinishLaunching` (`func applicationDidFinishLaunching(_: Notification) {`, `MCPRouterApp.swift:164-174` at `25a7fc9`). Disposition calls `withdrawBanner(for:)` (`withdrawBanner(for: disposition.item.id)`, `InboxBoardModel.swift:257` at `25a7fc9`) and the next read still sweeps (`InboxBoardModel+Arrivals.swift:110-120`). `willPresent` is `[.banner, .list, .sound]` (`public static let presentationOptions: UNNotificationPresentationOptions = [`, `InboxNotificationDelegate.swift:69-71` at `25a7fc9`).

## 5. Verdict

**REFUSE.** Make `perform` a walkable value (or call it from A7) so a Review branch that installs goes red, and assert `isReviewable == false` on a partial row.

GROK-EXIT: 0
BYTES:     5104
