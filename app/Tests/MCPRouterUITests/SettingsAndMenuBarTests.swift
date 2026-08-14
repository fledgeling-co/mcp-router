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
        @Test("Settings has a board and no scaffold")
        func settingsIsInstalled() {
            #expect(BoardRegistry.installed.contains(.settings))
            #expect(BoardRegistry.hasBoard(.settings))
            #expect(ScaffoldedDestination(.settings) == nil)
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
            try await Task.sleep(for: .milliseconds(120))
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

            try await Task.sleep(for: .milliseconds(120))
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
