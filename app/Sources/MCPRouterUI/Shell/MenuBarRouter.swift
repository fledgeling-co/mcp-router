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
            NSApp.activate(ignoringOtherApps: true)
            bringWindowForward()
            Task { await model.reveal(server: row.server, openingHeldChange: row.opensHeldChangeSheet) }
        }

        /// Open the main window from the popover's one action.
        @MainActor
        public static func openWindow() {
            NSApp.activate(ignoringOtherApps: true)
            bringWindowForward()
        }

        /// Quit the app. **Not the router** — the daemon keeps running, which is what the button's
        /// help tag promises and what makes quitting safe for someone mid-session.
        @MainActor
        public static func quit() {
            NSApp.terminate(nil)
        }

        /// The app's own window, rather than whatever happens to be first.
        ///
        /// A `MenuBarExtra` in `.window` style has an `NSWindow` of its own, and it is in
        /// `NSApp.windows`. Ordering that one forward would raise the popover rather than the shell,
        /// so the panel classes are skipped.
        @MainActor
        private static func bringWindowForward() {
            let target = NSApp.windows.first { window in
                window.canBecomeMain && !(window is NSPanel)
            }
            target?.makeKeyAndOrderFront(nil)
        }
    }
#endif
