import Foundation
import Testing
@testable import MCPRouterKit

/// The rules the menu bar obeys, as opposed to the inventory it is checked against.
///
/// Split out of `MenuCommandTests` at M20, when the Router and Library menus took that file past
/// its length limit. The seam is the one the file already had a `MARK` for: above it, the model is
/// compared against two documents; here, it is held to the house rules those documents state —
/// the ellipsis, the disabled reason, the badge, the accelerator, the gating map.
///
/// It reuses `MenuCommandTests`' document readers rather than growing a second copy, so there is
/// still one parser per oracle.
@Suite("Menu bar — house rules")
struct MenuCommandRuleTests {
    // MARK: - The house rules

    /// `DESIGN.md` §3.4 — `…` means "opens a further view"; its absence means "commits now".
    @Test("the ellipsis is on exactly the commands that open a further view")
    func ellipsisRule() {
        let opening: Set = [
            // `Settings…` joined at M15. It opens a window now rather than selecting a sidebar
            // destination, and §3.4 makes that distinction the ellipsis's whole job.
            "Settings…",
            "Add Server…", "Add Marketplace…", "Pair iPhone…", "Export Library…",
            // M20's one. `Review Held Changes…` opens the held-change sheet for the selected
            // server, which is a further view by the same rule.
            //
            // **`Export Library…` keeps its ellipsis and `D-m14-c` stays open.** That item calls it
            // a promise of a view that does not exist and assigns the call to M1; the mock now
            // draws it with the ellipsis too, so M20 records the agreement rather than settling
            // somebody else's question in passing.
            "Review Held Changes…"
        ]
        for command in MenuCommand.allCases {
            #expect(
                command.opensAFurtherView == opening.contains(command.title),
                "\(command.title) disagrees with the ellipsis rule"
            )
        }
    }

    /// §3.4 — disabled dims in place with a discoverable reason and never disappears.
    @Test("every unavailable command carries a reason, and every available one carries none")
    func disabledCommandsCarryTheirReason() {
        for command in MenuCommand.allCases {
            if command.availability.isEnabled {
                #expect(command.availability.reason == nil)
            } else {
                let reason = command.availability.reason
                #expect(reason?.isEmpty == false, "\(command.title) is disabled with no reason")
                // §6: never blames, never emotes.
                #expect(reason?.contains("!") == false)
                #expect(reason?.lowercased().contains("you did") == false)
            }
        }
        // Exactly three reasons exist, so none can be invented at a call site.
        #expect(CommandAvailability.surfaceAbsent.reason == "This part of the app isn't built yet.")
        #expect(CommandAvailability.featureUnbuilt.reason == "This feature hasn't been built yet.")
        #expect(CommandAvailability.needsServerSelection.reason == "Select a server first.")
        // The two refusals M14 separated must not collapse back into one sentence. Pinning the
        // strings above is not enough on its own: someone editing one to match the other would
        // update both literals here in the same pass and this file would stay green. Asserting the
        // *distinction* is what fails when the vocabulary silently narrows again.
        #expect(CommandAvailability.surfaceAbsent.reason != CommandAvailability.featureUnbuilt.reason)
    }

    /// Every `.featureUnbuilt` command names **what** is unbuilt.
    ///
    /// `D-m14-a`'s clause. One command carried that refusal when its sentence was written and nine
    /// carry it now, so the generic *"This feature hasn't been built yet."* would appear nine times
    /// across two menus and tell a reader nothing about which nine features. Asserting that the
    /// sentences are **distinct** is what fails if a later command takes the case without naming
    /// its subject — pinning nine literals would not, because the fallback would satisfy them one
    /// at a time.
    @Test("every unbuilt command says what is unbuilt, in words of its own")
    func unbuiltCommandsNameTheirSubject() {
        let unbuilt = MenuCommand.allCases.filter { $0.availability == .featureUnbuilt }
        #expect(unbuilt.count >= 9, "only \(unbuilt.count) commands are featureUnbuilt")
        var sentences: Set<String> = []
        for command in unbuilt {
            guard let reason = command.reason() else {
                Issue.record("\(command.title) is unbuilt with no reason")
                continue
            }
            #expect(
                reason != CommandAvailability.featureUnbuilt.reason,
                "\(command.title) fell back to the generic sentence"
            )
            #expect(!reason.contains("!"), "\(command.title) emotes")
            #expect(sentences.insert(reason).inserted, "\(command.title) reuses another's sentence")
        }
        // The three that are *not* specialised keep the generic answer, because which board is
        // missing is visible from the item itself.
        #expect(MenuCommand.addServer.reason() == CommandAvailability.surfaceAbsent.reason)
        #expect(MenuCommand.about.reason() == nil)
    }

    /// The badge is present exactly where a command is unavailable, and the two unbuilt answers
    /// keep different words there too.
    ///
    /// The brief and `PRD.md` §9.8 put the reason in the shortcut column rather than only in a tool
    /// tip. Collapsing `surfaceAbsent` and `featureUnbuilt` to one badge would undo M14's
    /// separation one layer down, where no test was looking — the sentences would still differ and
    /// the thing a person reads would not.
    @Test("the shortcut column carries a short reason exactly where one is owed")
    func badgeIsPresentExactlyWhereUnavailable() {
        for command in MenuCommand.allCases {
            let badge = command.availability.badge
            #expect(
                (badge == nil) == command.availability.isEnabled,
                "\(command.title) disagrees with its own availability about its badge"
            )
            if let badge { #expect(!badge.isEmpty) }
        }
        #expect(CommandAvailability.enabled.badge == nil)
        #expect(CommandAvailability.surfaceAbsent.badge != CommandAvailability.featureUnbuilt.badge)
        #expect(CommandAvailability.needsServerSelection.badge != nil)
    }

    /// A command that cannot fire in any context carries no accelerator.
    ///
    /// The rule the app already applied to `Export Library…`, whose `⌘E` was a standard macOS
    /// combination — Finder's *Eject* — claimed for a command that could never fire. M20 generalised
    /// it rather than re-deciding it per item, and it is what settles **seven** of the ten chords the
    /// mock's Router and Library menus claim. Without this, adding `⇧⌘R` to `Restart Router` because
    /// the mock draws it would pass every other test in this file.
    ///
    /// Seven rather than nine, because this clause can only see the limb it enforces. `⌃W` is granted,
    /// `⌘1` is a duplicate the no-duplicate rule settles, and `⌥⌘Q` is refused by `DESIGN.md` §8's
    /// second limb — the chord is AppKit's own `Quit and Keep Windows` — which nothing here reads,
    /// since this file's subject is availability. The nine that is true of M20 is the number of the
    /// twelve declared commands that are `.featureUnbuilt`, which is a different population.
    @Test("a command that can never fire claims no shortcut")
    func unbuildableCommandsClaimNoShortcut() {
        let everyContext = [
            MenuCommand.CommandContext.none,
            MenuCommand.CommandContext(
                installedDestinations: Set(Destination.allCases),
                selectedServerIsTripped: nil
            ),
            MenuCommand.CommandContext(
                installedDestinations: Set(Destination.allCases),
                selectedServerIsTripped: true
            )
        ]
        for command in MenuCommand.allCases {
            let canEverFire = everyContext.contains { command.availability(in: $0).isEnabled }
            guard !canEverFire else { continue }
            #expect(
                command.shortcut == nil,
                "\(command.title) can fire in no context and claims \(command.shortcut?.display ?? "")"
            )
        }
    }

    /// **Which board each command gates on**, asserted where the shipping registry cannot see it.
    ///
    /// This is the fact M11's derived acceptance oracle gave up. That oracle compiles this very
    /// file, so a change to the gating map moves the expectation with the app and no gate goes red;
    /// `inventoryMatchesTheModelBothWays` above only reads `.none`, where every board-dependent
    /// command answers `surfaceAbsent` and the map is invisible; and with all eight boards
    /// installed *any* required destination yields `.enabled`. So the map is only falsifiable
    /// against **partial** contexts, which is what this builds.
    ///
    /// Repointing `find` at `.evals` instead of `.servers` passes every other test in this repo.
    /// It fails here.
    @Test("each command gates on its own board, not merely on some board")
    func gatingMapIsPerCommand() {
        func context(_ installed: Set<Destination>) -> MenuCommand.CommandContext {
            MenuCommand.CommandContext(installedDestinations: installed, selectedServerIsTripped: nil)
        }
        let serversOnly = context([.servers])
        let skillsOnly = context([.skills])

        // Servers is what these three need, and Skills does not stand in for it.
        for command in [MenuCommand.addServer, .find] {
            #expect(command.availability(in: serversOnly) == .enabled, "\(command.title)")
            #expect(command.availability(in: skillsOnly) == .surfaceAbsent, "\(command.title)")
        }
        // The two that act on a selection get past the surface question and stop at the selection.
        for command in [MenuCommand.resetServer, .removeServer] {
            #expect(command.availability(in: serversOnly) == .needsServerSelection, "\(command.title)")
            #expect(command.availability(in: skillsOnly) == .surfaceAbsent, "\(command.title)")
        }
        // And marketplaces are the Skills board's, which is the pair that would swap silently.
        #expect(MenuCommand.addMarketplace.availability(in: skillsOnly) == .enabled)
        #expect(MenuCommand.addMarketplace.availability(in: serversOnly) == .surfaceAbsent)

        // Owned by nothing that has shipped, so no installed set turns it on. `.featureUnbuilt`
        // rather than `.surfaceAbsent`: there is no board that would make export appear, which is
        // exactly the distinction M14 added the case for.
        for installed in [Set<Destination>(), [.servers], [.inbox], Set(Destination.allCases)] {
            #expect(MenuCommand.exportLibrary.availability(in: context(installed)) == .featureUnbuilt)
        }
        // And pairing gates on the board that hosts its sheet, not on "some board". Asserted
        // against partial contexts for the reason this whole test exists: with every destination
        // installed any required one yields `.enabled`, so the map is invisible there.
        #expect(MenuCommand.pairPhone.availability(in: context([.inbox])) == .enabled)
        #expect(MenuCommand.pairPhone.availability(in: serversOnly) == .surfaceAbsent)
        #expect(MenuCommand.pairPhone.availability(in: skillsOnly) == .surfaceAbsent)
    }

    @Test("shortcuts render in Apple's modifier order")
    func modifierOrder() {
        #expect(KeyChord("N", [.command, .shift]).display == "⇧⌘N")
        #expect(KeyChord("H", [.command, .option]).display == "⌥⌘H")
        #expect(KeyChord("S", [.command, .control]).display == "⌃⌘S")
        #expect(KeyChord("N").display == "⌘N")
    }

    @Test("no two commands claim the same shortcut")
    func shortcutsAreUnique() {
        let displays = MenuCommand.allCases.compactMap(\.shortcut).map(\.display)
        #expect(Set(displays).count == displays.count, "a shortcut is bound twice: \(displays)")
    }

    /// The View menu carries every destination that has a digit, **in digit order**.
    ///
    /// It used to assert sidebar order, which was the same list while the digits were `1`–`7` down
    /// the sidebar. M20 takes the design of record's map, where they are not: sidebar order would
    /// draw a menu reading `⌘4, ⌘3, ⌘2, ⌘1, ⌘8, ⌘6, ⌘7`, and the digit is the only thing this menu
    /// is for. The set is still asserted against `Destination`, so a destination cannot gain a
    /// digit without appearing here.
    ///
    /// The sidebar's own order is deliberately not asserted to match: regrouping it into the
    /// mock's four sections is M22's, and until then the two orders differ.
    @Test("the View menu carries every digit-bearing destination, in digit order")
    func viewMenuIsInDigitOrder() {
        let inView = MenuCommand.inMenu(.view).compactMap { command -> Destination? in
            if case let .selectDestination(destination) = command { return destination }
            return nil
        }
        #expect(Set(inView) == Set(Destination.allCases.filter { $0.selectionDigit != nil }))
        #expect(inView == inView.sorted { ($0.selectionDigit ?? 0) < ($1.selectionDigit ?? 0) })
        #expect(inView.map(\.selectionDigit) == [1, 2, 3, 4, 6, 7, 8])
    }
}
