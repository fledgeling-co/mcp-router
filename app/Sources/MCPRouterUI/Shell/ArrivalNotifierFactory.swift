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
        public static let categoryIdentifier = "inbox.arrival"

        /// The category, built from the same closed action set the router resolves against — so a
        /// button that exists on screen and a button the app knows how to handle cannot drift apart.
        ///
        /// **`InboxNotificationAction` has no install case**, so this cannot register one. That is
        /// the enforcement: not a comment asking nobody to add an Install button, but an action set
        /// with nothing in it to register.
        public static func category() -> UNNotificationCategory {
            UNNotificationCategory(
                identifier: categoryIdentifier,
                actions: [
                    UNNotificationAction(
                        identifier: InboxNotificationAction.review.rawValue,
                        title: InboxCopy.Arrival.reviewAction,
                        // Foreground: the review is a window, and a sheet behind an unactivated app
                        // is a sheet nobody can reach. M8's held-change route, same reasoning.
                        options: [.foreground]
                    ),
                    UNNotificationAction(
                        identifier: InboxNotificationAction.decline.rawValue,
                        title: InboxCopy.Arrival.declineAction,
                        // Declining needs no window. It calls the router nothing and is reversible
                        // through the same single-slot undo the pane uses.
                        options: []
                    )
                ],
                intentIdentifiers: [],
                options: []
            )
        }

        public func requestAuthorization() async -> Bool {
            let centre = UNUserNotificationCenter.current()
            centre.setNotificationCategories([Self.category()])
            // `.alert` and `.sound` only. No badge: the app's own menu-bar dot is the count-free
            // indicator this product already decided on, and a Dock badge would be a second one
            // saying the same thing in a different vocabulary.
            let granted = try? await centre.requestAuthorization(options: [.alert, .sound])
            return granted ?? false
        }

        public func announce(_ announcement: InboxAnnouncement) async {
            let content = UNMutableNotificationContent()
            content.title = announcement.title
            content.subtitle = announcement.subtitle
            content.body = announcement.body
            content.categoryIdentifier = Self.categoryIdentifier
            // No trigger: deliver now. A queued item is already waiting, so scheduling it later
            // would mean announcing a thing that arrived at a time it did not.
            let request = UNNotificationRequest(
                identifier: announcement.id,
                content: content,
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
