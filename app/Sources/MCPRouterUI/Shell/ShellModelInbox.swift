#if os(macOS)
    import Foundation
    import MCPRouterKit

    /// The shell's inbox reach: the loop that keeps the queue live while the window is closed, and
    /// the two routes back in from a surface that is not the window.
    ///
    /// Split out of `ShellModel.swift` to keep it under the 400-line limit — the limit was met by
    /// splitting rather than raised, per this repo's own lesson from R2R — and split on this seam
    /// rather than an arbitrary one, following `ShellModelBadges.swift`'s precedent: everything here
    /// is about the inbox being reached from outside the window.
    public extension ShellModel {
        /// The board the shell hands every inbox surface.
        ///
        /// A static on this extension rather than three lines in `init`, and the seam is the same
        /// one the rest of this file sits on: which inbox the shell talks to is an inbox decision,
        /// and `ShellModel.swift` is at its length budget. `ShellPairingFactory` is what decides a
        /// Release build gets `NoTransportInboxService`, and keeping that call here means the rule
        /// and its one caller are read together.
        /// - Parameter service: the inbox to read. `nil` takes `ShellPairingFactory`'s choice, which
        ///   is what the app always passes. It is injectable for exactly one reason: `D1` — *no path
        ///   outside the window installs anything except popover `Approve`* — has to be driven through
        ///   `approveFromOutside` with something genuinely waiting, and the factory's Debug default is
        ///   the empty scenario. A clause that cannot reach the method it is about is the failure
        ///   `InboxNotificationRoute` was extracted from the delegate to fix.
        static func makeInboxBoard(
            client: any ControlAPIClient,
            notifier: any ArrivalNotifier,
            service: (any InboxService)? = nil
        ) -> InboxBoardModel {
            InboxBoardModel(
                client: client,
                service: service ?? ShellPairingFactory.makeService(),
                notifier: notifier
            )
        }

        /// The inbox's loop, and the reason it exists at all.
        ///
        /// M8 moved the *server* poll off the window's `.task` because the menu bar outlives the
        /// window. The inbox had the same problem and nobody had noticed it, because until this item
        /// the inbox had no surface outside the window: `InboxBoard`'s own `.task` was the only
        /// thing that ever called `load()`, so with the window closed — a menu-bar app's normal
        /// state — nothing arrived, nothing was announced, and the band would have been permanently
        /// empty however full the queue was.
        ///
        /// Same cadence as the servers poll. The queue is local, so this is a read of this Mac's own
        /// state rather than a request over a wire.
        ///
        /// Idempotent for the same reason `startPolling` is, and separately cancellable so a test
        /// can end it.
        func startInboxPolling() {
            guard inboxTask == nil else { return }
            inboxTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.inboxBoard.load()
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: Self.pollInterval)
                }
            }
        }

        /// Ends it. Paired with ``startInboxPolling()`` and called from `stopPolling()`, so the two
        /// loops the shell owns are started and stopped together rather than one of them being a
        /// line somebody has to remember.
        func stopInboxPolling() {
            inboxTask?.cancel()
            inboxTask = nil
        }

        /// Put a queued item in front of the user, from the popover or from a notification.
        ///
        /// The inbox counterpart of ``reveal(server:openingHeldChange:)``, and it stops in the same
        /// place: it selects, it opens the **review**, and it installs nothing. The sheet is what
        /// accepts, and the sheet is where what the item runs is on screen — so the press that
        /// declares code on this Mac is always made with the capability statement in front of it,
        /// whichever surface the user came from.
        ///
        /// An id that is no longer waiting still lands on Inbox, opens no sheet, and reports why.
        /// That is a designed state: a banner can be pressed between a disposition and its
        /// withdrawal, and the outcome the user wanted already happened.
        func revealInbox(itemID: String) {
            selection = .inbox
            inboxBoard.review(itemID: itemID)
        }

        /// Decline a queued item from outside the window. Calls the router nothing, opens nothing,
        /// and does not activate the app — which is the whole point of it being available here.
        func declineFromOutside(itemID: String) {
            inboxBoard.decline(itemID: itemID)
        }

        /// Install a queued item from the popover's band, without opening the window.
        ///
        /// **The one path outside the window that declares code on this Mac**, and every condition on
        /// it is re-checked here rather than assumed from the button having been drawn:
        ///
        /// 1. ``isApproveFromPopoverEnabled`` — the Settings preference. Re-read at the press, so
        ///    turning it off while the popover is open cannot be raced.
        /// 2. `AcceptableInboxItem(_:)` returns `nil` for an item whose registry entry this Mac could
        ///    not read, so an unresolved item cannot reach the installer at all — the type enforces
        ///    it rather than a check somebody has to remember.
        /// 3. `InboxBand.canApprove` — nothing the entry asks for is still blank. The band has no
        ///    fields, and `RegistryCapability.declaration(for:values:)` drops empty values rather than
        ///    refusing them, so without this a press here would send a credential-less declaration.
        ///
        /// Checking them twice is deliberate. The band's `isApprovable` decides what is *drawn*, and
        /// this decides what *happens* — one is a presentation rule and the other is the gate. A guard
        /// that exists only in the view is a guard a second call site removes silently, and
        /// `InboxArrivalTests.nothingOutsideTheWindowInstalls` drives this method rather than the view.
        ///
        /// It goes through `InboxBoardModel.accept(_:)` — **the board's existing install path, not a
        /// second one.** `requirementValues` is whatever the sheet last held, which is empty on this
        /// route, and condition 3 is what makes that safe.
        func approveFromOutside(itemID: String) async {
            guard isApproveFromPopoverEnabled,
                  let item = inboxBoard.rows.first(where: { $0.id == itemID }),
                  InboxBand.canApprove(item),
                  let acceptable = AcceptableInboxItem(item)
            else { return }
            await inboxBoard.accept(acceptable)
        }
    }
#endif
