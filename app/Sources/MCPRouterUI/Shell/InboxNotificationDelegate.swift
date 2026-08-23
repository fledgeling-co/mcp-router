#if os(macOS)
    import MCPRouterKit
    import UserNotifications

    /// Receives a notification press and turns it into one operation on the shell.
    ///
    /// It decides nothing: `InboxNotificationAction.resolve` maps the response, and the two
    /// operations it can reach are `ShellModel`'s own — both of which a test calls directly. What is
    /// left here is the framework conformance, which is the same split `MenuBarRouter` uses.
    ///
    /// **No branch installs anything.** `review` opens the sheet where what the item runs is on
    /// screen; `decline` calls the router nothing; and the finding family's three land on a board or
    /// on nothing at all. `InboxNotificationRoute` and `FindingNotificationRoute` are what decide
    /// that, in the Kit, where a clause walks every case of both.
    ///
    /// **Two families, resolved by which category the banner was posted under.** The families are
    /// deliberately not merged: `InboxNotificationAction` is left byte-identical so its own
    /// enforcement goes on meaning what it meant, and the identifier space is disjoint because a
    /// category id decides it — `inbox.arrival*` against `finding.analyst*`. Resolving by category
    /// rather than by trying one action set and falling back to the other is what stops a
    /// same-spelled identifier in one family being read as the other's: there is no shared raw value
    /// today, and a `decline` that arrived under a finding category must be dropped rather than
    /// guessed at.
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
            let isDefault = response.actionIdentifier == UNNotificationDefaultActionIdentifier
            let isDismiss = response.actionIdentifier == UNNotificationDismissActionIdentifier
            let identifier = response.notification.request.identifier
            // Which family, read off the category the banner was actually posted under rather than
            // guessed from the action identifier. `content.categoryIdentifier` is what macOS drew the
            // buttons from, so it is also the only honest answer to which action set they came from.
            let category = response.notification.request.content.categoryIdentifier

            if FindingNotificationCategory(rawValue: category) != nil {
                let action = FindingNotificationAction.resolve(
                    identifier: response.actionIdentifier,
                    isDefaultAction: isDefault,
                    isDismissAction: isDismiss
                )
                guard let action else { return }
                await MainActor.run { Self.handle(action, identifier: identifier) }
                return
            }

            // Everything else is the arrival family, including a banner whose category could not be
            // read: that is what shipped before findings existed, so an unrecognised category keeps
            // the behaviour it has always had rather than being dropped.
            let action = InboxNotificationAction.resolve(
                identifier: response.actionIdentifier,
                isDefaultAction: isDefault,
                isDismissAction: isDismiss
            )
            guard let action else { return }
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

        /// The finding family's half. Same split: the mapping is `FindingNotificationRoute`'s, and
        /// what is left here is which shell operation each route names.
        ///
        /// **Two of the four routes land on the Inbox board and neither focuses the finding, and that
        /// is a stated gap rather than a silent one.** `PRD.md` §6.4 puts the recommendation card in
        /// the Mac's Inbox, and the board has no card to focus because the analyst that produces
        /// findings is out of this item's scope (`plan-M20.md` §8). Nothing is misleading anybody in
        /// the meantime, because **nothing in either target constructs an `AnalystFinding`** — see
        /// `FindingArrival.swift`. When the producer ships, the finding id these routes already carry
        /// is what the board focuses on.
        ///
        /// `dismiss` deliberately does nothing beyond letting the banner go. Pressing it *is* closing
        /// the banner, which macOS does for any action press, and there is no finding store to record
        /// a dismissal in until the analyst brings one.
        @MainActor
        public static func handle(
            _ action: FindingNotificationAction,
            identifier: String,
            on model: ShellModel
        ) {
            switch FindingNotificationRoute.route(action, identifier: identifier) {
            case .openInbox, .reviewCapability, .explainFinding:
                MenuBarRouter.openInbox(on: model)
            case .dismiss:
                break
            }
        }

        @MainActor
        private static func handle(_ action: FindingNotificationAction, identifier: String) {
            guard let model = target else { return }
            handle(action, identifier: identifier, on: model)
        }
    }
#endif
