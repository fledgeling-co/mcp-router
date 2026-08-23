#if os(macOS)
    import MCPRouterKit
    import UserNotifications

    /// Which notifier the shell talks to, and the one condition that decides it.
    ///
    /// `UNUserNotificationCenter.current()` **traps** in a process with no bundle identifier rather
    /// than returning nil or throwing — and every `swift test` run is such a process. A concrete
    /// dependency on it would take the whole suite down instead of failing one assertion, so the
    /// choice is made here where a test can drive it with the identifier passed in.
    ///
    /// The same shape `ShellClientFactory` and `ShellPairingFactory` use, for the same reason: a
    /// decision that lives in an app target is a decision `swift test` cannot reach.
    public enum ArrivalNotifierFactory {
        /// - Parameter bundleIdentifier: the process's own identifier, supplied by the app target
        ///   and by nothing else. `nil` means there is no notification centre to talk to.
        ///
        /// **It is a parameter with no default, and A36 is why.** The shell's one-channel gate
        /// forbids naming the resource-reading framework in these files, because reading a bundled
        /// resource is how a surface comes to render something no router observed. Reading the
        /// process's own identifier is not that — but the honest response to a blunt gate whose
        /// reason is good is to satisfy it rather than to carve an exception into it, so the
        /// identity is passed in from the assembly file that already knows it. The gate is a source
        /// grep, which is why this comment does not spell the name either.
        public static func choose(bundleIdentifier: String?) -> Bool {
            bundleIdentifier != nil
        }

        public static func make(bundleIdentifier: String?) -> any ArrivalNotifier {
            choose(bundleIdentifier: bundleIdentifier)
                ? UserNotificationArrivalNotifier()
                : SilentArrivalNotifier()
        }
    }

    /// The real one.
    ///
    /// It carries no decisions: what the banner says, which actions it offers and when it fires were
    /// all settled in `MCPRouterKit`, where a test calls them. What is left here is the framework
    /// call — which is exactly the split `MenuBarRouter` uses for the popover's activation.
    public struct UserNotificationArrivalNotifier: ArrivalNotifier {
        public init() {}

        /// The category every inbox banner is posted under, so the two actions are registered once
        /// rather than per notification.
        ///
        /// **Two of them, and the second one is a fix.** One category for every banner meant macOS
        /// drew `Decline` on the many-item banner while its value said `[.review]` — the spec forbids
        /// that button and the assertion over the value was green against it, because the value is
        /// not what the system draws from. Which category a banner takes is
        /// ``InboxNotificationCategory``'s decision, in the Kit, where a test walks every
        /// announcement the app can build.
        public static func category(_ category: InboxNotificationCategory) -> UNNotificationCategory {
            UNNotificationCategory(
                identifier: category.rawValue,
                // Built from the category's own action list rather than restated, so the buttons
                // macOS draws and the buttons the value promises are one statement.
                actions: category.actions.map(action(for:)),
                intentIdentifiers: [],
                options: []
            )
        }

        /// The category a finding banner is posted under. `FindingNotificationCategory`'s own action
        /// list, for the same reason: the buttons macOS draws and the buttons the value promises are
        /// one statement rather than two that can drift.
        public static func category(
            _ category: FindingNotificationCategory
        ) -> UNNotificationCategory {
            UNNotificationCategory(
                identifier: category.rawValue,
                actions: category.actions.map(action(for:)),
                intentIdentifiers: [],
                options: []
            )
        }

        /// Every category this app registers — **both families**.
        ///
        /// **Neither action set has a case that installs**, so no category of either family can list
        /// one. That is the enforcement: not a comment asking nobody to add an Install button, but an
        /// action set with nothing in it to register. `FindingNotificationAction.install` is not a
        /// counter-example — `plan-M20.md` §3.3 settles that its `Install…` opens the board where the
        /// entry is on screen, and `FindingNotificationRoute.installs` is `false` in every arm.
        ///
        /// Built by mapping each family's `allCases` rather than by listing four identifiers, so a
        /// category added to either enum is registered without anyone remembering to come here.
        public static func categories() -> [UNNotificationCategory] {
            InboxNotificationCategory.allCases.map(category)
                + FindingNotificationCategory.allCases.map(category)
        }

        /// One `UNNotificationAction` per case of the closed set, so a button on screen and a branch
        /// the app has cannot drift apart.
        static func action(for action: InboxNotificationAction) -> UNNotificationAction {
            switch action {
            case .review:
                UNNotificationAction(
                    identifier: InboxNotificationAction.review.rawValue,
                    title: InboxCopy.Arrival.reviewAction,
                    // Foreground: the review is a window, and a sheet behind an unactivated app
                    // is a sheet nobody can reach. M8's held-change route, same reasoning.
                    options: [.foreground]
                )
            case .decline:
                UNNotificationAction(
                    identifier: InboxNotificationAction.decline.rawValue,
                    title: InboxCopy.Arrival.declineAction,
                    // Declining needs no window. It calls the router nothing and is reversible
                    // through the same single-slot undo the pane uses.
                    options: []
                )
            }
        }

        /// One `UNNotificationAction` per case of the finding set.
        ///
        /// `Install…` is `.foreground` because the board it opens is a window, and a board behind an
        /// unactivated app is a board nobody can reach — the same reasoning `review` carries.
        /// `Dismiss` needs no window: it lets the banner go and does nothing else.
        static func action(for action: FindingNotificationAction) -> UNNotificationAction {
            UNNotificationAction(
                identifier: action.rawValue,
                title: FindingCopy.action(action),
                options: action == .dismiss ? [] : [.foreground]
            )
        }

        /// The content of one banner, built without touching the notification centre so a test can
        /// read the category identifier a banner would actually be posted under.
        public static func content(for announcement: InboxAnnouncement) -> UNMutableNotificationContent {
            let content = UNMutableNotificationContent()
            content.title = announcement.title
            content.subtitle = announcement.subtitle
            content.body = announcement.body
            // An action set no category draws gets no category, which means a banner with no
            // buttons. `make` builds no such set — the walk over everything it can build asserts
            // that — and the degradation is the safe one: with no buttons the only press left is the
            // default, which is `Review`.
            content.categoryIdentifier = announcement.category?.rawValue ?? ""
            return content
        }

        /// A finding banner's content. `InboxAnnouncement`'s treatment, and the same degradation for
        /// an action set no category draws: no category means a banner with no buttons, which leaves
        /// only the default press.
        public static func content(
            for announcement: FindingAnnouncement
        ) -> UNMutableNotificationContent {
            let content = UNMutableNotificationContent()
            content.title = announcement.title
            content.subtitle = announcement.subtitle
            content.body = announcement.body
            content.categoryIdentifier = announcement.category?.rawValue ?? ""
            return content
        }

        public func requestAuthorization() async -> Bool {
            let centre = UNUserNotificationCenter.current()
            centre.setNotificationCategories(Set(Self.categories()))
            // `.alert` and `.sound` only. No badge: the app's own menu-bar dot is the count-free
            // indicator this product already decided on, and a Dock badge would be a second one
            // saying the same thing in a different vocabulary.
            let granted = try? await centre.requestAuthorization(options: [.alert, .sound])
            return granted ?? false
        }

        public func announce(_ announcement: InboxAnnouncement) async {
            // No trigger: deliver now. A queued item is already waiting, so scheduling it later
            // would mean announcing a thing that arrived at a time it did not.
            let request = UNNotificationRequest(
                identifier: announcement.id,
                content: Self.content(for: announcement),
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }

        public func withdraw(itemIDs: [String]) async {
            let centre = UNUserNotificationCenter.current()
            // Both, because a delivered banner and a pending request are different objects and an
            // item can be dispositioned before its request has been delivered.
            centre.removeDeliveredNotifications(withIdentifiers: itemIDs)
            centre.removePendingNotificationRequests(withIdentifiers: itemIDs)
        }
    }
#endif
