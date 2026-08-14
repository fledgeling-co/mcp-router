#if os(macOS)
    import AppKit
    import MCPRouterKit

    /// Puts each disabled command's reason where macOS can actually show it.
    ///
    /// **This exists because SwiftUI's `.help()` does not reach a menu item.** Measured on this
    /// machine against the built app: every item in all six menus reported `AXHelp` as
    /// `missing value` while `.help(...)` was applied to the `Button` inside the `CommandGroup`.
    /// `DESIGN.md` §3.4 requires a disabled control to dim in place **with a discoverable reason**,
    /// and on macOS a menu item's only place for one is its tool tip — so without this bridge, A22's
    /// "carries the reason" half is simply false, however good the string on `CommandAvailability`
    /// looks in the source.
    ///
    /// Matching is by title against `MenuCommand`, which is the same model the menu was built from,
    /// so an item the app did not declare is never touched — the system's own items keep whatever
    /// macOS gives them.
    ///
    /// Re-applied continuously rather than once at launch: SwiftUI rebuilds its menu items
    /// as state changes, and a tool tip set once is a tool tip that disappears the first time the
    /// selection moves.
    public enum ShellMenuReasons {
        /// Sets the tool tip on every item whose command has a reason. Returns how many it set, so a
        /// test can tell "applied to nothing" from "applied correctly" — a walker that silently
        /// matches zero items is the failure this whole file is about.
        @MainActor
        @discardableResult
        public static func apply(to menu: NSMenu, context: MenuCommand.CommandContext = .none) -> Int {
            var applied = 0
            for item in menu.items {
                let availability = command(titled: item.title)?.availability(in: context)
                if let reason = availability?.reason {
                    // Both, and for different readers. `toolTip` is what a person sees when they
                    // rest on the item; `setAccessibilityHelp` is what VoiceOver reads and what
                    // `AXHelp` returns. Setting only the tool tip leaves the reason invisible to
                    // the accessibility tree, which is where A22's evidence is read from.
                    //
                    // Written only when it differs. This runs ten times a second, and
                    // unconditionally re-assigning both attributes on every pass mutates the
                    // accessibility tree continuously — which made concurrent AX reads fail with
                    // -1728 against elements that were being rewritten underneath them. After the
                    // first pass over a menu this loop now only reads.
                    if item.toolTip != reason { item.toolTip = reason }
                    if item.accessibilityHelp() != reason { item.setAccessibilityHelp(reason) }
                    // Counted on match rather than on write, so the count still answers "how many
                    // items does this walker own" rather than "how many changed this time".
                    applied += 1
                }
                if let submenu = item.submenu {
                    applied += apply(to: submenu, context: context)
                }
            }
            return applied
        }

        /// The command this menu item was built from, or nil where macOS contributed the item.
        @MainActor
        public static func command(titled title: String) -> MenuCommand? {
            MenuCommand.allCases.first { $0.title == title }
        }

        /// How often the reasons are re-applied.
        ///
        /// A tenth of a second rather than a whole one, and the difference is not cosmetic.
        /// SwiftUI rebuilds a `CommandGroup`'s `NSMenuItem`s **when the menu is opened**, and it
        /// builds them bare — so the window between "the item exists" and "the item explains
        /// itself" is however long this interval is. At one second that window was long enough for
        /// an accessibility walk of a freshly-opened menu to read `AXHelp` as empty, which is
        /// exactly what a VoiceOver user focusing the item would have heard: nothing.
        ///
        /// A tool tip needs a second or two of hover before macOS shows it, so a person was never
        /// going to see the gap; the accessibility tree is read the instant focus lands, and that
        /// is the reader this interval is set for.
        ///
        /// The cost is a walk of about forty items against thirty-odd titles, ten times a second,
        /// and only while the app is running — far below anything the user is doing when a menu is
        /// open.
        static let reapplyInterval: Duration = .milliseconds(100)

        /// Keeps the reasons applied for as long as the app is running.
        ///
        /// This is a poll, and the reason it is a poll is worth recording, because every
        /// event-driven version of it was tried first and measured to be wrong:
        ///
        /// - **At launch only.** SwiftUI does not build every menu at launch. The File group is
        ///   there immediately; the Edit group's three items appear only when the Edit menu is
        ///   first opened, so those three stayed bare.
        /// - **On `didBeginTracking`.** Fires *before* SwiftUI populates the menu it is about to
        ///   show, so it cannot see the items it needs to annotate.
        /// - **On `didEndTracking`.** Fires after the menu closes. The items exist by then — but a
        ///   tool tip is read while the menu is *open*, so the reason would first become visible on
        ///   the second visit. A discoverable reason that needs two attempts is not discoverable.
        ///
        /// SwiftUI owns these `NSMenuItem`s and replaces them on its own schedule, so the only thing
        /// that survives is re-applying.
        /// Where the live context comes from while the app is running.
        ///
        /// A registered closure rather than a parameter, because `install()` is armed by the app
        /// delegate at launch — before any window exists — while the facts a command branches on
        /// (which boards are installed, which server is selected) belong to a window that appears
        /// later. The poll below reads it on every tick, so a window registering afterwards is
        /// picked up without re-arming anything.
        ///
        /// Nil means `.none`, which is M1's world and the honest answer when no shell window is up.
        @MainActor private static var contextProvider: (@MainActor () -> MenuCommand.CommandContext)?

        @MainActor
        public static func provideContext(_ provider: @escaping @MainActor () -> MenuCommand.CommandContext) {
            contextProvider = provider
        }

        @MainActor
        public static var liveContext: MenuCommand.CommandContext {
            contextProvider?() ?? .none
        }

        @MainActor
        public static func install() {
            Task { @MainActor in
                while !Task.isCancelled {
                    if let main = NSApp.mainMenu { apply(to: main, context: liveContext) }
                    do {
                        try await Task.sleep(for: reapplyInterval)
                    } catch {
                        return
                    }
                }
            }
        }
    }
#endif
