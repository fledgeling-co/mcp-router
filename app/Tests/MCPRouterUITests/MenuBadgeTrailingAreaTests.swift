#if os(macOS)
    import AppKit
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// What the trailing area of a badged menu item actually shows — M34.
    ///
    /// **This is the question M34 was filed because nothing could answer.** Some commands are dimmed
    /// with a badge explaining why *and* carry a keyboard chord, and a badge and a chord want the
    /// same edge of the item. If the badge displaced the chord, the menu would be teaching a
    /// shortcut it no longer displays; if the chord displaced the badge, `PRD.md` §9.8's *reason in
    /// the shortcut column* would be false. Four lanes were recorded closed on it: the accessibility
    /// tree, actuation, photography, and a unit test over a menu the test itself built.
    ///
    /// The lane that turned out to be open is **AppKit's own layout**. `NSMenu.size` lays a menu out
    /// and returns the width it needs, in-process, with no window, no tracking session and nothing
    /// on screen — so it takes no part of the user's display, which is what closed the photography
    /// lane. A trailing area that has room for both is one that displaces neither.
    ///
    /// **What this does not claim.** It measures the width AppKit reserves, not the pixels it
    /// paints, and it builds its own `NSMenu` — so it is evidence about the platform's layout rule
    /// rather than about the app's wiring. The wiring is covered separately:
    /// `ShellMenuContextTests` proves the walker writes the badge, and
    /// `scripts/acceptance/menu-badge-fixture/` measures what reaches the accessibility plane of a
    /// menu SwiftUI built. The three together are the chain; none of them is it alone.
    @Suite("Mac shell — a badge and a chord in one trailing area")
    struct MenuBadgeTrailingAreaTests {
        /// The commands the question is actually about: dimmed with a badge, and carrying a chord.
        static var badgedAndChorded: [MenuCommand] {
            MenuCommand.allCases.filter { $0.availability.badge != nil && $0.shortcut != nil }
        }

        /// One menu, one item, laid out by AppKit — the width it says that item needs.
        ///
        /// `autoenablesItems` is off because AppKit would otherwise dim an item with no action, and
        /// the subject here is a **disabled** item: the badge is how a dimmed command explains
        /// itself, so measuring the enabled case would measure something the app never shows.
        @MainActor
        static func width(title: String, badge: String?, chord: String?) -> CGFloat {
            let menu = NSMenu()
            menu.autoenablesItems = false
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: chord ?? "")
            if chord != nil { item.keyEquivalentModifierMask = [.command] }
            if let badge { item.badge = NSMenuItemBadge(string: badge) }
            item.isEnabled = false
            menu.addItem(item)
            return menu.size.width
        }

        /// A count, not a spot check.
        ///
        /// M34's claim is about a specific set — *six items carry a chord and a badge at once* — and
        /// a set that quietly empties would make every assertion below pass over nothing, which is
        /// the failure mode this repo keeps meeting. Pinning the number also means a seventh command
        /// joining the set has to be looked at rather than absorbed.
        @MainActor
        @Test("exactly the commands M34 is about carry both a badge and a chord")
        func theSetIsTheOneM34Names() {
            let both = Self.badgedAndChorded
            #expect(!both.isEmpty, "no command carries both, so every layout check below measures nothing")
            #expect(both.count == 6, "the set M34 names is six: \(both.map(\.title).sorted())")
        }

        /// The measurement, per command, against its own two controls.
        ///
        /// Both comparisons are needed and they fail on opposite mistakes. Wider than the badge
        /// alone says the **chord** still has room when a badge is present; wider than the chord
        /// alone says the **badge** does. One of them on its own would pass a build in which the
        /// other had been displaced.
        @MainActor
        @Test("a badge and a chord each get room, so neither displaces the other")
        func neitherDisplacesTheOther() {
            for command in Self.badgedAndChorded {
                guard let badge = command.availability.badge else { continue }
                let chord = "x"
                let plain = Self.width(title: command.title, badge: nil, chord: nil)
                let chordOnly = Self.width(title: command.title, badge: nil, chord: chord)
                let badgeOnly = Self.width(title: command.title, badge: badge, chord: nil)
                let together = Self.width(title: command.title, badge: badge, chord: chord)

                // The controls. Without these two, a build in which AppKit reserved nothing for
                // either would read as "neither displaces the other" and pass.
                #expect(chordOnly > plain, "\(command.title): AppKit reserved nothing for the chord")
                #expect(badgeOnly > plain, "\(command.title): AppKit reserved nothing for the badge")

                #expect(
                    together > badgeOnly,
                    "\(command.title): the badge displaced the chord (\(together) ≤ \(badgeOnly))"
                )
                #expect(
                    together > chordOnly,
                    "\(command.title): the chord displaced the badge (\(together) ≤ \(chordOnly))"
                )
            }
        }
    }
#endif
