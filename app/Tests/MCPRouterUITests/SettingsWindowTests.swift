#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// The Settings window: its own selection, its own persistence, its own scroll, and the icons
    /// its source list resolves.
    @MainActor
    @Suite("M15 — the Settings window")
    struct SettingsWindowTests {
        // MARK: - The source list owns its own selection

        /// Requirement 6, and the brief's own recorded bug: in the mock the console's board switcher
        /// cleared the settings list's selection through an unscoped query, and the selected pane
        /// rendered with no fill.
        ///
        /// Textual, deliberately, and for the reason `SettingsAndMenuBarTests`' A28 guard gives:
        /// this is a claim about how the view is *built*. A rendered assertion that the two
        /// selections happen to differ in the one state a test drove cannot tell "they are separate
        /// bindings" from "they agree today".
        @Test("the window's selection is its own, never the shell's")
        func selectionIsNotShared() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Settings/SettingsWindow.swift"
            )
            let body = try ShellTestSupport.declarationBody(
                of: "private var paneSelection: Binding<SettingsPane?>", in: source
            )
            #expect(!body.contains("shell."), "the pane binding reaches into the console's model")
            #expect(body.contains("store.save(settingsPane:"))
            // And the list is bound to that binding rather than to anything the shell holds.
            #expect(source.contains("List(selection: paneSelection)"))
            #expect(
                !source.contains("$shell.selection"),
                "the settings list is bound to the console's destination selection"
            )
        }

        /// The other half: a deselection cannot leave the window with no pane at all. Requirement 5
        /// is that exactly one pane is selected, and `List(selection:)` hands back nil when a row is
        /// deselected.
        @Test("a deselection keeps the current pane rather than emptying the detail")
        func deselectionKeepsAPane() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Settings/SettingsWindow.swift"
            )
            let body = try ShellTestSupport.declarationBody(
                of: "private var paneSelection: Binding<SettingsPane?>", in: source
            )
            #expect(
                body.contains("guard let new else { return }"),
                "a nil selection would leave the window with no pane and no detail"
            )
        }

        // MARK: - The pane survives the window being destroyed

        /// A `Settings` scene destroys its window on close, so a scene-local `@State` resets the
        /// pane to Router on every `⌘,`. That is a regression against the Settings board, whose
        /// selected destination survived because `ShellRestoration` held it — so this holds the pane
        /// the same way, and this is the evidence lane a scene-local `@State` has none of.
        @Test("the chosen pane survives a process boundary, and an unknown one falls back")
        func paneRestoresAcrossAProcessBoundary() throws {
            let scratch = try ShellTestSupport.scratchStore()
            defer { scratch.tearDown() }

            // Absent key: Router, the first pane, rather than nothing.
            #expect(scratch.store.restoredSettingsPane() == .router)

            scratch.store.save(settingsPane: .security)
            // A second store over the same domain is the process boundary this clause is about —
            // and it is also what a `Settings` scene does on every close and reopen.
            let second = ShellRestoration(defaults: scratch.defaults)
            #expect(second.restoredSettingsPane() == .security)

            // A pane name this build no longer has lands somewhere real rather than blanking.
            scratch.defaults.set("a-pane-that-was-removed", forKey: ShellRestoration.settingsPaneKey)
            #expect(second.restoredSettingsPane() == .router)
        }

        @Test("the window and the store name the same defaults key, and it is not the console's")
        func restorationKeyIsItsOwn() {
            #expect(ShellRestoration.settingsPaneKey == "shell.settingsPane")
            #expect(ShellRestoration.settingsPaneKey != ShellRestoration.destinationKey)
        }

        // MARK: - The icons the source list resolves

        /// `Destination.iconName` has this guard and `SettingsPane.iconName` needs it for the same
        /// reason: the string crosses a module boundary because `MCPRouterKit` may import no UI
        /// framework, so nothing but a test can prove it points at a real case. An unknown name
        /// renders the fallback rather than failing.
        @Test("every pane's icon name resolves to a real Icon case")
        func paneIconsResolve() {
            for pane in SettingsPane.allCases {
                #expect(
                    Icon(rawValue: pane.iconName) != nil,
                    "\(pane.title) names '\(pane.iconName)', which is not an Icon case"
                )
            }
        }

        /// `Icon.settings` outlived `Destination.settings`, and this is why it was kept: the source
        /// list still needs a gear. A case with no caller would have been deleted, and deleting it
        /// re-bases the sprite count `DesignSystemTests` asserts.
        @Test("Icon.settings keeps a caller after the destination that named it went")
        func settingsIconKeepsItsCaller() {
            #expect(SettingsPane.advanced.iconName == Icon.settings.rawValue)
            #expect(Icon.settings.systemName == "gearshape")
        }

        // MARK: - The window owns its scroll, where the board deliberately did not

        /// Ported **inverted**, and the inversion is the correct port rather than a re-litigation.
        /// `SettingsBoard` refused a `ScrollView` of its own because it sat inside the shell's, and
        /// nesting one made it publish three `AXScrollArea`s where every other board published two.
        /// There is no shell around this window, so there is no outer scroller to nest inside.
        @Test("the window installs exactly one detail scroll view")
        func theWindowOwnsOneScroll() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Settings/SettingsWindow.swift"
            )
            #expect(source.components(separatedBy: "ScrollView {").count - 1 == 1)
            // And no pane installs a second one inside it, which is the nesting that made the board
            // publish a scroll area that could not scroll.
            for pane in ShellTestSupport.settingsFiles where pane.contains("/Panes/") {
                let paneSource = try ShellTestSupport.repoFile(pane)
                #expect(
                    !paneSource.contains("ScrollView"),
                    "\(pane) nests a scroll view inside the window's own"
                )
            }
        }

        /// **Exactly one initializer**, so the scene and the measurement harness construct this the
        /// same way and differ only in the store they pass. Two initializers is how a surface comes
        /// to be measured in a configuration nobody ships.
        @Test("SettingsWindow has one initializer, which both the scene and MeasureDump use")
        func oneInitializer() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Settings/SettingsWindow.swift"
            )
            #expect(source.components(separatedBy: "public init(").count - 1 == 1)

            // The whole harness target rather than `main.swift`: which of its files draws the
            // Settings arm has already moved once, and this read stopped covering it silently.
            let harness = try ShellTestSupport.measureDumpSources()
            #expect(harness.contains("store: InMemoryTokenStore()"), "no in-memory store anywhere")
            #expect(
                !harness.contains("KeychainTokenStore()"),
                "the harness would read a keychain it has no access group for (-34018)"
            )
        }

        // MARK: - The router-stopped state

        /// Requirement 9, and where the build parts company with the mock on purpose. The mock's
        /// `v-empty` frame refuses the whole window — "Settings are unavailable while the router is
        /// stopped". The build opens: the menu-bar preference is genuinely still editable, and a
        /// window that refused to open would be hiding a working control behind a stopped daemon.
        @Test("with the router stopped the window still opens, and says so where it must")
        func routerStoppedKeepsTheWindowUsable() async throws {
            let model = try ShellTestSupport.model(.offline)
            await model.refresh(at: Date())
            #expect(model.trackerState != nil, "the offline fixture never answered at all")

            // Every pane row is still live: the source list is over `allCases` unconditionally.
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Settings/SettingsWindow.swift"
            )
            #expect(source.contains("ForEach(SettingsPane.ordered)"))
            #expect(
                !source.contains("if offlineError") && !source.contains("guard offlineError"),
                "the window branches on the router before drawing its source list"
            )

            // And the sentence the router-fed panes draw is `ControlAPIError`'s own, verbatim,
            // rather than a second wording written here.
            let router = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Settings/Panes/RouterPane.swift"
            )
            #expect(router.contains("\\(error.headline). \\(error.advice)"))
        }

        // MARK: - M8's two source-level gates, re-pointed at the window

        // Moved here from `SettingsAndMenuBarTests` when this window replaced the board. They are
        // claims about how the *Settings surface* is built, which is this suite's subject, and the
        // file they were in was over its 400-line cap — met by splitting on a real seam rather than
        // raised, per this repository's own lesson from R2R.

        // MARK: - A28 · offline loses the router's facts and nothing else

        /// The lines of the group stack in `body`, stripped and without blanks.
        ///
        /// The stack is found by its own spacing token rather than by line number, so an edit above
        /// it does not silently make this read a different block.
        ///
        /// **Its closing brace is found at the opener's own indentation, computed rather than
        /// written down.** This used to search for a literal `"\n" + 20 spaces + "}"`, which made
        /// the helper robust to edits *above* the stack — as the paragraph above claims — and
        /// brittle to a change in the stack's own nesting depth, which the claim does not cover.
        /// D2 removed the redundant `ScrollView` that wrapped this stack; the four groups were
        /// unchanged, the assertion was still true, and the helper dedented by four spaces, missed
        /// its terminator, ran on to the next 20-space brace and returned **thirty-six** lines of
        /// the rest of the file. A28 failed while the property it guards held perfectly.
        ///
        /// A slice terminator that encodes how deeply nested the code happens to be today is a
        /// second, invisible assertion about nesting that nobody wrote and nobody wants.
        private static func groupStackBody(in source: String) throws -> [String] {
            let opener = "VStack(alignment: .leading, spacing: SettingsMetrics.groupGap) {"
            let after = try #require(
                source.range(of: opener),
                "the settings pane no longer composes its groups in a groupGap stack"
            )
            // The whitespace between the previous newline and the opener — the depth this stack is
            // written at, whatever that happens to be.
            let lineStart = source[..<after.lowerBound].lastIndex(of: "\n")
                .map { source.index(after: $0) } ?? source.startIndex
            let indent = String(source[lineStart ..< after.lowerBound])
            let rest = source[after.upperBound...]
            let close = try #require(rest.range(of: "\n" + indent + "}"), "the stack never closes")
            return rest[..<close.lowerBound]
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }

        /// A28 was true and asserted nowhere, for the same reason A29 was: the four groups sit
        /// unconditionally in `body`, so an offline router can only empty the *Router* group and can
        /// never remove Menu bar or Control token. "True by construction" is precisely the property
        /// a later edit removes without anything objecting — wrapping the token group in
        /// `if facts != nil` to "tidy up the offline pane" is a one-line change that reads as
        /// reasonable and silently deletes the only surface for forgetting a rejected credential.
        ///
        /// Textual, deliberately, and for the reason A29 gives: this is a claim about how the view
        /// is *built*. A rendered assertion that the two groups appear while offline cannot tell
        /// "they are unconditional" from "they happen to be reachable in the one state I drove".
        @Test("A28 — every group but Router is unconditional, so offline cannot remove one")
        func offlineKeepsEveryOtherGroup() throws {
            // **The four groups live on three panes now**, so the claim is made three times rather
            // than once. It is the same claim: a router that is down may empty the Router *card* and
            // may never remove a group — and the window makes it strictly harder to break, because
            // wrapping a whole pane in `if facts != nil` would leave a source-list row selecting
            // nothing at all.
            let expected = [
                "app/Sources/MCPRouterUI/Settings/Panes/RouterPane.swift":
                    ["routerGroup", "warmSetGroup"],
                "app/Sources/MCPRouterUI/Settings/Panes/SecurityPane.swift":
                    ["tokenGroup", "pairedGroup"],
                "app/Sources/MCPRouterUI/Settings/Panes/AdvancedPane.swift":
                    ["filesGroup", "identityFooter"]
            ]
            for (path, groups) in expected {
                let lines = try Self.groupStackBody(in: ShellTestSupport.repoFile(path))
                #expect(
                    lines == groups,
                    """
                    \(path)'s groups must be bare properties in order. Found: \(lines). Anything \
                    else — an `if`, a `guard`, a group moved inside another — means a router that \
                    is down can take a group with it, which is the partial rule A28 states.
                    """
                )
            }

            // And the one pane that reads nothing from the router must not have grown a branch on
            // it: the menu-bar preference stays editable while the router is stopped, which is why
            // this window opens where the mock's own empty frame refuses to.
            let menuBar = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Settings/Panes/MenuBarPane.swift"
            )
            #expect(
                !menuBar.contains("offlineError") && !menuBar.contains("trackerState"),
                """
                the Menu bar pane reads the router, so a stopped router could disable a preference \
                that is entirely this app's
                """
            )
        }

        /// A28's second half: the pane never shows a router value it does not have.
        ///
        /// `routerGroup` must test the error **before** the facts, so the two cannot both render.
        /// Reversing the branches compiles, passes every other test, and draws stale endpoint rows
        /// beside a banner saying the router never answered.
        @Test("A28 — the offline branch precedes the facts branch, so neither renders beside the other")
        func offlineBranchPrecedesFacts() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Settings/Panes/RouterPane.swift"
            )
            let error = try #require(source.range(of: "if let error = offlineError {"))
            let facts = try #require(source.range(of: "} else if let facts {"))
            #expect(
                error.upperBound < facts.lowerBound,
                "the facts branch must be the `else` of the offline branch, not the other way round"
            )
            // And there is exactly one place facts are read, so a second, unguarded one cannot hide
            // further down the file.
            #expect(source.components(separatedBy: "else if let facts {").count - 1 == 1)
        }

        /// The A28 guards' own red-green, kept rather than performed once by hand.
        @Test("A28's guards can fail")
        func groupStackGuardCanFail() throws {
            // **Opener and terminator come from one indent**, the only relationship
            // `groupStackBody` relies on. This fixture put the opener at column zero and its closer
            // at a literal depth 20 — consistent only while the helper looked for a fixed brace.
            let indent = String(repeating: " ", count: 20)
            let wrapped = indent + "VStack(alignment: .leading, spacing: SettingsMetrics.groupGap) {\n"
                + indent + "    routerGroup\n"
                + indent + "    if facts != nil { tokenGroup }\n"
                + indent + "}"
            let lines = try Self.groupStackBody(in: wrapped)
            #expect(lines == ["routerGroup", "if facts != nil { tokenGroup }"])
            #expect(lines != ["routerGroup", "menuBarGroup", "warmSetGroup", "tokenGroup"])

            // The indent is load-bearing, so it gets its own red-green: the same stack at another
            // depth must still read correctly — the case the fixed terminator could not survive.
            let deeper = String(repeating: " ", count: 8)
            let nested = deeper + "VStack(alignment: .leading, spacing: SettingsMetrics.groupGap) {\n"
                + deeper + "    routerGroup\n"
                + deeper + "}"
            #expect(try Self.groupStackBody(in: nested) == ["routerGroup"])

            // The ordering half: a reversed pair puts `facts` first, and the comparison flips.
            let reversed = "} else if let facts {\nif let error = offlineError {"
            let error = try #require(reversed.range(of: "if let error = offlineError {"))
            let factsRange = try #require(reversed.range(of: "} else if let facts {"))
            #expect(!(error.upperBound < factsRange.lowerBound))
        }

        // MARK: - A29 · the skeleton and the populated row are the same height

        /// Every `minHeight:` in a file, as written.
        ///
        /// Deliberately textual. A29 is a claim about *how the view is built* — that one frame
        /// governs both states — and a rendered-height assertion cannot distinguish "both states
        /// are 32pt because one modifier sets them" from "both states are 32pt today because two
        /// modifiers happen to agree". The second passes until someone edits one of them.
        private static func minHeights(in source: String) -> [String] {
            source
                .components(separatedBy: "minHeight:")
                .dropFirst()
                .map { fragment in
                    fragment
                        .prefix { $0 != ")" && $0 != "," && $0 != "\n" }
                        .trimmingCharacters(in: .whitespaces)
                }
        }

        /// A29 was asserted nowhere. It was *true* — `SettingsRow` puts its `.frame(minHeight:)`
        /// outside the branch that chooses between a value and a skeleton, so the two cannot
        /// disagree — but "true by construction" is exactly the property that a later edit removes
        /// without anything objecting, and the clause is typed **T**.
        ///
        /// The guard is the count as much as the value: a second `minHeight` in this file is how a
        /// separate skeleton height would arrive, and it fails here before it can make the pane
        /// jump at the moment values land.
        @Test("A29 — one row height governs both the skeleton and the populated row")
        func skeletonAndPopulatedRowShareOneHeight() throws {
            let parts = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Settings/SettingsParts.swift"
            )
            let heights = Self.minHeights(in: parts)
            #expect(
                heights == ["SettingsMetrics.rowHeight"],
                """
                SettingsRow must set exactly one row height, from the shared constant. \
                Found \(heights.count): \(heights). A second one means the skeleton and the \
                populated row can drift, which is the resize A29 exists to prevent.
                """
            )

            // The value the constant carries is derived from tokens, not a literal — the same rule
            // A31 holds the views to, checked here because this is the one number A29 is about.
            #expect(
                SettingsMetrics.rowHeight
                    == MetricToken.tableRows.leadingScalar + MetricToken.selectionInset.leadingScalar * 2
            )
        }

        /// The guard's own red-green, kept as a permanent test rather than performed once by hand.
        /// A guard that has never been seen to fail is a decoration.
        @Test("A29's guard can fail")
        func rowHeightGuardCanFail() {
            let diverged = """
            .frame(minHeight: SettingsMetrics.rowHeight)
            .frame(minHeight: 24)
            """
            #expect(Self.minHeights(in: diverged) == ["SettingsMetrics.rowHeight", "24"])

            let single = ".frame(minHeight: SettingsMetrics.rowHeight)"
            #expect(Self.minHeights(in: single) == ["SettingsMetrics.rowHeight"])
        }
    }
#endif
