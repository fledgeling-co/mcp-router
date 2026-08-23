#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// A7 and D1 · what a surface outside the window may do.
    ///
    /// Split out of `InboxArrivalTests.swift`, which reached both the 400-line file cap and the
    /// 250-line type-body cap once D1's amendment and its exception were added — the caps were met by
    /// splitting rather than raised, following the split that produced `InboxAnnouncementTests.swift`
    /// in the Kit. The seam is the one that file's own suite name already draws: it is "arrivals and
    /// routes", this is "the boundary".
    ///
    /// The fixtures, the recording notifier and the scripted service stay on `InboxArrivalTests`, for
    /// that file's stated reason: two copies of `item(id:)` drifting apart is how two suites come to
    /// disagree about what a queued item is.
    @Suite("I6 · the boundary, and M20's one exception to it")
    @MainActor
    struct InboxBoundaryTests {
        static let device = InboxArrivalTests.device

        static func item(id: String, secondsAgo: TimeInterval, resolved: Bool = false) throws -> InboxItem {
            try InboxArrivalTests.item(id: id, secondsAgo: secondsAgo, resolved: resolved)
        }

        static func itemAskingForAValue(id: String) throws -> InboxItem {
            try InboxArrivalTests.itemAskingForAValue(id: id)
        }

        static func snapshot(_ items: [InboxItem], paired: Bool = true) -> InboxSnapshot {
            InboxArrivalTests.snapshot(items, paired: paired)
        }

        static func board(
            _ snapshots: [Result<InboxSnapshot, InboxServiceError>],
            notifier: RecordingArrivalNotifier
        ) -> (InboxBoardModel, RecordingControlAPIClient) {
            InboxArrivalTests.board(snapshots, notifier: notifier)
        }

        // MARK: - A7 · the boundary

        /// **The clause this whole item is written around.** Every route a surface outside the
        /// window can take — both notification actions, the arrival path itself, the band
        /// derivation — is exercised, and `add` is counted on a recording client throughout.
        ///
        /// It is counted rather than watched, for `RecordingControlAPIClient`'s own reason: a row
        /// disappearing looks identical to an install from the outside.
        ///
        /// **The second snapshot carries a genuine arrival, and that is not decoration.** The first
        /// version of this test read the same two items twice, so `arrivals` was empty on every
        /// load and the arrival path was never entered — a mutation that installed every arrival
        /// left it green. The clause was sound and the fixture was not exercising the branch the
        /// clause is about, which is the only thing a mutation can tell you and a passing series
        /// cannot.
        ///
        /// **Amended at M20, in the open, and the amendment is narrower than the sentence it
        /// replaces.** The invariant was *no path outside the window installs anything*. M20 builds
        /// one that does — the popover band's `Approve` — so the invariant is now:
        ///
        /// > No path outside the window installs anything **except** `ShellModel.approveFromOutside`
        /// > on a resolved item with nothing blank and the preference on — and **no notification
        /// > path ever does.**
        ///
        /// The notification half stays absolutely closed and is *widened* rather than relaxed: this
        /// clause now walks `FindingNotificationAction`'s cases as well as `InboxNotificationAction`'s,
        /// so the second family M20 adds is inside the same count. `add == 0` across both families is
        /// asserted before the exception is exercised at all, so the exception cannot mask the rule.
        ///
        /// `approveFromPopoverInstallsExactlyOnce` is the other half, and the two are deliberately
        /// separate tests: this one proves the boundary holds, that one proves the single hole in it
        /// is the shape it was designed to be. A single test asserting `add == 1` could not tell a
        /// hole in the right place from a hole anywhere.
        @Test("no path from outside the window installs anything, and the notification half is absolute")
        func nothingOutsideTheWindowInstalls() async throws {
            let notifier = RecordingArrivalNotifier()
            let first = try [Self.item(id: "q-1", secondsAgo: 300, resolved: true)]
            let both = try first + [Self.item(id: "q-2", secondsAgo: 60, resolved: true)]
            let (board, client) = Self.board(
                [.success(Self.snapshot(first)), .success(Self.snapshot(both))],
                notifier: notifier
            )

            await board.load()
            // The arrival path runs with something in it, so an install placed there is reachable.
            await board.load()
            #expect(notifier.announcements.count == 1, "the arrival branch was never entered")
            _ = board.bandZone()

            // Every action the closed set contains, directly through the delegate as well as the board.
            let shell = ShellModel(client: client, notifier: notifier)
            for action in InboxNotificationAction.allCases {
                InboxNotificationDelegate.handle(action, identifier: "q-1", on: shell)
                switch action {
                case .review: board.review(itemID: "q-1")
                case .decline: board.decline(itemID: "q-2")
                }
            }

            // **M20's second notification family, walked in the same clause.** Both identifier shapes,
            // because a finding banner names a finding and the arrival's many-banner names none.
            for action in FindingNotificationAction.allCases {
                for identifier in ["f-1", FindingAnnouncement.manyIdentifier] {
                    InboxNotificationDelegate.handle(action, identifier: identifier, on: shell)
                }
            }

            #expect(client.calls.add == 0, "a route from outside the window declared a server")
            #expect(client.calls.addForced == 0)
            #expect(client.calls.remove == 0)

            // The finding family's routes, walked as values as well as through the delegate — the
            // delegate can only be handed identifiers, and this reads what each one resolves to.
            for action in FindingNotificationAction.allCases {
                let route = FindingNotificationRoute.route(action, identifier: "f-1")
                #expect(
                    route.installs == false,
                    "\(action) resolves to \(route), which installs"
                )
            }
        }

        // MARK: - C4 · a finding press lands in the finding family and never in the arrival's

        /// The two families share a delegate and an identifier space they must not share meaning in.
        ///
        /// **The discriminator is the category the banner was posted under**, not the action
        /// identifier — because that is what macOS actually drew the buttons from. So this clause
        /// asserts the mapping the delegate uses in both directions: a finding identifier resolves in
        /// the finding set and nowhere in the arrival set, and an arrival identifier the other way.
        ///
        /// Driven on the resolvers and the routes rather than on `didReceive`, and that boundary is
        /// stated rather than glossed: `UNNotificationResponse` has no public initialiser, so nothing
        /// in this repo can construct one — the delegate's own `handle(_:identifier:on:)` overloads are
        /// what `nothingOutsideTheWindowInstalls` drives, and this is the resolution step above them.
        @Test("a finding press resolves in the finding family and an arrival press in the arrival's")
        func eachFamilyResolvesOnlyItsOwn() {
            for action in FindingNotificationAction.allCases {
                #expect(
                    FindingNotificationAction.resolve(
                        identifier: action.rawValue, isDefaultAction: false, isDismissAction: false
                    ) == action
                )
                #expect(
                    InboxNotificationAction(rawValue: action.rawValue) == nil,
                    "\(action.rawValue) resolves in the arrival family too"
                )
            }
            for action in InboxNotificationAction.allCases {
                #expect(
                    InboxNotificationAction.resolve(
                        identifier: action.rawValue, isDefaultAction: false, isDismissAction: false
                    ) == action
                )
                #expect(
                    FindingNotificationAction(rawValue: action.rawValue) == nil,
                    "\(action.rawValue) resolves in the finding family too"
                )
            }

            // The categories are disjoint too, which is what makes the delegate's discriminator sound.
            let arrival = Set(InboxNotificationCategory.allCases.map(\.rawValue))
            let finding = Set(FindingNotificationCategory.allCases.map(\.rawValue))
            #expect(arrival.isDisjoint(with: finding))
            for identifier in arrival {
                #expect(FindingNotificationCategory(rawValue: identifier) == nil)
            }
            for identifier in finding {
                #expect(InboxNotificationCategory(rawValue: identifier) == nil)
            }

            // And the two banner identifiers, which are what a route reads to decide "names no one".
            #expect(InboxAnnouncement.manyIdentifier != FindingAnnouncement.manyIdentifier)
        }

        /// A finding press reaches no inbox operation.
        ///
        /// The strongest available statement of C4's second half: the shell's own board is driven
        /// through every finding action and its queue is untouched — nothing dispositioned, nothing
        /// reviewed, nothing declared. Counted on a recording client, because a row that stayed is
        /// indistinguishable from a row that was put back.
        @Test("no finding press disposes of, reviews or installs a queued item")
        func findingPressTouchesNoQueuedItem() async throws {
            let client = RecordingControlAPIClient(wrapping: FixtureControlAPIClient(.populated))
            let shell = try ShellModel(
                client: client,
                notifier: RecordingArrivalNotifier(),
                inboxService: ScriptedInboxService([
                    .success(Self.snapshot([Self.item(id: "q-1", secondsAgo: 300, resolved: true)]))
                ])
            )
            await shell.inboxBoard.load()
            #expect(shell.inboxBoard.rows.count == 1, "the injected queue never loaded")

            // Both identifier shapes, and an identifier that collides with the queued item's own id —
            // the case that would matter if the delegate ever routed by identifier rather than family.
            for action in FindingNotificationAction.allCases {
                for identifier in ["f-1", FindingAnnouncement.manyIdentifier, "q-1"] {
                    InboxNotificationDelegate.handle(action, identifier: identifier, on: shell)
                }
            }

            #expect(shell.inboxBoard.rows.count == 1, "a finding press dispositioned a queued item")
            #expect(shell.inboxBoard.sheetItemID == nil, "a finding press opened an inbox review")
            #expect(client.calls.add == 0, "a finding press declared a server")
            #expect(client.calls.remove == 0)
        }

        /// D1's exception, exercised through the method the band actually calls.
        ///
        /// **Every one of the three conditions is failed alone against a control that satisfies all
        /// three**, and the install is counted on a recording client rather than inferred from a row
        /// disappearing — which is what a decline looks like too.
        ///
        /// The board is injected, because the factory's Debug default is the empty scenario and a
        /// clause that cannot reach `approveFromOutside` with something waiting would pass on a
        /// method that had been deleted.
        @Test("approving from the popover installs exactly once, and only under all three conditions")
        func approveFromPopoverInstallsExactlyOnce() async throws {
            /// One shell over one scripted queue, with `add` counted.
            func shell(
                _ items: [InboxItem],
                preference: Bool
            ) -> (ShellModel, RecordingControlAPIClient) {
                let client = RecordingControlAPIClient(wrapping: FixtureControlAPIClient(.populated))
                let model = ShellModel(
                    client: client,
                    notifier: RecordingArrivalNotifier(),
                    inboxService: ScriptedInboxService([.success(Self.snapshot(items))])
                )
                model.isApproveFromPopoverEnabled = preference
                return (model, client)
            }

            let resolved = try [Self.item(id: "q-1", secondsAgo: 300, resolved: true)]

            // The control: everything satisfied, so exactly one server is declared.
            let (control, controlClient) = shell(resolved, preference: true)
            await control.inboxBoard.load()
            #expect(control.inboxBoard.rows.count == 1, "the injected queue never loaded")
            await control.approveFromOutside(itemID: "q-1")
            #expect(controlClient.calls.add == 1, "the one designed install path did not install")
            #expect(controlClient.calls.addForced == 0, "force: true would adopt an existing server")
            #expect(control.inboxBoard.rows.isEmpty, "the item was installed and is no longer waiting")

            // 1 · the preference off.
            let (off, offClient) = shell(resolved, preference: false)
            await off.inboxBoard.load()
            await off.approveFromOutside(itemID: "q-1")
            #expect(offClient.calls.add == 0, "the preference did not gate the install")

            // 2 · the entry could not be read.
            let (partial, partialClient) = try shell(
                [Self.item(id: "q-1", secondsAgo: 300, resolved: false)], preference: true
            )
            await partial.inboxBoard.load()
            await partial.approveFromOutside(itemID: "q-1")
            #expect(partialClient.calls.add == 0, "an unread entry was installed")

            // 3 · the entry asks for a value the band has no field for.
            let (asks, asksClient) = try shell(
                [Self.itemAskingForAValue(id: "q-1")], preference: true
            )
            await asks.inboxBoard.load()
            #expect(asks.inboxBoard.rows.count == 1, "the requirement fixture never loaded")
            await asks.approveFromOutside(itemID: "q-1")
            #expect(asksClient.calls.add == 0, "a blank credential was sent to the router")

            // An id that is not waiting installs nothing and is not an error.
            let (absent, absentClient) = shell(resolved, preference: true)
            await absent.inboxBoard.load()
            await absent.approveFromOutside(itemID: "no-such-id")
            #expect(absentClient.calls.add == 0)
        }

        /// The review route opens the **sheet**, which is where what the item runs is on screen —
        /// so the press that installs is always made with the capability statement in front of it.
        @Test("the review route opens the sheet and installs nothing")
        func reviewOpensTheSheet() async throws {
            let notifier = RecordingArrivalNotifier()
            let items = try [Self.item(id: "q-1", secondsAgo: 300, resolved: true)]
            let (board, client) = Self.board([.success(Self.snapshot(items))], notifier: notifier)
            await board.load()

            #expect(board.review(itemID: "q-1"))
            #expect(board.sheetItemID == "q-1")
            #expect(board.acceptState == InboxBoardModel.AcceptState.idle)
            #expect(client.calls.add == 0)
        }
    }
#endif
