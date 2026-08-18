#if os(macOS)
    import AppKit
    import MCPRouterKit

    /// What pressing a row in the menu-bar popover does.
    ///
    /// Here rather than in `app/MCPRouter/MCPRouterApp.swift` for the reason that file states about
    /// itself: it is not a SwiftPM target, so a decision written there is a decision `swift test`
    /// cannot reach. `ShellCommandRouter` exists for exactly this on the menu-bar-menu side, and
    /// `ShellCommandRouterTests.assemblyCarriesNoOperation` greps the Scene to keep it honest. This
    /// is the same arrangement for the status item.
    ///
    /// The activation is the one in the app that is legitimate. Everywhere else the popover *is* the
    /// surface; here the destination is a window, and a sheet opened behind an unactivated
    /// menu-bar popover is a sheet nobody can reach.
    public enum MenuBarRouter {
        /// Put a server in front of the user, activating the app first.
        ///
        /// `NSApp.activate` and the window ordering are the only AppKit here; the state change
        /// itself is `ShellModel.reveal`, where a test asserts it.
        @MainActor
        public static func reveal(_ row: MenuBarPresentation.AttentionRow, on model: ShellModel) {
            NSApp?.activate(ignoringOtherApps: true)
            bringWindowForward()
            Task { await model.reveal(server: row.server, openingHeldChange: row.opensHeldChangeSheet) }
        }

        /// Open the main window from the popover's one action.
        @MainActor
        public static func openWindow() {
            NSApp?.activate(ignoringOtherApps: true)
            bringWindowForward()
        }

        /// Put a queued item's **review** in front of the user, activating the app first.
        ///
        /// The second legitimate activation in the app, and it is legitimate for exactly M8's
        /// reason: the destination is a window. The review sheet is where what an item runs is on
        /// screen, and a sheet behind an unactivated menu-bar popover is a sheet nobody can reach.
        ///
        /// **This opens a review and installs nothing.** Every path from a surface outside the
        /// window stops here, so the press that declares code on this Mac is always made with the
        /// capability statement in front of it.
        @MainActor
        public static func revealInbox(itemID: String, on model: ShellModel) {
            NSApp?.activate(ignoringOtherApps: true)
            bringWindowForward()
            model.revealInbox(itemID: itemID)
        }

        /// Open the Inbox board itself, with nothing selected — the overflow row's destination, and
        /// where a multi-item notification lands. No sheet: there is no single item to review.
        @MainActor
        public static func openInbox(on model: ShellModel) {
            NSApp?.activate(ignoringOtherApps: true)
            bringWindowForward()
            model.select(.inbox)
        }

        /// Quit the app. **Not the router** — the daemon keeps running, which is what the button's
        /// help tag promises and what makes quitting safe for someone mid-session.
        @MainActor
        public static func quit() {
            NSApp?.terminate(nil)
        }

        /// The app's own window, rather than whatever happens to be first.
        ///
        /// A `MenuBarExtra` in `.window` style has an `NSWindow` of its own, and it is in
        /// `NSApp.windows`. Ordering that one forward would raise the popover rather than the shell,
        /// so the panel classes are skipped.
        @MainActor
        private static func bringWindowForward() {
            let target = NSApp?.windows.first { window in
                window.canBecomeMain && !(window is NSPanel)
            }
            target?.makeKeyAndOrderFront(nil)
        }
    }
#endif
