#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// The app menu's `Settings…` item, built from the command model exactly as `CommandItem` is.
    ///
    /// **Its body is a `SettingsLink` rather than a `Button`**, because that is the documented API
    /// for opening a `Settings` scene from a `Commands` builder. `EnvironmentValues.openSettings`
    /// needs a view inside a scene and a menu lives outside every scene — the same `@FocusedValue`
    /// fact `ShellCommandRouter`'s own note measured — so a hand-rolled button here would be a menu
    /// item that reliably does nothing.
    ///
    /// It reads its title, shortcut and disabled reason from `MenuCommand` for the reason
    /// `CommandItem` does: the menu bar cannot say something the model does not, which is what makes
    /// A19 a check rather than a coincidence.
    ///
    /// **Whether the shortcut is applied here is a reading rather than a guess.** A `Settings` scene
    /// in the `.appSettings` position may carry `⌘,` implicitly, and applying it a second time is how
    /// an item ends up double-bound. `mac-shell.sh`'s A20 walk reads `AXMenuItemCmdChar` and the
    /// modifiers off the running menu bar, so the answer is measured there; the modifier is applied
    /// below because the reading with it absent was empty.
    public struct SettingsCommandItem: View {
        private let command: MenuCommand

        public init(_ command: MenuCommand = .settings) {
            self.command = command
        }

        /// Read from the live context, never from `MenuCommand.availability` — the shorthand answers
        /// in `CommandContext.none`, which is M1's world, and reading it here is the defect
        /// `CommandItem` records having shipped once.
        var resolvedAvailability: CommandAvailability {
            command.availability(in: ShellMenuReasons.liveContext)
        }

        public var body: some View {
            item
                // §3.4: disabled dims in place and never disappears, with a discoverable reason. On
                // macOS a menu item's only place for that reason is its help tag.
                .disabled(!resolvedAvailability.isEnabled)
                .help(resolvedAvailability.reason ?? "")
        }

        @ViewBuilder
        private var item: some View {
            if let shortcut = command.shortcut {
                SettingsLink { Text(command.title) }
                    .keyboardShortcut(shortcut.keyboardShortcut)
            } else {
                SettingsLink { Text(command.title) }
            }
        }
    }
#endif
