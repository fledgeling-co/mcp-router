#if os(macOS)
    import MCPRouterKit
    import SwiftUI

    /// Binds `KeyChord` — the kit's UI-free shortcut value — to SwiftUI's `KeyboardShortcut`.
    ///
    /// The two exist separately because `MCPRouterKit` may import no UI framework, which is what
    /// lets `MenuCommandTests` parse `DESIGN.md` §8 and compare it against the command model without
    /// a UI stack. This is the one place the crossing happens, so A20's "the key and modifiers the
    /// document states" has exactly one implementation to be wrong in.
    public extension KeyChord {
        /// The key as SwiftUI wants it: lower-cased, because a `KeyEquivalent` of `"H"` means
        /// **shift-h** and would silently add a modifier `DESIGN.md` never asked for.
        ///
        /// `?` is the one glyph that is not a key. On every layout macOS ships it is shift and
        /// another key — `/` on US — so a `KeyEquivalent("?")` binds nothing at all and the menu item
        /// silently appears with no shortcut. Measured on this machine: `AXMenuItemCmdChar` came back
        /// empty for Help until this mapping existed. The chord is written `⌘?` because that is what
        /// the menu displays, and it is *pressed* as `⇧⌘/`.
        var keyEquivalent: KeyEquivalent {
            switch key {
            case "⌫": .delete
            case "⏎": .return
            case "?": KeyEquivalent("/")
            default:
                KeyEquivalent(Character(key.lowercased()))
            }
        }

        var eventModifiers: EventModifiers {
            var result: EventModifiers = []
            if modifiers.contains(.command) { result.insert(.command) }
            if modifiers.contains(.shift) { result.insert(.shift) }
            if modifiers.contains(.option) { result.insert(.option) }
            if modifiers.contains(.control) { result.insert(.control) }
            // The shift that turns `/` into `?`. Added here rather than written into the chord so
            // `DESIGN.md`'s and the inventory's spelling stays the one the menu shows.
            if key == "?" { result.insert(.shift) }
            return result
        }

        var keyboardShortcut: KeyboardShortcut {
            KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
        }
    }

    /// One menu item, built from the command model rather than written out by hand.
    ///
    /// This is what makes A19 a real check instead of a coincidence: the title, the shortcut, the
    /// enabled state and the disabled reason all come from `MenuCommand`, so the menu bar cannot say
    /// something the model does not. `CommandsBuilder` cannot iterate top-level menus — SwiftUI's
    /// command groups are position-based — so the six menus are six explicit builders, but their
    /// *contents* are driven by `MenuCommand.inMenu(_:)`.
    public struct CommandItem: View {
        private let command: MenuCommand
        private let action: () -> Void

        public init(_ command: MenuCommand, action: @escaping () -> Void = {}) {
            self.command = command
            self.action = action
        }

        public var body: some View {
            item
                // §3.4: disabled dims in place and never disappears, with a discoverable reason. On
                // macOS a menu item's only place for that reason is its help tag, which is what the
                // accessibility walk reads back.
                .disabled(!command.availability.isEnabled)
                .help(command.availability.reason ?? "")
        }

        @ViewBuilder
        private var item: some View {
            if let shortcut = command.shortcut {
                Button(command.title, action: action)
                    .keyboardShortcut(shortcut.keyboardShortcut)
            } else {
                Button(command.title, action: action)
            }
        }
    }

    /// Reaching the focused window's model from a menu command.
    ///
    /// A menu lives outside any scene, so it cannot hold a reference to one window's state. The
    /// supported bridge is `focusedSceneValue` writing into `FocusedValues`, which is what this is;
    /// walking a window list from the command builder would work until the second window opened.
    public struct ShellModelFocusedValueKey: FocusedValueKey {
        public typealias Value = ShellModel
    }

    public extension FocusedValues {
        var shellModel: ShellModel? {
            get { self[ShellModelFocusedValueKey.self] }
            set { self[ShellModelFocusedValueKey.self] = newValue }
        }
    }
#endif
