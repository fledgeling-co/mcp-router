#if os(macOS)
    import AppKit
    import Foundation
    import MCPRouterKit
    import SwiftUI
    import Testing
    @testable import MCPRouterUI

    /// The shell's views, held to `DESIGN.md` and to the control client's own words.
    ///
    /// What this suite can and cannot see is worth stating, because the alternative is a suite that
    /// looks like it measures rendering and does not. SwiftUI's view tree is opaque to a SwiftPM
    /// test: nothing here can read a rendered inset, a badge's displacement or a focus ring's width.
    /// So every clause with a rendered half is split — the decision is asserted here, where it is a
    /// value, and the render is measured in `scripts/acceptance/shells.sh` off the running app's
    /// accessibility tree. A claim that a rendered geometry was measured from this file would be
    /// false, and none is made.
    @Suite("Mac shell")
    struct ShellTests {
        enum OracleError: Error { case fileNotFound(String), sectionNotFound(String) }

        /// Walks up to the repository root, the way `MenuCommandTests` finds its oracle.
        static func repoFile(_ relativePath: String, from filePath: String = #filePath) throws -> String {
            var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
            for _ in 0 ..< 8 {
                let candidate = dir.appendingPathComponent(relativePath)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return try String(contentsOf: candidate, encoding: .utf8)
                }
                dir = dir.deletingLastPathComponent()
            }
            throw OracleError.fileNotFound(relativePath)
        }

        /// A scratch defaults domain, so restoration is tested against real `UserDefaults`
        /// behaviour without writing into the developer's own preferences.
        static func scratchStore() throws -> (ShellRestoration, UserDefaults, String) {
            let suite = "mcprouter.tests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            return (ShellRestoration(defaults: defaults), defaults, suite)
        }

        @MainActor
        static func model(
            _ scenario: FixtureControlAPIClient.Scenario,
            at now: Date = Date(timeIntervalSince1970: 1_000_000)
        ) throws -> ShellModel {
            let (store, _, _) = try scratchStore()
            return ShellModel(client: FixtureControlAPIClient(scenario), store: store, clock: { now })
        }

        // MARK: - A34 · the scroll edge

        /// The threshold is driven from both sides, and from a **non-zero** resting offset — which
        /// is the case `offset > 0` gets wrong and the reason this is a state machine rather than a
        /// comparison. A scroll view with content insets rests below zero, and rubber-banding puts
        /// it either side of its resting point without the content having moved.
        @Test("the separator is absent at the resting offset and present above it")
        func scrollEdgeThreshold() {
            for resting in [0.0, -22.0, 13.5] {
                var state = ScrollEdgeState()
                state.observe(offset: resting)
                #expect(state.baseline == resting)
                #expect(!state.isSeparatorVisible, "showed a separator before anything scrolled")

                state.observe(offset: resting + ScrollEdgeState.threshold)
                #expect(!state.isSeparatorVisible, "fired at the threshold rather than above it")

                state.observe(offset: resting + ScrollEdgeState.threshold + 0.01)
                #expect(state.isSeparatorVisible, "did not appear once scrolled past the threshold")

                state.observe(offset: resting)
                #expect(!state.isSeparatorVisible, "did not clear on the way back to the top")
            }
        }

        @Test("rubber-banding above the resting point never shows the separator")
        func rubberBandingDoesNotFire() {
            var state = ScrollEdgeState()
            state.observe(offset: 0)
            state.observe(offset: -40)
            #expect(!state.isSeparatorVisible)
        }

        /// A new destination brings its own insets, so a carried-over baseline would compare one
        /// view's offset to another view's resting position.
        @Test("changing destination re-measures the baseline rather than carrying the old one")
        func resetForgetsTheBaseline() {
            var state = ScrollEdgeState()
            state.observe(offset: 0)
            state.observe(offset: 200)
            #expect(state.isSeparatorVisible)

            state.reset()
            #expect(state.baseline == nil)
            #expect(!state.isSeparatorVisible)

            state.observe(offset: -18)
            #expect(state.baseline == -18)
            #expect(!state.isSeparatorVisible)
        }

        @MainActor
        @Test("selecting a different destination resets the shell's scroll edge")
        func selectionResetsScrollEdge() throws {
            let model = try Self.model(.populated)
            model.observeScroll(offset: 0)
            model.observeScroll(offset: 300)
            #expect(model.scrollEdge.isSeparatorVisible)

            model.select(.servers)
            #expect(!model.scrollEdge.isSeparatorVisible)
        }

        // MARK: - A18, A26, A37 · every state, driven by a named scenario

        /// Ten scenarios, each asserting a **specific observable** rather than that something
        /// rendered. All of them run with no router on the machine, which is A37.
        @MainActor
        @Test(
            "each fixture scenario puts the shell in its own state",
            arguments: [
                FixtureControlAPIClient.Scenario.populated,
                .empty, .partial, .error, .success, .offline, .unauthorized, .overflow, .disabled
            ]
        )
        func everyScenarioHasItsOwnObservable(scenario: FixtureControlAPIClient.Scenario) async throws {
            let model = try Self.model(scenario)
            await model.refresh(at: Date(timeIntervalSince1970: 1_000_000))

            switch scenario {
            case .offline:
                #expect(model.readout.state == .failed(.routerNotRunning))
                // A18: absent, never zero.
                #expect(model.readout.running == nil)
                #expect(model.readout.declared == nil)
                #expect(model.badge(for: .servers) == nil)
            case .unauthorized:
                #expect(model.readout.state == .failed(.unauthorized))
                #expect(model.servers == nil)
            case .error:
                guard case let .failed(error) = model.readout.state else {
                    Issue.record("the error scenario did not fail the readout"); return
                }
                // The router's own status and hint survive to the surface rather than being
                // flattened into "something went wrong".
                #expect(error.headline == ControlAPIError.server(status: 422, message: "").headline)
            case .empty:
                #expect(model.readout.state == .empty)
                #expect(model.readout.declared == 0)
            case .partial:
                guard case let .partial(_, _, notIndexed) = model.readout.state else {
                    Issue.record("the partial scenario did not report anything unindexed"); return
                }
                #expect(notIndexed > 0)
            case .overflow:
                let names = try #require(model.servers).map(\.name)
                #expect(names.contains { $0.count > 40 }, "the overflow scenario carried no long name")
            case .disabled:
                let servers = try #require(model.servers)
                #expect(servers.contains { $0.placard != nil }, "no placarded server to dim")
            case .populated, .success:
                #expect(model.readout.hasCounts)
                guard case let .populated(running, declared) = model.readout.state else {
                    Issue.record("\(scenario) did not populate"); return
                }
                #expect(declared > 0)
                #expect(running <= declared, "more servers running than declared is not observable")
            default:
                Issue.record("\(scenario) has no assertion")
            }
        }

        /// The loading state is the *absence* of an answer, so it is asserted by not answering
        /// rather than by a flag. A `refresh` against the loading scenario never returns, which is
        /// why this races it against a deadline instead of awaiting it.
        @MainActor
        @Test("a shell with no answer yet is loading, not empty")
        func loadingIsTheAbsenceOfAnAnswer() async throws {
            let model = try Self.model(.loading)
            let poll = Task { await model.refresh(at: Date(timeIntervalSince1970: 1_000_000)) }
            try await Task.sleep(for: .milliseconds(120))
            #expect(model.readout.state == .loading)
            #expect(model.readout.state != .empty)
            poll.cancel()
        }

        // MARK: - A28 · the failure copy is the client's own, unchanged

        @MainActor
        @Test(
            "the readout renders ControlAPIError's wording verbatim",
            arguments: [ControlAPIError.routerNotRunning, .unauthorized]
        )
        func failureCopyIsVerbatim(error: ControlAPIError) async throws {
            let scenario: FixtureControlAPIClient.Scenario =
                error == .routerNotRunning ? .offline : .unauthorized
            let model = try Self.model(scenario)
            await model.refresh(at: Date(timeIntervalSince1970: 1_000_000))

            guard case let .failed(rendered) = model.readout.state else {
                Issue.record("\(scenario) did not fail"); return
            }
            // Equality on the error itself, so the surface cannot substitute a different condition
            // with similar-looking copy.
            #expect(rendered == error)
            #expect(rendered.headline == error.headline)
            #expect(rendered.advice == error.advice)
        }

        /// The deviation this item recorded, asserted rather than described: the client offers an
        /// action label for both full-pane failures and the shell renders **no control**, because
        /// neither operation exists behind the control API in this build.
        @Test("the two offered actions exist on the error and are deliberately not rendered")
        func offeredActionsAreNotRenderedAsButtons() throws {
            #expect(ControlAPIError.routerNotRunning.actionLabel == "Start the router")
            #expect(ControlAPIError.unauthorized.actionLabel == "Re-pair…")

            let source = try Self.repoFile("app/Sources/MCPRouterUI/Shell/Readout.swift")
            #expect(!source.contains("actionLabel"), "the readout reached for an action it cannot perform")
            #expect(!source.contains("Button("), "the readout shipped a control with nothing behind it")
        }

        // MARK: - A29 · the skeleton is the readout's own geometry

        @Test("the loading skeleton and the populated readout are one height")
        func skeletonMatchesPopulatedGeometry() throws {
            // Both forms are held to the same constant, which is the only way the sidebar does not
            // move when the first poll lands. Composed from tokens, so it follows `DESIGN.md`.
            #expect(ReadoutGeometry.height > 0)
            #expect(
                ReadoutGeometry.height
                    == MetricToken.tableRows.leadingScalar * 2
                    + ReadoutGeometry.traceHeight
                    + ReadoutGeometry.spacing * 4
            )
            let source = try Self.repoFile("app/Sources/MCPRouterUI/Shell/Sidebar.swift")
            #expect(
                source.contains("ReadoutGeometry.height"),
                "the sidebar stopped holding the readout to its declared height"
            )
        }

        @Test("the loading state is a skeleton rather than a spinner")
        func loadingIsNeverASpinner() throws {
            let source = try Self.repoFile("app/Sources/MCPRouterUI/Shell/Readout.swift")
            #expect(!source.contains("ProgressView"), "§5 forbids a spinner over a blank pane")
        }

        // MARK: - A15 · no number the router does not observe

        @Test("the readout's copy carries no figure beyond the counts and the trace")
        func copyCarriesNoFabricatedMetric() {
            let strings = [
                ReadoutCopy.runningLabel,
                ReadoutCopy.counts(running: 3, declared: 8),
                ReadoutCopy.notIndexed(2),
                ReadoutCopy.emptyTitle,
                ReadoutCopy.emptyDetail,
                ReadoutCopy.loadingLabel,
                ReadoutCopy.accessibilityLabel(running: 3, declared: 8)
            ]
            for forbidden in ["memory", "saved", "saving", "RAM", "MB", "GB", "footprint"] {
                for string in strings {
                    #expect(
                        !string.lowercased().contains(forbidden.lowercased()),
                        "'\(string)' claims a \(forbidden) figure the router never measures"
                    )
                }
            }
            #expect(ReadoutCopy.counts(running: 3, declared: 8) == "3 of 8")
        }

        // MARK: - A12 · sentence case, and no transform to remove

        @Test("no shell file applies an uppercasing transform")
        func noUppercasingAnywhere() throws {
            for file in Self.shellFiles {
                let source = try Self.repoFile(file)
                #expect(!source.contains(".uppercased()"), "\(file) upper-cases a string it renders")
                #expect(!source.contains("textCase(.uppercase)"), "\(file) tracks a header uppercase")
            }
        }

        @Test("the group headers are the sentence-case literals, not derived from the case name")
        func headersAreLiteralSentenceCase() {
            #expect(DestinationGroup.running.rawValue == "Running")
            #expect(DestinationGroup.library.rawValue == "Library")
        }

        // MARK: - A6 · the indicator colours do only their own job

        /// Each declared use is checked against `DESIGN.md`'s own wording for the token, so "it
        /// looked good there" cannot be spelled as a justification.
        @Test("every indicator colour the shell uses is justified by the document's own meaning")
        func indicatorUsesAreJustified() throws {
            let design = try Self.repoFile("DESIGN.md")
            let meanings: [ColorToken: String] = [
                .accent: "selection, focus, the one primary action",
                .live: "a child process is running",
                .attention: "wants a human decision",
                .fail: "failed or tripped"
            ]
            for (token, meaning) in meanings {
                #expect(design.contains(meaning), "DESIGN.md no longer states \(token.rawValue)'s meaning")
            }

            for use in ShellChrome.indicatorUses {
                let documented = try #require(meanings[use.token], "\(use.token) is not an indicator colour")
                #expect(
                    documented.contains(use.justification),
                    "'\(use.justification)' is not part of \(use.token.rawValue)'s documented meaning"
                )
            }
        }

        /// The other direction, which is the one that actually goes wrong: a token drawn somewhere
        /// the declaration does not mention.
        @Test("no shell file draws an indicator colour the declaration does not list")
        func noUndeclaredIndicatorUse() throws {
            let declared = ShellChrome.indicatorTokensUsed
            let indicators: [ColorToken] = [.accent, .live, .attention, .fail]
            for file in Self.shellFiles {
                let source = try Self.repoFile(file)
                for token in indicators where source.contains("ColorToken.\(tokenCaseName(token))") {
                    #expect(
                        declared.contains(token),
                        "\(file) draws \(token.rawValue) but ShellChrome does not justify it"
                    )
                }
            }
            // `--fail` is declared nowhere and drawn nowhere: an offline router has not failed, and
            // painting it red would spend the token that means "failed or tripped" on absence.
            #expect(!declared.contains(.fail))
        }

        private func tokenCaseName(_ token: ColorToken) -> String {
            switch token {
            case .accent: "accent"
            case .live: "live"
            case .attention: "attention"
            case .fail: "fail"
            default: token.rawValue
            }
        }

        // MARK: - A8, A10 · opaque content, arrow cursor

        @Test("the window's content is an opaque token, never a material")
        func contentIsOpaque() throws {
            #expect(ShellChrome.contentBackground == .ground)
            for file in Self.shellFiles {
                let source = try Self.repoFile(file)
                for material in ["ultraThinMaterial", "thinMaterial", "regularMaterial",
                                 "thickMaterial", "ultraThickMaterial", "VisualEffectView"] {
                    #expect(
                        !source.contains(material),
                        "\(file) puts glass on content — §3.3 allows it on floating chrome only"
                    )
                }
            }
        }

        @Test("no shell element sets a pointing-hand cursor")
        func cursorIsAlwaysTheArrow() throws {
            #expect(!ShellChrome.usesPointingHandCursor)
            for file in Self.shellFiles {
                let source = try Self.repoFile(file)
                #expect(!source.contains("pointingHand"), "\(file) sets a web-content cursor")
                #expect(!source.contains(".pointerStyle(.link"), "\(file) sets a link pointer")
            }
        }

        // MARK: - A30, A31 · motion and the three accessibility settings

        @Test("row selection has no transition at all, not merely a fast one")
        func selectionIsImmediate() {
            #expect(ShellMotion.selectionAnimation() == nil)
        }

        @Test("a badge count change is a transform, and Reduce Motion removes it")
        func badgeBumpIsTransformOnly() {
            #expect(ShellMotion.badgeBump(reduceMotion: false) != nil)
            #expect(ShellMotion.badgeBump(reduceMotion: true) == nil)
            // A bump, not a leap: the scale is derived from two documented values.
            #expect(ShellMotion.badgeBumpScale > 1)
            #expect(ShellMotion.badgeBumpScale < 1.2)
        }

        /// The spring is the breaker's documented rise rather than a second one invented here.
        @Test("the bump reuses the design document's own spring")
        func bumpUsesTheDocumentedSpring() {
            #expect(BreakerGeometry.standard.riseDamping < 1)
            #expect(ShellMotion.badgeBumpHold == .milliseconds(
                Int(BreakerGeometry.standard.riseResponse * 1000)
            ))
        }

        @Test("no shell file animates opacity from zero on entry")
        func neverFadesInFromZero() throws {
            for file in Self.shellFiles {
                let source = try Self.repoFile(file)
                #expect(
                    !source.contains(".opacity(0)") || file.hasSuffix("ScrollEdge.swift"),
                    "\(file) may fade content in from nothing"
                )
            }
        }

        /// Each setting removes the effect and keeps the information — which is the half that is
        /// easy to fail in the flattering direction.
        @Test("Reduce Transparency makes the sidebar opaque without removing the zone")
        func reduceTransparencyKeepsTheZone() {
            #expect(ShellAccessibilityRules.sidebarIsOpaque(reduceTransparency: true))
            #expect(!ShellAccessibilityRules.sidebarIsOpaque(reduceTransparency: false))
            #expect(ShellChrome.sidebarBackground == .panel)
            #expect(ShellChrome.sidebarBackground != ShellChrome.contentBackground)
        }

        @Test("Differentiate Without Colour gives the attention badge a glyph, and only that one")
        func differentiateWithoutColourAddsAGlyph() {
            #expect(ShellAccessibilityRules.badgeNeedsGlyph(
                differentiateWithoutColor: true, source: .serversNeedingAttention
            ))
            // The neutral badge needs nothing: it was never telling you anything by hue.
            #expect(!ShellAccessibilityRules.badgeNeedsGlyph(
                differentiateWithoutColor: true, source: .serversNeverUsed
            ))
            #expect(!ShellAccessibilityRules.badgeNeedsGlyph(
                differentiateWithoutColor: false, source: .serversNeedingAttention
            ))
        }

        @Test("Reduce Motion removes the bump and never the new count")
        func reduceMotionKeepsTheNumber() {
            #expect(!ShellAccessibilityRules.badgeAnimates(reduceMotion: true))
            #expect(ShellAccessibilityRules.badgeAnimates(reduceMotion: false))
            // The count is rendered by `BadgeView` whatever `animates` is — only the transform is
            // conditional, which is what "removes the effect, not the information" means here.
            #expect(ShellMotion.badgeBump(reduceMotion: true) == nil)
        }

        // MARK: - A32 · restoration

        @MainActor
        @Test("the selected destination and the sidebar survive a new process")
        func restorationRoundTrips() throws {
            let (store, defaults, suite) = try Self.scratchStore()
            defer { defaults.removePersistentDomain(forName: suite) }

            let first = ShellModel(client: FixtureControlAPIClient(.populated), store: store)
            first.select(.evals)
            first.isSidebarVisible = false

            // A second model reading the same store is what a relaunch is, minus the process.
            let second = ShellModel(client: FixtureControlAPIClient(.populated), store: store)
            #expect(second.selection == .evals)
            #expect(second.isSidebarVisible == false)
        }

        @MainActor
        @Test("a stored destination this build no longer has falls back rather than blanking")
        func unknownStoredDestinationFallsBack() throws {
            let (store, defaults, suite) = try Self.scratchStore()
            defer { defaults.removePersistentDomain(forName: suite) }

            defaults.set("marketplaces", forKey: ShellRestoration.destinationKey)
            let model = ShellModel(client: FixtureControlAPIClient(.populated), store: store)
            #expect(model.selection == Destination.fallback)
            #expect(model.selection == .activity)
        }

        /// `bool(forKey:)` returns `false` for a key nobody wrote, which would hide the sidebar on
        /// every first launch. The boundary worth testing is the absent key, not the stored one.
        @MainActor
        @Test("a first launch shows the sidebar rather than inheriting Bool's zero value")
        func firstLaunchShowsTheSidebar() throws {
            let (store, defaults, suite) = try Self.scratchStore()
            defer { defaults.removePersistentDomain(forName: suite) }
            #expect(defaults.object(forKey: ShellRestoration.sidebarVisibleKey) == nil)
            #expect(store.restoredSidebarVisible())
        }

        // MARK: - A36 · one channel

        @Test("the shell opens no socket, no file and no process of its own")
        func theClientIsTheOnlyChannel() throws {
            for file in Self.shellFiles {
                let source = try Self.repoFile(file)
                for forbidden in ["URLSession", "Process(", "NSTask", "FileManager",
                                  "NWConnection", "Socket(", "socket("] {
                    #expect(
                        !source.contains(forbidden),
                        "\(file) reaches past the control API with \(forbidden)"
                    )
                }
            }
        }

        @MainActor
        @Test("the shell does not use ServerStateTracker, whose typed errors are discarded")
        func theTrackerIsNotUsed() throws {
            for file in Self.shellFiles {
                let source = try Self.repoFile(file)
                #expect(
                    !source.contains("ServerStateTracker("),
                    "\(file) built a tracker that cannot tell offline from an empty poll"
                )
            }
        }

        // MARK: - A22 · the disabled reason is reachable

        /// The bridge exists because SwiftUI's `.help()` does not reach an `NSMenuItem` — every item
        /// reported `AXHelp` as `missing value` until this walker was written. A walker that matched
        /// nothing would look identical to one that worked, so the count is the assertion.
        @MainActor
        @Test("the reason walker sets a tool tip on exactly the commands that have one")
        func menuReasonsApplyToDisabledCommands() {
            let menu = NSMenu()
            let disabled = MenuCommand.allCases.filter { $0.availability.reason != nil }
            for command in disabled {
                menu.addItem(NSMenuItem(title: command.title, action: nil, keyEquivalent: ""))
            }
            // A system item the app never declared, which must be left exactly as macOS left it.
            let foreign = NSMenuItem(title: "Emoji & Symbols", action: nil, keyEquivalent: "")
            menu.addItem(foreign)

            let applied = ShellMenuReasons.apply(to: menu)
            #expect(applied == disabled.count)
            #expect(applied > 0, "the walker matched nothing, which reads exactly like success")

            for item in menu.items where item !== foreign {
                #expect(item.toolTip == CommandAvailability.surfaceAbsent.reason)
                #expect(item.accessibilityHelp() == CommandAvailability.surfaceAbsent.reason)
            }
            #expect(foreign.toolTip == nil, "the walker touched an item macOS owns")
        }

        @MainActor
        @Test("the walker descends into submenus rather than only the top level")
        func menuReasonsDescend() {
            let root = NSMenu()
            let parent = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.addItem(NSMenuItem(title: MenuCommand.addServer.title, action: nil, keyEquivalent: ""))
            parent.submenu = submenu
            root.addItem(parent)

            #expect(ShellMenuReasons.apply(to: root) == 1)
        }

        // MARK: - A20 · the SwiftUI shortcut mapping

        /// The chord-level parity against §8 lives in `MenuCommandTests`. What is only checkable
        /// here is the crossing into SwiftUI, where a capital letter silently means shift.
        @Test("a chord's key never smuggles in a modifier the document did not ask for")
        func shortcutMappingAddsNoModifiers() {
            #expect(KeyChord("H").keyEquivalent.character == "h")
            #expect(KeyChord("H").eventModifiers == .command)
            #expect(KeyChord("H", [.command, .option]).eventModifiers == [.command, .option])
            #expect(KeyChord("N", [.command, .shift]).eventModifiers == [.command, .shift])
            #expect(KeyChord("S", [.command, .control]).eventModifiers == [.command, .control])
            #expect(KeyChord("⌫").keyEquivalent == .delete)
            #expect(KeyChord(",").keyEquivalent.character == ",")
            #expect(KeyChord("1").keyEquivalent.character == "1")
        }

        // MARK: - A25 · focus order

        @Test("the shell's focus order is a prefix of §8's, with nothing interposed")
        func focusOrderIsAPrefixOfTheDocument() throws {
            let design = try Self.repoFile("DESIGN.md")
            #expect(design.contains("Tab order runs sidebar → table → inspector"))
            let documented = ["sidebar", "table", "inspector"]
            let shipped = ShellWindow.focusOrder

            // M1 has no table and no inspector, so it ships the head of that order. What must be
            // true is that nothing of the shell's own sits between the sidebar and the content.
            #expect(shipped.first == documented.first)
            #expect(shipped.count == 2)
            #expect(shipped == ["sidebar", "content"])
        }

        // MARK: - The scaffold cannot outlive the surface it stands in for

        @Test("M1 installs no board, so every destination is scaffolded")
        func everyDestinationIsScaffoldedForNow() {
            #expect(BoardRegistry.installed.isEmpty)
            #expect(BoardRegistry.scaffolded == Destination.ordered)
        }

        /// The structural half of the orchestrator's condition: the placeholder cannot be built for
        /// a destination whose board has shipped. Not "should not" — the initialiser returns nil.
        @Test("the scaffold refuses to exist for a destination with a board")
        func scaffoldRefusesAnInstalledDestination() {
            for destination in Destination.allCases {
                let permission = ScaffoldedDestination(destination)
                #expect(
                    (permission != nil) == !BoardRegistry.hasBoard(destination),
                    "\(destination.title)'s scaffold and its board disagree about which exists"
                )
            }
        }

        @Test("the scaffold copy names the surface and offers no action it cannot perform")
        func scaffoldCopyIsHonest() throws {
            let title = ScaffoldCopy.title(for: .activity)
            #expect(title == "Activity isn't built yet")
            #expect(title.contains(ScaffoldCopy.sentinel))
            #expect(ScaffoldCopy.detail(for: .activity).contains("activity"))

            let source = try Self.repoFile("app/Sources/MCPRouterUI/Shell/ScaffoldPane.swift")
            #expect(!source.contains("Button("), "the scaffold offered a control with nothing behind it")
        }

        // MARK: - Icons

        @Test("every destination's icon name resolves to a real case")
        func destinationIconsResolve() {
            for destination in Destination.allCases {
                #expect(
                    Icon(rawValue: destination.iconName) != nil,
                    "\(destination.title) names an icon that does not exist"
                )
            }
        }

        /// Every file this item added under `MCPRouterUI`, so the source-level gates above cannot
        /// silently stop covering one.
        static let shellFiles = [
            "app/Sources/MCPRouterUI/Shell/ShellModel.swift",
            "app/Sources/MCPRouterUI/Shell/ShellWindow.swift",
            "app/Sources/MCPRouterUI/Shell/Sidebar.swift",
            "app/Sources/MCPRouterUI/Shell/Readout.swift",
            "app/Sources/MCPRouterUI/Shell/ScaffoldPane.swift",
            "app/Sources/MCPRouterUI/Shell/ScrollEdge.swift",
            "app/Sources/MCPRouterUI/Shell/ShellChrome.swift",
            "app/Sources/MCPRouterUI/Shell/ShellCommands.swift",
            "app/Sources/MCPRouterUI/Shell/ShellMenuReasons.swift"
        ]

        @Test("the file list this suite scans is the whole of what the item added")
        func shellFileListIsComplete() throws {
            var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            var root: URL?
            for _ in 0 ..< 8 {
                if FileManager.default.fileExists(atPath: dir.appendingPathComponent("DESIGN.md").path) {
                    root = dir; break
                }
                dir = dir.deletingLastPathComponent()
            }
            let shellDir = try #require(root).appendingPathComponent("app/Sources/MCPRouterUI/Shell")
            let onDisk = try FileManager.default
                .contentsOfDirectory(atPath: shellDir.path)
                .filter { $0.hasSuffix(".swift") }
                .sorted()
            let listed = Self.shellFiles
                .map { URL(fileURLWithPath: $0).lastPathComponent }
                .sorted()
            #expect(
                onDisk == listed,
                "a shell file exists that the source-level gates never look at: \(onDisk) vs \(listed)"
            )
        }
    }
#endif
