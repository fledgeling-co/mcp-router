#if os(macOS)
    import Foundation
    import Testing
    @testable import MCPRouterKit
    @testable import MCPRouterUI

    /// The board's honesty guards: every figure and every sentence that reached the user without
    /// having been observed.
    ///
    /// Split from `ServersBoardSurfaceTests` when that file crossed the 400-line limit, and split
    /// along a real seam — these are not assertions about *what the board shows* but about **what it
    /// is allowed to claim**, which is this product's governing rule (`DESIGN.md` §6: no number is
    /// displayed that the router does not observe).
    ///
    /// Six defects of this class were found and closed. Four were caught by an adversarial review
    /// after the first three were already fixed, which is the argument for keeping them together and
    /// for keeping every one of them mutation-proven:
    ///
    /// 1. `state.idleMs ?? 300_000` — a countdown to the prototype's hardcoded horizon.
    /// 2. `0 tools from 0 servers · last reading, not current` — on every cold start.
    /// 3. `Authorised Never.` — under a heading reading `Signed in`.
    /// 4. `Running 1` in the filter bar on a stale load — thirty points below a header refusing it.
    /// 5. `No server has a child process up right now` — from a router that stopped answering.
    /// 6. `Its N tools leave every session's tool list` — for a server that is scoped.
    @Suite("Servers board — what it is allowed to claim")
    struct ServersBoardHonestyTests {
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

        // MARK: - The timestamp the router sent but nothing could read

        /// The third figure of the same class, found by sweeping the board for values that reach a
        /// string without having been observed. `relative()` answers `Never` for a string that will
        /// not parse, which is correct at the three call sites passing an **optional** — `Indexed`,
        /// `First seen`, `Last used` all mean it literally — and wrong at the one where the value is
        /// already non-nil, where it rendered `Authorised Never.` under a heading reading `Signed in`.
        ///
        /// `auth.authorized` is observed and is the branch this sits inside, so the server *is*
        /// signed in; only the *when* is unreadable. The fix drops the figure and keeps the fact.
        @MainActor
        @Test("An unreadable authorisation timestamp drops the time rather than saying 'Never'")
        func unreadableAuthorisationTimestampDropsTheTime() {
            let honest = "Credentials are stored for this server."

            // Absent, and unparseable, must reach the same sentence — the router said nothing usable
            // in both cases, and the user is owed the same truth.
            #expect(ServerInspector.signedInDetail(nil) == honest)
            for unreadable in ["", "not-a-date", "0000", "yesterday"] {
                let detail = ServerInspector.signedInDetail(unreadable)
                #expect(detail == honest, "'\(unreadable)' produced: \(detail)")
                #expect(
                    !detail.contains("Never"),
                    "a server that IS signed in was told its credentials were never authorised"
                )
            }

            // A timestamp that does parse still reports when — the fallback is targeted, not a
            // regression that silenced the figure everywhere.
            let real = ServerInspector.signedInDetail("2026-08-14T10:00:00.000Z")
            #expect(real.hasPrefix("Authorised "))
            #expect(!real.contains("Never"))
        }

        // MARK: - The filter bar, which was making the claim the header refuses to

        /// **The fourth fabricated figure, and the one that made the board contradict itself.**
        /// `controls` is rendered inside `populated(staleError:)`, which serves `.stale` as well as
        /// `.loaded`, and `counts(from:)` had no currency gate — so a router that had gone quiet
        /// showed `Running 1` roughly thirty points below a header deliberately withholding exactly
        /// that figure.
        ///
        /// The assertion is that the two **agree**, not merely that each is individually plausible.
        /// A test on the filter bar alone would still pass a board whose header and segments told
        /// different stories, which is the defect.
        @MainActor
        @Test("A9 — the filter bar withholds the live counts on the same loads the header does")
        func filterBarAndHeaderAgreeAboutWhatMayBeClaimed() throws {
            let board = Self.board()
            let servers = try [
                Self.server("a", state: .running),
                Self.server("b", state: .idle)
            ]

            let loaded = ServerStateTracker.TrackerState(load: .loaded(servers), stream: .notConfigured)
            let live = board.counts(from: loaded)
            #expect(live[.all] == 2)
            #expect(live[.running] == 1)
            #expect(live[.idle] == 1)
            #expect(board.header(from: loaded).running == 1)

            for load in [
                ServerStateTracker.LoadState.stale(servers, .routerNotRunning),
                .loading,
                .failed(.routerNotRunning)
            ] {
                let state = ServerStateTracker.TrackerState(load: load, stream: .notConfigured)
                let counts = board.counts(from: state)

                // The header's rule, applied to the segments.
                #expect(
                    board.header(from: state).running == nil,
                    "the header should already withhold this — \(load)"
                )
                #expect(
                    counts[.running] == nil,
                    "the filter bar claimed a live process count the header refused to: \(load)"
                )
                #expect(counts[.idle] == nil, "'idle' is equally a claim about now: \(load)")

                // Withheld means ABSENT, never zero. A zero would render as `Running 0`, which is a
                // fabricated figure rather than a missing one.
                #expect(counts[.running] ?? -1 != 0)

                // And the counts that are not present-tense survive, so this is targeted rather
                // than the bar going blank — the same split the header makes.
                #expect(counts[.all] == board.header(from: state).servers)
            }
        }

        /// The empty-in-filter copy is reachable from the stale branch, and every sentence in it was
        /// in the present tense — `"No server has a child process up right now"`, `"Everything is
        /// running"`. The `.idle` line was the worst: an observed count attached to a present-tense
        /// verb, which is §6's defect in its literal form.
        @MainActor
        @Test("§6 — the empty-filter copy makes no present-tense claim from a stale reading")
        func emptyFilterCopyClaimsNothingWhenTheReadingIsStale() {
            for filter in ServerFilter.allCases {
                let stale = filter.emptyMessage(totalServers: 4, reading: .stale)
                let text = "\(stale.title) \(stale.detail)"
                for banned in ["right now", "Everything is running", "have a child process up"] {
                    #expect(
                        !text.contains(banned),
                        "\(filter) asserts '\(banned)' from a reading that has stopped answering"
                    )
                }
                // It says what IS known: that this is the last reading and is not current.
                #expect(text.contains("last"))

                // The current wording is untouched — the fix narrowed which loads may speak these
                // sentences rather than deleting the real copy §5 asks for.
                let current = filter.emptyMessage(totalServers: 4, reading: .current)
                #expect(current.title != stale.title)
                #expect(!current.title.isEmpty, "\(filter) lost its populated-reading copy")
            }
            #expect(ServerFilter.running.emptyMessage(totalServers: 4).detail.contains("right now"))
        }

        // MARK: - Controls that would fail

        /// `Reset` on a row and `Sign in…` in the inspector were gated on `isWriting` alone, so on a
        /// stale load they stayed live one column from a Behaviour toggle dimming with
        /// `cannotWriteReason` for that same condition. Both are writes to a router that is not
        /// answering.
        @MainActor
        @Test("§3.4 — every write control is gated by the same rule, and none is silently dimmed")
        func writeControlsShareOneGateAndAlwaysGiveAReason() throws {
            let board = Self.board()
            let servers = try [Self.server("a", state: .running)]

            let loaded = ServerStateTracker.TrackerState(load: .loaded(servers), stream: .notConfigured)
            #expect(board.canWrite(to: loaded))

            for load in [
                ServerStateTracker.LoadState.stale(servers, .routerNotRunning),
                .loading,
                .failed(.routerNotRunning)
            ] {
                let state = ServerStateTracker.TrackerState(load: load, stream: .notConfigured)
                #expect(
                    !board.canWrite(to: state),
                    "a router that is not answering cannot be written to: \(load)"
                )
            }

            // The reason a dimmed control carries is a real sentence, not an empty string — a
            // control dimmed with "" is dimmed with nothing said, which is the §3.4 defect.
            for reason in [
                ServersBoardModel.cannotWriteReason,
                ServersBoardModel.applyingReason,
                ServersBoardModel.resetDisabledReason
            ] {
                #expect(!reason.isEmpty)
                #expect(reason.count > 3)
            }
        }

        // MARK: - The claim the footer was corrected for, still being made by the dialog

        @MainActor
        @Test("§6 — the removal dialog does not tell a scoped server's owner it was in every session")
        func removalDialogDoesNotOverstateAScopedServer() {
            let scoped = ServersBoardModel.removeToolsConsequence(tools: 3, isScoped: true)
            #expect(
                !scoped.contains("every session"),
                "a scoped server was never in every session's list: \(scoped)"
            )
            #expect(scoped.contains("scoped"))

            // Unscoped is genuinely visible everywhere, so that sentence stays true and stays said.
            let unscoped = ServersBoardModel.removeToolsConsequence(tools: 3, isScoped: false)
            #expect(unscoped.contains("every session's tool list"))

            // Both agree with the count they were given, and neither invents one.
            #expect(scoped.contains("3") && unscoped.contains("3"))
            #expect(ServersBoardModel.removeToolsConsequence(tools: 1, isScoped: false).contains("1 tool "))
        }
    }
#endif
