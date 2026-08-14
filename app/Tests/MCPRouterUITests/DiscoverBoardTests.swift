#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    @Suite("M5 · the Discover board")
    @MainActor
    struct DiscoverBoardTests {
        private func entry(
            id: String,
            name: String? = nil,
            useCount: Int? = nil,
            install: RegistryInstall? = RegistryInstall(type: .stdio, command: "npx", args: ["-y", "s"]),
            installed: Bool? = nil
        ) -> RegistryEntry {
            RegistryEntry(
                id: id,
                name: name ?? id,
                displayName: id.capitalized,
                description: "",
                source: .smithery,
                useCount: useCount,
                install: install,
                installed: installed
            )
        }

        private func response(_ results: [RegistryEntry]) -> RegistrySearchResponse {
            RegistrySearchResponse(
                results: results,
                sources: RegistrySources(official: 0, smithery: results.count, merged: results.count),
                warnings: []
            )
        }

        // MARK: - A1 · the board is installed, not scaffolded

        /// The assertion the item is actually done against. A board that compiles but is absent from
        /// `installed` still shows the user "This part of the app isn't built yet".
        @Test("Discover is registered, so its pane is not the placeholder")
        func discoverIsInstalled() {
            #expect(BoardRegistry.hasBoard(.discover))
            #expect(BoardRegistry.installed.contains(.discover))
            // The `ScaffoldedDestination(.discover) == nil` line went with the type when M6 removed
            // the placeholder. This is the same claim, made against what still exists.
            #expect(!BoardRegistry.scaffolded.contains(.discover))
        }

        // MARK: - A5 · detail-then-install

        /// The brief's rule: it must not be one click from a gameable ranking to executing someone's
        /// code. Asserted as the absence of a call rather than as the absence of a button, because a
        /// button can be added back and this cannot pass if one is.
        @Test("exercising every row affordance issues no add at all")
        func rowAffordancesNeverInstall() async {
            let client = DiscoverRecordingClient()
            client.staged = [.success(response([entry(id: "alpha"), entry(id: "beta")]))]
            let board = DiscoverBoardModel(client: client)
            await board.load()

            // Everything a row offers: select it, move through the list, press Return, dismiss.
            board.selection = "alpha"
            board.moveSelection(by: 1)
            board.moveSelection(by: -1)
            #expect(board.commitDefaultAction(), "Return opens the sheet for a selected row")
            board.escape()
            board.escape()

            #expect(client.addedServers.isEmpty, "no row affordance may declare a server")
        }

        @Test("Return opens the detail sheet and is left unhandled when nothing is selected")
        func returnOpensDetailRatherThanInstalling() async {
            let client = DiscoverRecordingClient()
            client.staged = [.success(response([entry(id: "alpha")]))]
            let board = DiscoverBoardModel(client: client)
            await board.load()

            // Unhandled rather than silently swallowed, so the key still means something elsewhere.
            #expect(!board.commitDefaultAction())

            board.selection = "alpha"
            #expect(board.commitDefaultAction())
            #expect(board.sheetEntryID == "alpha")
            #expect(client.addedServers.isEmpty)
        }

        @Test("Escape dismisses the sheet first and clears the selection second, never both")
        func escapeUnwindsOneLayerAtATime() async {
            let client = DiscoverRecordingClient()
            client.staged = [.success(response([entry(id: "alpha")]))]
            let board = DiscoverBoardModel(client: client)
            await board.load()
            board.selection = "alpha"
            _ = board.commitDefaultAction()

            board.escape()
            #expect(board.sheetEntryID == nil)
            #expect(board.selection == "alpha", "the selection survives dismissing the sheet")

            board.escape()
            #expect(board.selection == nil)
        }

        @Test("the selection moves through the visible rows, not the whole response")
        func selectionMovesThroughVisibleRowsOnly() async {
            let client = DiscoverRecordingClient()
            client.staged = [.success(response([
                entry(id: "no-usage"),
                entry(id: "has-usage", useCount: 5)
            ]))]
            let board = DiscoverBoardModel(client: client)
            await board.load()

            // Under `mostUsed` only one row is visible, so movement cannot land on the other.
            board.ordering = .mostUsed
            #expect(board.rows.count == 1)
            board.moveSelection(by: 1)
            #expect(board.selection == "has-usage")
            board.moveSelection(by: 1)
            #expect(board.selection == "has-usage", "movement clamps rather than wrapping off the end")
        }

        /// The return value the view turns into `.handled` / `.ignored`.
        ///
        /// This is the half the model tests could not see: `moveSelection(by:)` returned `Void`, so
        /// the board's `.onKeyPress` returned `.handled` unconditionally and swallowed the arrow
        /// keys on a board with nothing to select — meaning a keyboard user could not scroll a long
        /// registry list, because the scroll view never received the key.
        @Test("an arrow key on a board with nothing to select is left unhandled")
        func arrowKeysAreIgnoredWhenThereIsNothingToMove() async {
            let client = DiscoverRecordingClient()
            client.staged = [.success(response([]))]
            let board = DiscoverBoardModel(client: client)
            await board.load()

            #expect(board.rows.isEmpty)
            #expect(board.moveSelection(by: 1) == false, "nothing to move, so the key is not ours")
            #expect(board.moveSelection(by: -1) == false)
            #expect(board.selection == nil)

            // With rows, it is ours and it says so.
            let populated = DiscoverRecordingClient()
            populated.staged = [.success(response([entry(id: "a"), entry(id: "b")]))]
            let live = DiscoverBoardModel(client: populated)
            await live.load()
            #expect(live.moveSelection(by: 1) == true)
            #expect(live.selection == "a")
        }

        // MARK: - A10 · search behaviour

        /// A fetch per keystroke would issue two third-party HTTP requests per character.
        @Test("a typed burst is one request, not one per keystroke")
        func searchIsDebounced() async throws {
            let client = DiscoverRecordingClient()
            let board = DiscoverBoardModel(client: client)
            await board.load()
            let baseline = client.searchQueries.count

            for text in ["p", "po", "pos", "post", "postg"] {
                board.search = text
                board.queryChanged()
            }
            try await Task.sleep(nanoseconds: DiscoverBoardModel.debounceNanoseconds * 3)

            #expect(
                client.searchQueries.count == baseline + 1,
                "five keystrokes issued \(client.searchQueries.count - baseline) requests"
            )
            #expect(client.searchQueries.last == "postg", "and the request carries the latest text")
        }

        /// Bypassing the debounce without cancelling it issues this request *and* lets the debounce
        /// fire 400 ms later, so two calls go out — a burst-then-Return sequence a keystroke-only
        /// test never exercises.
        @Test("Return searches now and cancels the debounce rather than racing it")
        func submitCancelsThePendingDebounce() async throws {
            let client = DiscoverRecordingClient()
            let board = DiscoverBoardModel(client: client)
            await board.load()
            let baseline = client.searchQueries.count

            board.search = "postgres"
            board.queryChanged()
            board.submitSearch()
            try await Task.sleep(nanoseconds: DiscoverBoardModel.debounceNanoseconds * 3)

            #expect(client.searchQueries.count == baseline + 1)
        }

        /// Blanking on every keystroke is the same defect as throwing away a stale reading.
        @Test("a re-query keeps the rows that are already on screen")
        func aRequeryKeepsItsRows() async throws {
            let client = DiscoverRecordingClient()
            client.staged = [.success(response([entry(id: "alpha")]))]
            let board = DiscoverBoardModel(client: client)
            await board.load()
            #expect(board.rows.map(\.id) == ["alpha"])

            client.searchDelayNanoseconds = 800_000_000
            board.search = "beta"
            board.submitSearch()
            // Mid-flight: the previous reading is still what the board draws.
            try await Task.sleep(nanoseconds: 120_000_000)
            #expect(board.rows.map(\.id) == ["alpha"], "rows stay put while the query is in flight")
        }

        /// A previous good reading is kept and labelled rather than discarded — an empty board is a
        /// stronger claim than a stale one.
        @Test("a failed re-query keeps the last good rows and marks them stale")
        func aFailedRequeryKeepsItsRows() async {
            let client = DiscoverRecordingClient()
            client.staged = [
                .success(response([entry(id: "alpha")])),
                .failure(.routerNotRunning)
            ]
            let board = DiscoverBoardModel(client: client)
            await board.load()
            // A second read, awaited directly rather than fired through `submitSearch` and slept on.
            // `load` and the debounced path share `fetch`, which is where the stale-versus-failed
            // decision lives, so this exercises the same branch — and it does so deterministically.
            // The slept version passed twice and then failed once under fleet load, which is the
            // definition of a test that reports the machine rather than the code.
            await board.load()

            #expect(board.rows.map(\.id) == ["alpha"])
            #expect(board.state.error == .routerNotRunning)
            if case .stale = board.state {} else {
                Issue.record("a live failure over a good reading is stale, not failed")
            }
        }

        @Test("with nothing ever loaded, a failure is failed rather than stale")
        func aColdFailureIsFailed() async {
            let client = DiscoverRecordingClient()
            client.staged = [.failure(.routerNotRunning)]
            let board = DiscoverBoardModel(client: client)
            await board.load()

            if case .failed = board.state {} else {
                Issue.record("nothing loaded, so there is no reading to keep")
            }
            #expect(board.rows.isEmpty)
        }

        // MARK: - Installing

        /// No refetch on purpose: `/registry/search` is non-deterministic between calls, so
        /// re-reading it at the moment the user acted would reorder the board under them.
        @Test("a successful install marks the row in place without re-querying")
        func installMarksTheRowWithoutRefetching() async {
            let client = DiscoverRecordingClient()
            client.staged = [.success(response([entry(id: "alpha"), entry(id: "beta")]))]
            let board = DiscoverBoardModel(client: client)
            await board.load()
            let searchesBefore = client.searchQueries.count
            let target = board.rows[0]

            await board.install(target, values: [:])

            #expect(client.searchQueries.count == searchesBefore, "the board must not reorder under the user")
            #expect(board.rows.first { $0.id == "alpha" }?.installed == true)
            #expect(board.rows.first { $0.id == "beta" }?.installed != true, "only the row acted on changes")
            #expect(board.installState == .idle)
        }

        /// A refusal must leave the row saying what is true, which is that nothing was added.
        @Test("a refused install leaves the row unmarked and states the failure")
        func refusedInstallIsNotOptimistic() async {
            let client = DiscoverRecordingClient()
            client.staged = [.success(response([entry(id: "alpha")]))]
            client.addFailure = .routerNotRunning
            let board = DiscoverBoardModel(client: client)
            await board.load()

            await board.install(board.rows[0], values: [:])

            #expect(board.rows[0].installed != true)
            #expect(board.installState == .failed(.routerNotRunning))
            board.clearInstallFailure()
            #expect(board.installState == .idle)
        }

        @Test("an entry with no install block cannot be declared at all")
        func anEntryWithNoInstallBlockSendsNothing() async {
            let client = DiscoverRecordingClient()
            client.staged = [.success(response([entry(id: "alpha", install: nil)]))]
            let board = DiscoverBoardModel(client: client)
            await board.load()

            await board.install(board.rows[0], values: [:])
            #expect(client.addedServers.isEmpty)
        }

        /// The sheet holds its entry **by id**. A captured copy would keep `installed == false` after
        /// a successful add, so its action would stay live and a second press would send a second
        /// declaration for a server that now exists.
        @Test("the sheet reads the row fresh, so it sees a completed install")
        func theSheetSeesTheInstallItJustDid() async {
            let client = DiscoverRecordingClient()
            client.staged = [.success(response([entry(id: "alpha")]))]
            let board = DiscoverBoardModel(client: client)
            await board.load()
            board.selection = "alpha"
            _ = board.commitDefaultAction()

            await board.install(board.rows[0], values: [:])

            #expect(board.sheetEntry()?.installed == true)
            #expect(
                !RegistryCapability.action(for: board.sheetEntry() ?? board.rows[0]).isEnabled,
                "the action becomes Added and disabled, in place"
            )
        }
    }
#endif
