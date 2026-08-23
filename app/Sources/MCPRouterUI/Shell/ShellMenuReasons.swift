#if os(macOS)
    import AppKit
    import MCPRouterKit
    import Observation

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
        /// Sets each owned item's tool tip to its command's reason, and **clears it** where there is
        /// none. Returns how many owned items currently carry a reason, so a test can tell "applied
        /// to nothing" from "applied correctly" — a walker that silently matches zero items is the
        /// failure this whole file is about. In a fully-live context that number is legitimately 0,
        /// which is why the count is not by itself a health check.
        @MainActor
        @discardableResult
        public static func apply(to menu: NSMenu, context: MenuCommand.CommandContext = .none) -> Int {
            var applied = 0
            for item in menu.items {
                // Only the items the app declares. `command(titled:)` returning nil means macOS
                // owns this item, and macOS's own tool tips are not this walker's to write **or to
                // erase** — which is why the clearing below is inside this binding rather than
                // beside it.
                if let command = command(titled: item.title) {
                    let reason = command.reason(in: context)
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
                    //
                    // **`nil` is written too, and that is the point of assigning rather than
                    // testing for a reason first.** This walker is armed at launch, before any
                    // window exists, so its first passes run against `.none` — M1's world, in which
                    // `Add server…` is surface-absent — and annotate the item accordingly. The
                    // window then appears, the context goes live, and the command becomes usable.
                    // A walker that only ever wrote a reason would leave the surface-absent
                    // sentence on an enabled command, which is worse than saying nothing: it is the
                    // shell telling the user a surface is missing while offering it.
                    //
                    // The sentence itself is deliberately not quoted here. `ScaffoldPane.swift` is
                    // the one file allowed to carry it, and `placeholderIsNotReintroduced` fails on
                    // any other — including, as this comment first did, in prose.
                    if item.toolTip != reason { item.toolTip = reason }
                    if item.accessibilityHelp() != reason { item.setAccessibilityHelp(reason) }
                    // The short form, in the shortcut column, under the same write-only-when-changed
                    // discipline and for the same measured reason.
                    //
                    // **This is what puts the reason where the brief asks for it.** The brief and
                    // `PRD.md` §9.8 both say a disabled item is dimmed in place *with the reason in
                    // the shortcut column* — `Install Command-Line Tool · Installed` is the pattern
                    // — and a tool tip needs a second of hover, so until now the reason was
                    // discoverable to a pointer that waited and to VoiceOver, and invisible to a
                    // person reading the menu. `NSMenuItemBadge` is the platform's own right-aligned
                    // trailing text and is available from macOS 14; the deployment target is 15.0.
                    //
                    // Compared through `stringValue` rather than by identity, because
                    // `NSMenuItemBadge` is an `NSObject` without value equality and two badges
                    // carrying one word are not `==`. `stringValue` is documented as "the string
                    // representation of the badge as it would appear when the badge is displayed",
                    // which is exactly what this walker is keeping in step.
                    let badge = command.availability(in: context).badge
                    if item.badge?.stringValue != badge {
                        item.badge = badge.map { NSMenuItemBadge(string: $0) }
                    }
                    // Counted where the item *has* a reason, which is the number a test can use to
                    // tell "applied correctly" from "matched nothing". Note this is a count of
                    // owned items **currently carrying a reason**, not of items owned and not of
                    // writes performed: in a fully-live context every command is enabled and the
                    // honest answer is 0.
                    if reason != nil { applied += 1 }
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
        /// Nil means `.none`, which is M1's world and the honest answer *before any window has ever
        /// appeared*. It is deliberately **not** unregistered when a window closes, and that is a
        /// trade rather than an oversight: the app outlives its window (M8's menu-bar extra makes
        /// window-closed a normal state), and reverting to `.none` there would dim `Add server…`
        /// and tell the user its surface has not been built — which is false, and a worse §3.4
        /// answer than an enabled item. The residue is that a command can render enabled while no
        /// focused scene exists to receive it, which `ShellCommandRouter` then no-ops. That is a
        /// pre-existing property of the sixteen commands that were always enabled, not something
        /// this context source introduced; it is recorded in `planning/evidence/M11-acceptance.md`
        /// as a gap belonging to the command router rather than papered over here.
        ///
        /// **`@Observable`, and not incidentally.** `CommandItem` reads `liveContext` inside its
        /// `body` to decide whether to dim, so SwiftUI has to be told when the answer changes.
        /// Observation covers both ways it can: the stored `provider` is read on every evaluation,
        /// so a window registering after the menu was first built invalidates the items; and once a
        /// provider is installed, calling it reads `ShellModel.menuContext`, whose own `@Observable`
        /// properties are then tracked too, so moving the server selection re-evaluates `Reset
        /// server` and `Remove server`. A plain `static var` gave neither, and the menu would have
        /// been built once against whatever was true at launch.
        ///
        /// **Not `@FocusedValue`, which is the obvious alternative and is wrong here.** A focused
        /// scene value is nil whenever the app is inactive, so every command would dim the moment
        /// the user switched away — and the acceptance walk, which reads the menu bar of a
        /// deliberately backgrounded app, would measure a menu no user ever sees.
        @MainActor
        @Observable
        final class ContextSource {
            static let shared = ContextSource()

            private var provider: (@MainActor () -> MenuCommand.CommandContext)?

            private init() {}

            func provide(_ provider: @escaping @MainActor () -> MenuCommand.CommandContext) {
                self.provider = provider
            }

            /// Restores the launch-time state. Only a test needs this; the app registers once.
            func reset() {
                provider = nil
            }

            var context: MenuCommand.CommandContext {
                provider?() ?? .none
            }
        }

        @MainActor
        public static func provideContext(_ provider: @escaping @MainActor () -> MenuCommand.CommandContext) {
            ContextSource.shared.provide(provider)
        }

        @MainActor
        public static var liveContext: MenuCommand.CommandContext {
            ContextSource.shared.context
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
