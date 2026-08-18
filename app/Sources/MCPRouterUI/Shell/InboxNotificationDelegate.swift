#if os(macOS)
    import MCPRouterKit
    import UserNotifications

    /// Receives a notification press and turns it into one operation on the shell.
    ///
    /// It decides nothing: `InboxNotificationAction.resolve` maps the response, and the two
    /// operations it can reach are `ShellModel`'s own — both of which a test calls directly. What is
    /// left here is the framework conformance, which is the same split `MenuBarRouter` uses.
    ///
    /// **Neither branch installs anything.** `review` opens the sheet where what the item runs is on
    /// screen; `decline` calls the router nothing. There is no third branch, because
    /// `InboxNotificationAction` has no third case.
    public final class InboxNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
        /// The one live delegate, and the shell it acts on.
        ///
        /// Both are statics rather than instance state, and that is a concurrency requirement rather
        /// than a shortcut: `UNUserNotificationCenter.delegate` is **weak**, so something has to hold
        /// the delegate — and the response callback is `nonisolated`, so reaching a stored
        /// `ShellModel` through `self` would send a non-`Sendable` reference across an actor
        /// boundary. A `@MainActor` static is reached *inside* the hop instead, so only the action
        /// and the identifier — both `Sendable` — cross it.
        private nonisolated(unsafe) static var installed: InboxNotificationDelegate?
        @MainActor private weak static var target: ShellModel?

        /// Attach to the notification centre, once.
        ///
        /// **Guarded on the bundle identifier**, and not defensively:
        /// `UNUserNotificationCenter.current()` traps in a process without one rather than failing,
        /// so an unguarded call here would take down any host that is not the app.
        @MainActor
        public static func install(on model: ShellModel, bundleIdentifier: String?) {
            guard ArrivalNotifierFactory.choose(bundleIdentifier: bundleIdentifier),
                  installed == nil
            else { return }
            let delegate = InboxNotificationDelegate()
            target = model
            installed = delegate
            UNUserNotificationCenter.current().delegate = delegate
        }

        public func userNotificationCenter(
            _: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse
        ) async {
            let action = InboxNotificationAction.resolve(
                identifier: response.actionIdentifier,
                isDefaultAction: response.actionIdentifier == UNNotificationDefaultActionIdentifier,
                isDismissAction: response.actionIdentifier == UNNotificationDismissActionIdentifier
            )
            guard let action else { return }
            let identifier = response.notification.request.identifier
            await MainActor.run { Self.handle(action, identifier: identifier) }
        }

        /// Deliver while the app is frontmost too.
        ///
        /// The default is to suppress it, which would mean the one moment you are *most* likely to
        /// be at the Mac is the one moment nothing tells you something arrived.
        ///
        /// **`.list` as well as `.banner`, and it is load-bearing rather than tidy.** Without it a
        /// frontmost delivery shows a banner and is never filed in Notification Center, so the
        /// withdrawal that runs when the item is dispositioned has nothing to withdraw — and the
        /// banner the user is looking at is the one that goes on offering `Decline` for an item that
        /// is gone.
        ///
        /// A static so it is assertable: this method's parameters can only be supplied by a real
        /// notification centre, and `UNUserNotificationCenter.current()` traps in a test process.
        public static let presentationOptions: UNNotificationPresentationOptions = [
            .banner, .list, .sound
        ]

        public func userNotificationCenter(
            _: UNUserNotificationCenter,
            willPresent _: UNNotification
        ) async -> UNNotificationPresentationOptions {
            Self.presentationOptions
        }

        @MainActor
        public static func handle(
            _ action: InboxNotificationAction,
            identifier: String,
            on model: ShellModel
        ) {
            // The mapping is `InboxNotificationRoute`'s, in the Kit, where a clause walks every
            // action against both identifier shapes. What is left here is which shell operation each
            // route names — and none of the three declares anything on this Mac.
            switch InboxNotificationRoute.route(action, identifier: identifier) {
            case .openInbox:
                MenuBarRouter.openInbox(on: model)
            case let .review(itemID):
                MenuBarRouter.revealInbox(itemID: itemID, on: model)
            case let .decline(itemID):
                // No activation and no window: declining from the couch is the whole point of it
                // being available here.
                model.declineFromOutside(itemID: itemID)
            }
        }

        @MainActor
        private static func handle(_ action: InboxNotificationAction, identifier: String) {
            guard let model = target else { return }
            handle(action, identifier: identifier, on: model)
        }
    }
#endif
