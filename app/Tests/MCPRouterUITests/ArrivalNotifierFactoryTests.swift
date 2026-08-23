#if os(macOS)
    import Foundation
    import Testing
    import UserNotifications
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// A18, and the half of the boundary that A8 cannot reach.
    ///
    /// A8 asserts over `InboxAnnouncement.actions` — the value the app builds. The buttons macOS
    /// actually draws come from `UNNotificationCategory`, which is a *different object* built in a
    /// different file, and nothing previously compared the two. A category that registered an
    /// install action would put an install button on the banner however clean the announcement was,
    /// so the closed action set is asserted here on the framework object itself.
    @Suite("I6 · the notifier seam and the buttons macOS is actually given")
    struct ArrivalNotifierFactoryTests {
        // MARK: - A18 · the guard that keeps the suite runnable

        /// `UNUserNotificationCenter.current()` traps in a process with no bundle identifier, and
        /// every `swift test` run is such a process. This is the branch that keeps that call
        /// unreached.
        @Test("no bundle identifier means the silent notifier, so nothing reaches the trap")
        func noBundleIdentifierIsSilent() {
            #expect(ArrivalNotifierFactory.choose(bundleIdentifier: nil) == false)
            #expect(ArrivalNotifierFactory.make(bundleIdentifier: nil) is SilentArrivalNotifier)
        }

        @Test("a real bundle identifier reaches the real notifier")
        func aBundleIdentifierIsReal() {
            #expect(ArrivalNotifierFactory.choose(bundleIdentifier: "gg.rhodes.MCPRouter"))
            let notifier = ArrivalNotifierFactory.make(bundleIdentifier: "gg.rhodes.MCPRouter")
            #expect(notifier is UserNotificationArrivalNotifier)
        }

        /// An empty string is a bundle identifier as far as `nil`-checking goes, and this records
        /// which way that falls rather than leaving it to be discovered. It reaches the real
        /// notifier: an empty identifier is not a state a bundled app can be in, and treating it as
        /// "no bundle" would be a second rule inferred from a value rather than from the seam.
        @Test("the choice turns on presence, not on content")
        func choiceTurnsOnPresence() {
            #expect(ArrivalNotifierFactory.choose(bundleIdentifier: ""))
        }

        // MARK: - The action set macOS is handed

        /// A queued item, built here rather than borrowed from `InboxArrivalTests`: that suite is
        /// `@MainActor` and this one is not, and hopping actors to build a fixture would be
        /// ceremony for a value.
        static func item(id: String) throws -> InboxItem {
            let json = """
            {"id":"e","name":"e","displayName":"Local notes","description":"d","source":"official",
             "install":{"type":"stdio","command":"node","args":["s.js"]}}
            """
            return try InboxItem(
                envelope: InboxEnvelope(
                    version: 1,
                    id: id,
                    entryID: "entry-\(id)",
                    displayName: "Item \(id)",
                    queuedAt: Date(),
                    deviceName: "Luke's iPhone"
                ),
                resolved: JSONDecoder().decode(RegistryEntry.self, from: Data(json.utf8))
            )
        }

        /// C2 · every registered category, in **both** families, offers exactly what its value says.
        ///
        /// Two things are asserted per category and they are different claims: that every button
        /// macOS is handed resolves back to a case of the enum the delegate switches over, and that
        /// the *list* matches the Kit's own statement of it. The first stops a button existing with
        /// no branch behind it; the second stops the two lists drifting, which is the failure
        /// `InboxNotificationCategory` was added to close.
        ///
        /// **The registered set is checked against the sum of both families rather than against a
        /// literal 4.** A count written by hand goes stale the moment a category is added, and the
        /// staleness reads as a pass.
        @Test("every registered category offers nothing that installs, across both families")
        func categoriesRegisterNoInstall() throws {
            let categories = UserNotificationArrivalNotifier.categories()
            #expect(
                categories.count
                    == InboxNotificationCategory.allCases.count + FindingNotificationCategory.allCases.count
            )
            #expect(
                Set(categories.map(\.identifier)).count == categories.count,
                "two categories share an identifier, so one of them draws the other's buttons"
            )

            var seenArrival = 0
            var seenFinding = 0
            for category in categories {
                let identifiers = category.actions.map(\.identifier)

                if let declared = InboxNotificationCategory(rawValue: category.identifier) {
                    seenArrival += 1
                    for identifier in identifiers {
                        #expect(InboxNotificationAction(rawValue: identifier) != nil)
                    }
                    #expect(identifiers == declared.actions.map(\.rawValue))
                } else if let declared = FindingNotificationCategory(rawValue: category.identifier) {
                    seenFinding += 1
                    for identifier in identifiers {
                        #expect(FindingNotificationAction(rawValue: identifier) != nil)
                        // The other family's set must not resolve it. The two identifier spaces are
                        // disjoint today and the delegate picks a family by category, so a shared raw
                        // value would make one family's press readable as the other's.
                        #expect(
                            InboxNotificationAction(rawValue: identifier) == nil,
                            "\(identifier) resolves in both families"
                        )
                    }
                    #expect(identifiers == declared.actions.map(\.rawValue))
                    // `install` is registered and installs nothing: the route is what proves it.
                    for identifier in identifiers {
                        let action = try #require(FindingNotificationAction(rawValue: identifier))
                        #expect(!FindingNotificationRoute.route(action, identifier: "f-1").installs)
                    }
                } else {
                    Issue.record(
                        "a category is registered that neither family declares: \(category.identifier)"
                    )
                }
            }
            // Both arms were entered, so a family silently dropped from `categories()` fails here
            // rather than passing on a loop that never ran.
            #expect(seenArrival == InboxNotificationCategory.allCases.count)
            #expect(seenFinding == FindingNotificationCategory.allCases.count)
        }

        /// C2's other half for the finding family: the buttons macOS draws are the buttons the
        /// announcement promises, walked over every announcement `make` can build.
        @Test("the buttons macOS draws on a finding are the buttons the finding offers")
        func drawnButtonsMatchTheFinding() throws {
            let one = try #require(FindingAnnouncement.make(findings: [Self.finding(id: "f-1")]))
            let many = try #require(
                FindingAnnouncement.make(
                    findings: [Self.finding(id: "f-1"), Self.finding(id: "f-2")]
                )
            )

            for announcement in [one, many] {
                let declared = try #require(
                    announcement.category,
                    "no category draws \(announcement.actions)"
                )
                let drawn = UserNotificationArrivalNotifier.category(declared)
                #expect(drawn.actions.map(\.identifier) == announcement.actions.map(\.rawValue))
                #expect(
                    UserNotificationArrivalNotifier.content(for: announcement).categoryIdentifier
                        == declared.rawValue,
                    "the banner would be posted under a category that draws different buttons"
                )
            }

            // The forbidden button, asserted where it is decided rather than on the value alone.
            let manyDrawn = UserNotificationArrivalNotifier.category(FindingNotificationCategory.many)
            #expect(
                manyDrawn.actions.contains {
                    $0.identifier == FindingNotificationAction.install.rawValue
                } == false,
                "a banner naming several findings drew an Install for an entry it does not name"
            )
        }

        /// `Install…` comes forward because the board it opens is a window; `Dismiss` must not,
        /// because it opens nothing at all.
        @Test("a finding's Install comes forward and its Dismiss stays where you are")
        func findingActionOptionsMatchTheirDestinations() throws {
            let category = UserNotificationArrivalNotifier.category(FindingNotificationCategory.single)
            let byID = Dictionary(
                uniqueKeysWithValues: category.actions.map { ($0.identifier, $0) }
            )
            let install = try #require(byID[FindingNotificationAction.install.rawValue])
            let details = try #require(byID[FindingNotificationAction.details.rawValue])
            let dismiss = try #require(byID[FindingNotificationAction.dismiss.rawValue])

            #expect(install.options.contains(.foreground))
            #expect(details.options.contains(.foreground))
            #expect(dismiss.options.contains(.foreground) == false)
            // None is destructive. Dismissing a suggestion destroys nothing, and marking it
            // destructive would tell the user that it does.
            for action in [install, details, dismiss] {
                #expect(action.options.contains(.destructive) == false)
            }
        }

        /// A finding, built here for the reason `item(id:)` is built here.
        static func finding(id: String) -> AnalystFinding {
            AnalystFinding(
                id: id,
                entryID: "docker-mcp",
                subject: "docker-mcp",
                sentence: "You ran docker logs by hand 14 times this week.",
                evidenceCount: 14
            )
        }

        /// **The button the spec forbade, asserted where it is actually decided.**
        ///
        /// `InboxAnnouncement.actions` says `[.review]` for a many-item banner, but macOS draws
        /// buttons from the `UNNotificationCategory` the request is stamped with — a different
        /// object in a different file. One category for every banner therefore drew `Decline` on the
        /// many-item banner while the value said it did not, and the assertion over the value was
        /// green against it. This walks the announcements the app can actually build and compares
        /// the value to the buttons the system is handed for it.
        @Test("the buttons macOS draws are the buttons the announcement offers")
        func drawnButtonsMatchTheAnnouncement() throws {
            let single = try #require(
                InboxAnnouncement.make(
                    arrivals: [Self.item(id: "q-1")],
                    device: "Luke's iPhone"
                )
            )
            let many = try #require(
                InboxAnnouncement.make(
                    arrivals: [Self.item(id: "q-1"), Self.item(id: "q-2")],
                    device: "Luke's iPhone"
                )
            )

            for announcement in [single, many] {
                let identifier = UserNotificationArrivalNotifier
                    .content(for: announcement).categoryIdentifier
                let category = try #require(
                    UserNotificationArrivalNotifier.categories()
                        .first { $0.identifier == identifier },
                    "the banner is stamped with a category nothing registers"
                )
                #expect(
                    category.actions.map(\.identifier) == announcement.actions.map(\.rawValue),
                    "macOS draws buttons this banner does not offer"
                )
            }

            // Said again in its own terms, so the clause fails on the spec sentence rather than only
            // on a mismatch: no `Decline` on the many-item notification (spec-I6.md §"What it says").
            let manyCategory = try #require(
                UserNotificationArrivalNotifier.categories()
                    .first { $0.identifier == InboxNotificationCategory.many.rawValue }
            )
            #expect(
                manyCategory.actions.contains {
                    $0.identifier == InboxNotificationAction.decline.rawValue
                } == false
            )
        }

        /// The review button carries `.foreground` because its destination is a window; the decline
        /// button must not, because declining without a window is the whole reason it is offered
        /// here rather than only in the pane.
        @Test("review comes forward and decline stays where you are")
        func actionOptionsMatchTheirDestinations() throws {
            // Named rather than inferred: M20 adds a second family whose category enum also has a
            // `single`, so a bare `.single` no longer says which one this clause is about.
            let category = UserNotificationArrivalNotifier.category(InboxNotificationCategory.single)
            let review = try #require(
                category.actions.first { $0.identifier == InboxNotificationAction.review.rawValue }
            )
            let decline = try #require(
                category.actions.first { $0.identifier == InboxNotificationAction.decline.rawValue }
            )

            #expect(review.options.contains(.foreground))
            #expect(decline.options.contains(.foreground) == false)
            // Neither is destructive: a decline is reversible through the single-slot undo, and
            // marking it destructive would tell the user it is not.
            #expect(review.options.contains(.destructive) == false)
            #expect(decline.options.contains(.destructive) == false)
        }

        /// **`.list` is what makes the withdrawal reachable.** A frontmost delivery without it shows
        /// a banner and is never filed in Notification Center, so the withdrawal that runs when the
        /// item is dispositioned has nothing to remove — and the banner on screen goes on offering
        /// `Decline` for an item that is gone.
        @Test("a frontmost delivery is filed as well as shown")
        func frontmostDeliveryIsAlsoFiled() {
            let options = InboxNotificationDelegate.presentationOptions
            #expect(options.contains(.banner))
            #expect(options.contains(.list))
            #expect(options.contains(.sound))
        }

        // MARK: - The silent notifier

        /// **Not the implementation a Release build runs.** An earlier version of this comment said
        /// it was; Release passes `Bundle.main.bundleIdentifier` into `ArrivalNotifierFactory.make`
        /// and gets `UserNotificationArrivalNotifier`. Silence in Release comes from the empty
        /// `NoTransportInboxService` snapshot — nothing arrives, so nothing announces — and not from
        /// this type. What this type is for is a process with no notification centre to talk to,
        /// which is every `swift test` run.
        @Test("the silent notifier grants nothing")
        func silentNotifierGrantsNothing() async {
            let notifier = SilentArrivalNotifier()
            #expect(await notifier.requestAuthorization() == false)
        }

        /// Reachability, and it is stated as reachability rather than as inertness.
        ///
        /// The earlier version called `announce` and `withdraw` and asserted nothing about either,
        /// which reads as a check on their behaviour and is not one — there is no observable to
        /// check. What is real here is that both return from a process with no notification centre,
        /// which is the property that keeps the suite runnable, and it fails by hanging or trapping
        /// rather than by an expectation.
        @Test("announce and withdraw return in a process with no notification centre")
        func silentNotifierIsReachableWithoutACentre() async {
            let notifier = SilentArrivalNotifier()
            await notifier.announce(
                InboxAnnouncement(
                    id: "q-1",
                    title: "Local notes",
                    subtitle: "Queued from Luke's iPhone",
                    body: "Runs a program on this Mac",
                    actions: [.review, .decline],
                    itemIDs: ["q-1"]
                )
            )
            await notifier.withdraw(itemIDs: ["q-1"])
        }
    }
#endif
