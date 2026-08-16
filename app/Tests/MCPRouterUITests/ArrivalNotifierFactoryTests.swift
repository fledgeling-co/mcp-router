#if os(macOS)
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

        @Test("the registered category offers review and decline, and nothing that installs")
        func categoryRegistersNoInstall() {
            let category = UserNotificationArrivalNotifier.category()
            let identifiers = category.actions.map(\.identifier)

            #expect(identifiers == [
                InboxNotificationAction.review.rawValue,
                InboxNotificationAction.decline.rawValue
            ])
            // Stated as a count as well as an equality, so a third action appended to the end
            // fails on its own terms rather than only through the ordering assertion.
            #expect(category.actions.count == InboxNotificationAction.allCases.count)

            // The closed set is the enforcement: every registered button must resolve back to a
            // case of the enum the delegate switches over, so a button macOS draws and a branch
            // the app has cannot drift apart.
            for identifier in identifiers {
                #expect(InboxNotificationAction(rawValue: identifier) != nil)
            }
        }

        /// The review button carries `.foreground` because its destination is a window; the decline
        /// button must not, because declining without a window is the whole reason it is offered
        /// here rather than only in the pane.
        @Test("review comes forward and decline stays where you are")
        func actionOptionsMatchTheirDestinations() throws {
            let category = UserNotificationArrivalNotifier.category()
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

        // MARK: - The silent notifier is genuinely inert

        /// It is the implementation a Release build runs today, so "it does nothing" is a claim
        /// about shipped behaviour rather than about a test double.
        @Test("the silent notifier grants nothing and announces nothing")
        func silentNotifierIsInert() async {
            let notifier = SilentArrivalNotifier()
            let granted = await notifier.requestAuthorization()
            #expect(granted == false)
            // Neither call has an observable effect to assert on; that they return at all, from a
            // process with no notification centre, is the property being fixed.
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
