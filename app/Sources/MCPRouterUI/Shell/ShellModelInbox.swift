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
    }
#endif
