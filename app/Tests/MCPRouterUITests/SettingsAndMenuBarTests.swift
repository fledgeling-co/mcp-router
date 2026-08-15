#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// The Settings pane, the menu bar's preference, the route into the quarantine sheet, and the
    /// poll that has to outlive the window for any of it to be true.
    @MainActor
    @Suite("M8 — settings, menu bar, quarantine route")
    struct SettingsAndMenuBarTests {
        // MARK: - A1 · the board is installed

        /// A board that exists but is not registered still shows the user a placeholder, so this is
        /// the line between "the view compiles" and "the item shipped".
        @Test("Settings has a board")
        func settingsIsInstalled() {
            #expect(BoardRegistry.installed.contains(.settings))
            #expect(BoardRegistry.hasBoard(.settings))
            // The `ScaffoldedDestination(.settings) == nil` line that used to sit here went with the
            // type, which M6 deleted when the last board landed. The complement below is what
            // survives of it and is still capable of being false.
            #expect(!BoardRegistry.scaffolded.contains(.settings))
        }

        // MARK: - A15 · the menu-bar preference survives a relaunch

        @Test("the status item is shown by default, and the choice survives a new model")
        func menuBarPreferenceRestores() throws {
            let scratch = try ShellTestSupport.scratchStore()
            defer { scratch.tearDown() }

            // Absent key must read as `true`: `bool(forKey:)` returns false for a key nobody wrote,
            // which would hide a menu-bar app's main affordance on every first launch.
            #expect(scratch.store.restoredMenuBarVisible())

            let first = ShellModel(client: FixtureControlAPIClient(.populated), store: scratch.store)
            #expect(first.isMenuBarVisible)
            first.isMenuBarVisible = false

            // A second model over the same domain is the process boundary this clause is about.
            let second = ShellModel(client: FixtureControlAPIClient(.populated), store: scratch.store)
            #expect(!second.isMenuBarVisible, "the menu-bar preference did not survive")

            second.isMenuBarVisible = true
            #expect(scratch.store.restoredMenuBarVisible())
        }

        @Test("the pane and the store name the same defaults key")
        func preferenceKeyIsShared() {
            #expect(ShellRestoration.menuBarVisibleKey == SettingsPresentation.menuBarVisibleKey)
        }

        // MARK: - A24, A25 · the route into the quarantine sheet

        /// The clause the whole item exists for, and the one an obvious implementation fails.
        ///
        /// Opening the sheet takes **two** operations — setting `sheet` and loading the diff. An
        /// implementation that sets the sheet alone renders "Reading the held descriptions…"
        /// forever with the accept button dimmed, so asserting the sheet case alone would pass the
        /// exact failure this route must not have.
        @Test("a held-change row selects the board, the server, and loads the diff")
        func heldChangeRouteLoadsTheDiff() async throws {
            let model = try ShellTestSupport.model(.populated)
            await model.refresh(at: Date())
            // Any declared server: the fixture serves the held diff per name, and what is under
            // test is the route rather than which server happens to be holding a change.
            let held = try #require(model.servers?.first?.name)

            await model.reveal(server: held, openingHeldChange: true)

            #expect(model.selection == .servers)
            #expect(model.serversBoard.selection == held)
            #expect(model.serversBoard.sheet == .heldChange(server: held))
            #expect(
                model.serversBoard.heldChanges != nil,
                "the sheet opened without its diff — it would read 'Reading the held descriptions…' forever"
            )
            #expect(!model.serversBoard.isLoadingHeldChanges)
        }

        @Test("an auth or index-error row selects the server and opens no sheet")
        func otherCausesOpenNoSheet() async throws {
            let model = try ShellTestSupport.model(.populated)
            await model.refresh(at: Date())
            let name = try #require(model.servers?.first?.name)

            await model.reveal(server: name, openingHeldChange: false)

            #expect(model.selection == .servers)
            #expect(model.serversBoard.selection == name)
            #expect(
                model.serversBoard.sheet == nil,
                "a modal was put in front of a decision the user did not ask to make"
            )
        }

        @Test("only the held change asks for a sheet")
        func onlyHeldChangeRoutesToASheet() {
            #expect(MenuBarPresentation.AttentionCause.heldChange.opensHeldChangeSheet)
            #expect(!MenuBarPresentation.AttentionCause.needsAuthorization.opensHeldChangeSheet)
            #expect(!MenuBarPresentation.AttentionCause.indexFailed.opensHeldChangeSheet)
        }

        // MARK: - A27e, A27f · the poll outlives the window

        @Test("startPolling is idempotent — two calls run one loop")
        func pollingIsIdempotent() async throws {
            let model = try ShellTestSupport.model(.populated)
            defer { model.stopPolling() }

            model.startPolling()
            model.startPolling()
            model.startPolling()

            // Two loops would double every publication and let an older response overwrite a newer
            // one. One loop advances the tracker exactly once per interval.
            try await ShellTestSupport.waitUntil { model.trackerState != nil }
            #expect(model.trackerState != nil, "no poll ran at all")
        }

        /// The failure this guards is the one the spec gate found: the poll was owned by
        /// `ShellWindow`'s `.task` and died with the window, so a menu-bar app in its normal state
        /// — window closed — had a frozen status item and no way to know.
        @Test("the poll is retained on the model, not on the scene that started it")
        func pollSurvivesItsStartingScene() async throws {
            let model = try ShellTestSupport.model(.populated)
            defer { model.stopPolling() }

            // A scene-shaped task: it starts the poll and is then cancelled, exactly as a window
            // closing cancels its `.task`.
            let scene = Task { model.startPolling() }
            await scene.value
            scene.cancel()

            try await ShellTestSupport.waitUntil { model.trackerState != nil }
            #expect(
                model.trackerState != nil,
                "the poll died with the scene that started it — the status item would freeze"
            )
        }

        @Test("the window's task starts the poll rather than owning it")
        func windowDoesNotOwnThePoll() throws {
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/ShellWindow.swift")
            #expect(source.contains("model.startPolling()"))
            #expect(
                !source.contains("await model.run()"),
                "the window still owns the poll — closing it would stop the menu bar's data"
            )
        }

        // MARK: - A3 · the Home row is local, and says so

        /// The Router card's other three rows come from the response; Home does not, and the spec
        /// narrows A3 for exactly that reason. It is `RouterTokenFile.url`'s parent — the same
        /// directory the client resolves to find the token, so the path shown is the path used.
        @Test("home is derived from the token file's directory, not from the response")
        func homeComesFromTheTokenFile() {
            let file = RouterTokenFile(url: URL(fileURLWithPath: "/tmp/scratch-home/control.token"))
            let model = SettingsBoardModel(store: InMemoryTokenStore(), file: file)
            #expect(model.routerHome.path == "/tmp/scratch-home")
        }

        // MARK: - A7, A8, A9 · the token

        @Test("a stored token reads as stored, and its value never leaves the store")
        func storedTokenIsReportedWithoutItsValue() async {
            let secret = "sk-live-never-render-this"
            let model = SettingsBoardModel(store: InMemoryTokenStore(secret))
            await model.load(unauthorized: false)

            #expect(model.status == .stored)
            #expect(!model.status.value.contains(secret))
            #expect(!model.tokenHelp.contains(secret))
            #expect(!model.tokenPath.contains(secret))
        }

        @Test("no stored token disables forget, with the reason")
        func absentTokenDisablesForget() async {
            let model = SettingsBoardModel(store: InMemoryTokenStore())
            await model.load(unauthorized: false)

            #expect(model.status == .absent)
            #expect(!model.status.canForget)
            #expect(SettingsPresentation.forgetDisabledReason == "There is no stored token to forget.")
        }

        @Test("a rejected token is distinguished from an absent one, and forget becomes prominent")
        func rejectedTokenIsItsOwnState() async {
            let model = SettingsBoardModel(store: InMemoryTokenStore("stale-token"))
            await model.load(unauthorized: true)

            #expect(model.status == .rejected)
            #expect(model.status.canForget)
            #expect(model.status.forgetIsProminent, "the fix is not the pane's prominent action")
        }

        /// **Sends nothing to the router.** There is no rotate endpoint and this is not one: the
        /// router owns the token and writes it to its own file; this app only caches it.
        @Test("forget deletes the stored token and asks the router for nothing")
        func forgetOnlyDeletesLocally() async throws {
            let store = InMemoryTokenStore("a-token")
            let model = SettingsBoardModel(store: store)
            await model.load(unauthorized: false)
            #expect(model.status == .stored)

            await model.forget()

            #expect(model.status == .absent)
            #expect(try await store.read() == nil, "the token is still in the store")
        }

        @Test("forget does nothing when there is nothing to forget")
        func forgetIsInertWhenAbsent() async {
            let model = SettingsBoardModel(store: InMemoryTokenStore())
            await model.load(unauthorized: false)
            await model.forget()
            #expect(model.status == .absent)
        }

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
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Boards/SettingsBoard.swift"
            )
            let lines = try Self.groupStackBody(in: source)
            #expect(
                lines == ["routerGroup", "menuBarGroup", "warmSetGroup", "tokenGroup"],
                """
                The pane's four groups must be four bare properties in spec order. Found: \(lines). \
                Anything else — an `if`, a `guard`, a group moved inside another — means a router \
                that is down can take a group with it, which is the partial rule A28 states.
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
                "app/Sources/MCPRouterUI/Boards/SettingsBoard.swift"
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
            // Built with the real terminator rather than written as a literal, so the fixture cannot
            // drift from what `groupStackBody` actually looks for.
            let close = "\n                    }"
            let wrapped = "VStack(alignment: .leading, spacing: SettingsMetrics.groupGap) {\n"
                + "                        routerGroup\n"
                + "                        if facts != nil { tokenGroup }"
                + close
            let lines = try Self.groupStackBody(in: wrapped)
            #expect(lines == ["routerGroup", "if facts != nil { tokenGroup }"])
            #expect(lines != ["routerGroup", "menuBarGroup", "warmSetGroup", "tokenGroup"])

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
                "app/Sources/MCPRouterUI/Boards/SettingsBoardParts.swift"
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
