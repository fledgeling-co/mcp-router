#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// J2 · SURF-001's sidebar, actuated once per destination and read back somewhere else.
    ///
    /// **What this suite is for, and what it deliberately does not claim.** The control census
    /// (`planning/test-campaign/bin/control-census.py`) counts a declared control as actuated only
    /// when a *passing effect-rung* case drives it and reads the state it was supposed to change
    /// **through a different channel from the one that struck**. A sidebar row that renders, carries
    /// its accessible name and accepts a click does all of that whether or not its handler moves
    /// anything, so `model.selection == .servers` after `model.select(.servers)` is the actuation
    /// side of a vacuous assertion — it reads the property the call just wrote.
    ///
    /// The channel used here is the **restoration store**: `ShellModel.selection`'s `didSet` calls
    /// `store.save(destination:)`, so a real selection leaves a value in a `UserDefaults` suite that
    /// nothing in this file wrote. That is a different channel, it is the state a relaunch reads, and
    /// it goes silent the moment `select` stops doing anything.
    ///
    /// **The limit, stated rather than left implicit.** A persisted destination proves the selection
    /// took. It does not prove that a *different board was drawn* — SwiftUI's view tree is opaque to
    /// a SwiftPM test, and `ContentZone`'s switch is unreachable from here. Destination collapse
    /// (`references/inert-ui.md` §1, six menu items over one placeholder view) is read on glass by
    /// CASE-0001, which selects each row through AXPress and reads the window title back. That case
    /// is FAILING against the current build (DEF-058, DEF-059) and is therefore counted by nothing.
    /// This suite is the in-process half, and it says which half it is.
    @MainActor
    @Suite("J2 · the shell's destinations are actuated, not merely drawn")
    struct ShellDestinationActuationTests {
        /// The seven sidebar controls SURF-001 declares, paired with the destination each selects.
        ///
        /// Written as the census's own control names rather than as `Destination.allCases`, because
        /// the registry cites controls by string and the two must be able to disagree. `Checks` is
        /// `.evals` — the label was renamed and the identifier deliberately was not
        /// (`Destination.title`'s own note) — and a list derived from the enum would hide that.
        /// Harnesses and Insights are absent because the design of record this census counts against
        /// predates both boards.
        static let declared: [(control: String, destination: Destination)] = [
            ("Activity", .activity),
            ("Servers", .servers),
            ("Skills", .skills),
            ("Discover", .discover),
            ("Inbox", .inbox),
            ("Checks", .evals),
            ("Cleanup", .cleanup)
        ]

        /// Each row drives its own destination, and the store — not the model — is asked afterwards.
        ///
        /// The starting position matters: the model boots on `.activity`, so selecting Activity from
        /// Activity writes nothing (`didSet` guards on `oldValue != selection`). Every row is
        /// therefore approached from a *different* destination, which is what a user does and what a
        /// press that only works from one starting state would fail.
        @Test("selecting a destination leaves it in the restoration store, from any starting point")
        func eachSelectionReachesTheStore() throws {
            for (control, destination) in Self.declared {
                let scratch = try ShellTestSupport.scratchStore()
                defer { scratch.tearDown() }
                let model = ShellModel(client: FixtureControlAPIClient(.populated), store: scratch.store)

                // Approach from somewhere else, so the write cannot be the one the boot did.
                let elsewhere: Destination = destination == .insights ? .harnesses : .insights
                model.select(elsewhere)
                #expect(scratch.defaults.string(forKey: ShellRestoration.destinationKey)
                    == elsewhere.rawValue)

                model.select(destination)
                #expect(
                    scratch.defaults.string(forKey: ShellRestoration.destinationKey)
                        == destination.rawValue,
                    "pressing \(control) changed nothing a second channel can see"
                )
            }
        }

        /// The destination-collapse relation, stated over the channel this lane can actually read.
        ///
        /// Seven presses, seven distinct persisted values. A shell whose rows all led to one place
        /// would write one value seven times, and this is the shape that says so as a count rather
        /// than as seven separate greens.
        @Test("seven rows write seven distinct values, so no two rows lead to one place")
        func theSevenRowsDoNotCollapse() throws {
            let scratch = try ShellTestSupport.scratchStore()
            defer { scratch.tearDown() }
            let model = ShellModel(client: FixtureControlAPIClient(.populated), store: scratch.store)

            // Started outside the seven, so the first press is a real transition. The model boots
            // on `.activity` and `didSet` guards on `oldValue != selection`, so beginning the loop
            // there would have the first row write nothing at all — which this assertion caught the
            // first time it ran, rather than reading a stale value and calling it a pass.
            model.select(.insights)

            var written: [String] = []
            for (_, destination) in Self.declared {
                model.select(destination)
                try written.append(#require(
                    scratch.defaults.string(forKey: ShellRestoration.destinationKey)
                ))
            }
            #expect(written.count == Self.declared.count)
            #expect(
                Set(written).count == Self.declared.count,
                "two sidebar rows persisted the same destination: \(written)"
            )
        }

        /// A restored model is the read-back a relaunch performs, and it is the one that would catch
        /// a store that accepted a write and gave a different value back.
        ///
        /// The assertion above reads the raw defaults key; this reads it through the app's own
        /// restoration path, so a `save`/`restore` pair that disagreed about the key or the encoding
        /// fails here rather than shipping.
        @Test("a second model built on the same store comes up on the last row pressed")
        func aRelaunchLandsWhereTheRowLeftIt() throws {
            let scratch = try ShellTestSupport.scratchStore()
            defer { scratch.tearDown() }
            let first = ShellModel(client: FixtureControlAPIClient(.populated), store: scratch.store)
            first.select(.cleanup)

            let second = ShellModel(client: FixtureControlAPIClient(.populated), store: scratch.store)
            #expect(second.selection == .cleanup)
            #expect(scratch.store.restoredDestination() == .cleanup)
        }

        /// `Settings` is SURF-001's eighth declared control and it is **not** a destination.
        ///
        /// M15 moved it out of the sidebar into a scene of its own, so the effect to read is the
        /// opener the window installed firing — and the console's selection *not* moving. Both halves
        /// are asserted, because an implementation that selected a board and also opened the scene
        /// would pass the first alone.
        ///
        /// This overlaps `ShellCommandRouterTests.performOpensTheSettingsScene` on purpose: that
        /// suite is about the command mapping, and the census needs the control named. The
        /// registry cites that suite for the control; this is the neighbouring assertion that keeps
        /// the two facts in one place when someone reads this file.
        @Test("Settings fires the scene opener and leaves the console where it was")
        func settingsOpensASceneRatherThanABoard() throws {
            let scratch = try ShellTestSupport.scratchStore()
            defer { scratch.tearDown() }
            let model = ShellModel(client: FixtureControlAPIClient(.populated), store: scratch.store)
            model.select(.servers)

            let opened = OpenCounter()
            ShellCommandRouter.provideSettingsOpener { opened.fire() }
            defer { ShellCommandRouter.provideSettingsOpener {} }

            ShellCommandRouter.perform(.settings, on: model)
            #expect(opened.count == 1, "Settings reached an arm that does nothing")
            #expect(
                scratch.defaults.string(forKey: ShellRestoration.destinationKey)
                    == Destination.servers.rawValue,
                "opening Settings moved the console's destination"
            )
        }

        /// A counter a closure can bump, on the main actor so it needs no lock.
        @MainActor
        final class OpenCounter {
            private(set) var count = 0

            func fire() {
                count += 1
            }
        }
    }
#endif
