#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// The clauses an adversarial plan review found unscheduled: the board's own handling of a stale
    /// load, the nine states as a declared mapping rather than a preview's compile check, the control
    /// the board is required *not* to use, and the connection between the menu's availability rule
    /// and the app that actually reads it.
    @Suite("Servers board — the surface's own claims")
    struct ServersBoardSurfaceTests {
        @MainActor
        static func board() -> ServersBoardModel {
            let client = FixtureControlAPIClient(.populated)
            return ServersBoardModel(client: client, tracker: ServerStateTracker(client: client, stream: nil))
        }

        static func server(_ name: String = "s", state: ServerState = .running) throws -> MCPServer {
            var s = try FixtureControlAPIClient.decodeFixture("server-stdio", as: MCPServer.self)
            s.name = name
            s.state = state
            return s
        }

        // MARK: - A9, at the board rather than at the header type

        /// `ServersBoardHeader` having an `Int?` proves the figure *can* be absent. It proves nothing
        /// about whether the board passes `isCurrent: false` when the load is stale, which is the
        /// whole of the clause — so this asserts the board's own decision, in all four load states.
        @MainActor
        @Test("A9 — the board withholds the running count on every load that is not current")
        func boardWithholdsTheRunningCountWhenNotCurrent() throws {
            let board = Self.board()
            let one = try [Self.server()]

            let loaded = ServerStateTracker.TrackerState(load: .loaded(one), stream: .notConfigured)
            #expect(board.header(from: loaded).running == 1)

            let stale = ServerStateTracker.TrackerState(
                load: .stale(one, .routerNotRunning), stream: .notConfigured
            )
            #expect(
                board.header(from: stale).running == nil,
                "the board reported a present-tense count for a router that is not answering"
            )
            // And the figures that are not present-tense survive, so the withholding is targeted
            // rather than the board simply going blank.
            #expect(board.header(from: stale).servers == 1)

            let failed = ServerStateTracker.TrackerState(
                load: .failed(.routerNotRunning), stream: .notConfigured
            )
            #expect(board.header(from: failed).running == nil)

            let loading = ServerStateTracker.TrackerState(load: .loading, stream: .notConfigured)
            #expect(board.header(from: loading).running == nil)
        }

        @MainActor
        @Test("A9 — the stale subtitle names no time, because nothing observes when the poll answered")
        func staleSubtitleClaimsNoPrecision() throws {
            let board = Self.board()
            let stale = try ServerStateTracker.TrackerState(
                load: .stale([Self.server()], .routerNotRunning), stream: .notConfigured
            )
            let subtitle = board.header(from: stale).subtitle()
            #expect(subtitle.hasSuffix("· last reading, not current"))
            #expect(!subtitle.contains("ago"))
            #expect(!subtitle.contains("as of"))
            // The check that actually bites: no elapsed duration anywhere. A substring test for
            // "last read" would fire on this subtitle's own "last reading", which is the wording it
            // is supposed to permit — so the assertion is on the *shape of a time*, which is the
            // thing nothing observes.
            let durationPattern = try Regex(#"\d+\s*(s|m|h|d|mo|sec|min|hour|day)\b"#)
            #expect(
                subtitle.firstMatch(of: durationPattern) == nil,
                "the subtitle names an elapsed time nothing recorded: \(subtitle)"
            )
        }

        // MARK: - The header before anything has answered

        /// The defect this exists to keep out: with a two-case `isCurrent: Bool`, `.loading` fell to
        /// the not-current branch and the cold-start board rendered
        /// `0 tools from 0 servers · last reading, not current`. The zeros were invented and the
        /// sentence asserted a prior reading that had never happened — on screen, before the first
        /// poll returned, on every launch.
        ///
        /// The assertion is on **digits**, not on the wording. A test for the new sentence would
        /// pass if a later edit appended a fabricated count to it, and a fabricated count is the
        /// thing being guarded, not the phrasing.
        @MainActor
        @Test("The header claims nothing at all until a poll has answered")
        func headerClaimsNothingBeforeAnyPollAnswers() throws {
            let board = Self.board()

            for load in [ServerStateTracker.LoadState.loading, .failed(.routerNotRunning)] {
                let state = ServerStateTracker.TrackerState(load: load, stream: .notConfigured)
                let header = board.header(from: state)
                #expect(header.reading == .none, "\(load) has never had a poll answer")

                let subtitle = header.subtitle()
                #expect(
                    subtitle.rangeOfCharacter(from: .decimalDigits) == nil,
                    "the header displayed a figure before anything observed one: \(subtitle)"
                )
                #expect(
                    !subtitle.contains("last reading"),
                    "the header claimed an earlier reading that never happened: \(subtitle)"
                )
            }

            // And the stale wording is still reachable — the fix narrowed which loads may say it,
            // rather than removing the sentence a genuinely-gone-quiet router earns.
            let stale = try ServerStateTracker.TrackerState(
                load: .stale([Self.server()], .routerNotRunning), stream: .notConfigured
            )
            #expect(board.header(from: stale).subtitle().contains("last reading, not current"))
        }

        // MARK: - The reap horizon the router never sent

        /// `rows(from:)` briefly read `state.idleMs ?? 300_000`, defended by a comment arguing the
        /// fallback was unreachable. 300_000 is the prototype's hardcoded horizon, so a tracker that
        /// had servers but no `idleMs` counted a row down against a number nothing sent — the exact
        /// class of fabricated figure `DESIGN.md` §6 forbids.
        ///
        /// This asserts through the **board**, not through `ServerSubtitle`, because the type
        /// accepting `Int?` proves only that the absence is representable; the defect was the board
        /// filling it in.
        @MainActor
        @Test("A6 — an unknown reap horizon drops the countdown rather than inventing 300s")
        func unknownReapHorizonDropsTheCountdown() throws {
            let board = Self.board()
            let running = try [Self.server(state: .running)]

            let unknown = ServerStateTracker.TrackerState(
                load: .loaded(running), stream: .notConfigured, idleMs: nil
            )
            let subtitle = try #require(board.rows(from: unknown).first).subtitle.text
            #expect(subtitle == "running")
            #expect(!subtitle.contains("300"), "the board counted down to the prototype's horizon")
            #expect(!subtitle.contains("reaps in"))

            // Given the horizon, the countdown returns — the absence is targeted, not a regression
            // that silenced the figure everywhere.
            let known = ServerStateTracker.TrackerState(
                load: .loaded(running), stream: .notConfigured, idleMs: 300_000
            )
            let withHorizon = try #require(board.rows(from: known).first).subtitle.text
            #expect(withHorizon.hasPrefix("reaps in"))
        }

        // MARK: - A19, as a declared mapping

        @Test("A19 — every one of the nine states names where it is rendered on this board")
        func everyStateHasANamedTreatment() {
            for state in SurfaceState.allCases {
                let treatment = ServersBoardStates.treatment(for: state)
                #expect(!treatment.isEmpty, "\(state.rawValue) has no treatment on this board")
            }
            // Nine distinct answers: the states are not alternatives, and a mapping that folded two
            // of them onto one rendering would be the populated-only failure in disguise.
            let treatments = SurfaceState.allCases.map { ServersBoardStates.treatment(for: $0) }
            #expect(Set(treatments).count == SurfaceState.allCases.count)
            #expect(SurfaceState.allCases.count == 9)
        }

        // MARK: - A29's second half, and A23's, which are source-level claims

        /// The board renders the **indicator**, not `BreakerToggle`.
        ///
        /// `BreakerToggle`'s accessibility hint says it "toggles the server between dormant and
        /// running", and there is no start operation and no stop operation on `ControlAPIClient` —
        /// so using it here would be shipping a control that claims something the API cannot do.
        @Test("A29 — the board draws Breaker and never BreakerToggle")
        func theBoardDrawsTheIndicatorNotAToggle() throws {
            var sawBreaker = false
            for file in ShellTestSupport.boardFiles {
                let source = try ShellTestSupport.repoFile(file)
                #expect(
                    !source.contains("BreakerToggle("),
                    "\(file) uses a control that offers an operation the control API does not have"
                )
                if source.contains("Breaker(state:") { sawBreaker = true }
            }
            // A negative assertion alone would also pass on a board that drew no breaker at all.
            #expect(sawBreaker, "no board file draws a breaker, so the negative assertion proves nothing")
        }

        /// A23's two halves that a value can carry: the row keeps the whole name, and the row's
        /// height is read from the documented token rather than written as a number.
        @Test("A23 — a long name is kept whole in the model and the row height comes from the token")
        func overflowKeepsTheNameAndTheHeight() throws {
            let long = ServersBoardCopy.longServerName
            #expect(long.count > 60, "the overflow fixture is not long enough to truncate anything")

            let row = try ServerRowModel(
                server: Self.server(long), idleMs: 300_000, pendingAuth: nil
            )
            // Truncation is the view's, never the data's — the inspector and the accessibility label
            // both need the whole value, and a model that shortened it would lose it for good.
            #expect(row.name == long)
            #expect(row.id == long)

            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Boards/ServersBoardRow.swift"
            )
            #expect(source.contains("MetricToken.serversRow.leadingScalar"))
            #expect(source.contains("lineLimit(1)"))
            #expect(source.contains("accessibilityLabel(row.name)"))
        }

        // MARK: - The menu rule, reconnected to the app that reads it

        /// **Why this exists.** `MenuCommand.availability` keeps M1's meaning so `spec-M1.md`'s
        /// inventory table and its test pass unedited — which is correct, and which also means that
        /// test now certifies a default value the shipping app never uses. A drift guard that cannot
        /// see the drift is a decoration (`SWIFT_PRACTICES.md` §7).
        ///
        /// So the guard is reconnected here, at the value the running app actually passes: the
        /// context `ShellModel` builds. A28 measured the same thing from the running menu bar.
        @MainActor
        @Test("the context the app really passes is the one that enables the board's commands")
        func theShippingContextEnablesTheBoardsCommands() throws {
            let model = try ShellTestSupport.model(.populated)
            let context = model.menuContext

            #expect(context.installedDestinations == BoardRegistry.installed)
            #expect(context.installedDestinations.contains(.servers))
            #expect(context.selectedServerIsTripped == nil, "nothing is selected on a fresh window")

            #expect(MenuCommand.addServer.availability(in: context) == .enabled)
            #expect(MenuCommand.find.availability(in: context) == .enabled)
            #expect(MenuCommand.resetServer.availability(in: context) == .needsServerSelection)
            #expect(MenuCommand.removeServer.availability(in: context) == .needsServerSelection)

            // And the parameterless form is now demonstrably *not* what the app reads, which is the
            // fact that made the older test a decoration.
            #expect(MenuCommand.addServer.availability != MenuCommand.addServer.availability(in: context))
        }

        @MainActor
        @Test("selecting a server moves the two commands that act on one")
        func selectionMovesTheServerCommands() throws {
            let model = try ShellTestSupport.model(.populated)
            model.serversBoard.selection = "nothing-by-this-name"
            // A selection naming a server the poll never listed is not a selection: the context
            // reports nil rather than inventing a tripped-ness for a row that does not exist.
            #expect(model.menuContext.selectedServerIsTripped == nil)
        }
    }
#endif
