#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// The shell's state and its readout, held to `DESIGN.md` and to the control client's own words.
    ///
    /// What this suite can and cannot see is worth stating, because the alternative is a suite that
    /// looks like it measures rendering and does not. SwiftUI's view tree is opaque to a SwiftPM
    /// test: nothing here can read a rendered inset, a badge's displacement or a focus ring's width.
    /// So every clause with a rendered half is split — the decision is asserted here, where it is a
    /// value, and the render is measured in `scripts/acceptance/mac-shell.sh` off the running app's
    /// accessibility tree. A claim that a rendered geometry was measured from this file would be
    /// false, and none is made.
    @Suite("Mac shell")
    struct ShellTests {
        // MARK: - A34 · the scroll edge

        /// The threshold is driven from both sides, and from a **non-zero** resting offset — which
        /// is the case `offset > 0` gets wrong and the reason this is a state machine rather than a
        /// comparison. A scroll view with content insets rests below zero, and rubber-banding puts
        /// it either side of its resting point without the content having moved.
        @Test("the separator is absent at the resting offset and present above it")
        func scrollEdgeThreshold() {
            for resting in [0.0, -22.0, 13.5] {
                var state = ScrollEdgeState()
                // The very first callback is already a movement: `onScrollGeometryChange` fires on a
                // change, never on the resting value, so this is the shape every real reading has.
                state.observe(previous: resting, offset: resting + ScrollEdgeState.threshold)
                #expect(state.baseline == resting)
                #expect(!state.isSeparatorVisible, "fired at the threshold rather than above it")

                state.observe(previous: resting, offset: resting + ScrollEdgeState.threshold + 0.01)
                #expect(state.isSeparatorVisible, "did not appear once scrolled past the threshold")

                state.observe(previous: resting + 40, offset: resting)
                #expect(!state.isSeparatorVisible, "did not clear on the way back to the top")
            }
        }

        /// The defect this signature exists to prevent, asserted as itself.
        ///
        /// Measured on a fresh launch on 2026-08-14: the separator stayed hidden through 40 points of
        /// scrolling, because the baseline had been taken from the first reading *received* — which
        /// is where the first gesture ended — rather than from the offset it started at. A user
        /// scrolling for the first time saw no separator at all.
        @Test("the first movement is measured from where it started, not from where it landed")
        func theFirstMovementShowsTheSeparator() {
            var state = ScrollEdgeState()
            // One callback, resting at 0, landing 120 points down. That must show the separator.
            state.observe(previous: 0, offset: 120)
            #expect(state.baseline == 0)
            #expect(
                state.isSeparatorVisible,
                "the first scroll left the separator hidden — the baseline followed the gesture"
            )
        }

        @Test("rubber-banding above the resting point never shows the separator")
        func rubberBandingDoesNotFire() {
            var state = ScrollEdgeState()
            state.observe(previous: 0, offset: -40)
            #expect(!state.isSeparatorVisible)
        }

        /// A new destination brings its own insets, so a carried-over baseline would compare one
        /// view's offset to another view's resting position.
        @Test("changing destination re-measures the baseline rather than carrying the old one")
        func resetForgetsTheBaseline() {
            var state = ScrollEdgeState()
            state.observe(previous: 0, offset: 200)
            #expect(state.isSeparatorVisible)

            state.reset()
            #expect(state.baseline == nil)
            #expect(!state.isSeparatorVisible)

            state.observe(previous: -18, offset: -18.5)
            #expect(state.baseline == -18)
            #expect(!state.isSeparatorVisible)
        }

        @MainActor
        @Test("selecting a different destination resets the shell's scroll edge")
        func selectionResetsScrollEdge() throws {
            let model = try ShellTestSupport.model(.populated)
            model.observeScroll(previous: 0, offset: 300)
            #expect(model.scrollEdge.isSeparatorVisible)

            model.select(.servers)
            #expect(!model.scrollEdge.isSeparatorVisible)
        }

        // MARK: - A18, A26, A37 · every state, driven by a named scenario

        /// Nine scenarios, each asserting a **specific observable** rather than that something
        /// rendered. All of them run with no router on the machine, which is A37.
        ///
        /// The per-scenario assertions are three helpers rather than one switch, because one switch
        /// over nine cases is a function nobody can read and a complexity gate rightly rejects.
        @MainActor
        @Test(
            "each fixture scenario puts the shell in its own state",
            arguments: [
                FixtureControlAPIClient.Scenario.populated,
                .empty, .partial, .error, .success, .offline, .unauthorized, .overflow, .disabled
            ]
        )
        func everyScenarioHasItsOwnObservable(scenario: FixtureControlAPIClient.Scenario) async throws {
            let model = try ShellTestSupport.model(scenario)
            await model.refresh(at: Date(timeIntervalSince1970: 1_000_000))

            switch scenario {
            case .offline, .unauthorized, .error:
                try assertFailure(scenario, on: model)
            case .empty, .partial, .overflow, .disabled:
                try assertShape(scenario, on: model)
            case .populated:
                assertPopulated(scenario, on: model)
            case .success:
                // `.success` shared `.populated`'s assertions exactly, which a completeness critic
                // pointed out means it was distinguished by nothing — two names, one check.
                //
                // The honest answer is that the *shell* cannot tell them apart, and saying so is
                // better than inventing a difference: `.success` is a write that succeeded, and M1
                // ships no write surface. So the readout is asserted to be the populated one, and
                // the scenario's own observable is exercised where it actually exists — a reindex
                // that comes back with no error and a tool count, which under `.populated` fails.
                assertPopulated(scenario, on: model)
                let result = try await model.client.reindex("anything")
                #expect(result.error == nil, "the success scenario returned a failed write")
                #expect(result.tools != nil, "the success scenario reported no tool count")
            default:
                Issue.record("\(scenario) has no assertion")
            }
        }

        /// The three conditions the router can report that are not a reading: each keeps its own
        /// identity rather than collapsing into "something went wrong".
        @MainActor
        private func assertFailure(
            _ scenario: FixtureControlAPIClient.Scenario,
            on model: ShellModel
        ) throws {
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
            default:
                guard case let .failed(error) = model.readout.state else {
                    Issue.record("the error scenario did not fail the readout")
                    return
                }
                // The router's own status and hint survive to the surface.
                #expect(error.headline == ControlAPIError.server(status: 422, message: "").headline)
            }
        }

        /// The four readings whose shape is the point rather than the number.
        @MainActor
        private func assertShape(
            _ scenario: FixtureControlAPIClient.Scenario,
            on model: ShellModel
        ) throws {
            switch scenario {
            case .empty:
                #expect(model.readout.state == .empty)
                #expect(model.readout.declared == 0)
            case .partial:
                guard case let .partial(_, _, notIndexed) = model.readout.state else {
                    Issue.record("the partial scenario did not report anything unindexed")
                    return
                }
                #expect(notIndexed > 0)
            case .overflow:
                let names = try #require(model.servers).map(\.name)
                #expect(names.contains { $0.count > 40 }, "the overflow scenario carried no long name")
            default:
                let servers = try #require(model.servers)
                #expect(servers.contains { $0.placard != nil }, "no placarded server to dim")
            }
        }

        @MainActor
        private func assertPopulated(
            _ scenario: FixtureControlAPIClient.Scenario,
            on model: ShellModel
        ) {
            #expect(model.readout.hasCounts)
            guard case let .populated(running, declared) = model.readout.state else {
                Issue.record("\(scenario) did not populate")
                return
            }
            #expect(declared > 0)
            #expect(running <= declared, "more servers running than declared is not observable")
        }

        /// The loading state is the *absence* of an answer, so it is asserted by not answering
        /// rather than by a flag. A `refresh` against the loading scenario never returns, which is
        /// why this races it against a deadline instead of awaiting it.
        @MainActor
        @Test("a shell with no answer yet is loading, not empty")
        func loadingIsTheAbsenceOfAnAnswer() async throws {
            let model = try ShellTestSupport.model(.loading)
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
            let model = try ShellTestSupport.model(scenario)
            await model.refresh(at: Date(timeIntervalSince1970: 1_000_000))

            guard case let .failed(rendered) = model.readout.state else {
                Issue.record("\(scenario) did not fail")
                return
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

            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/Readout.swift")
            #expect(!source.contains("actionLabel"), "the readout reached for an action it cannot perform")
            #expect(!source.contains("Button("), "the readout shipped a control with nothing behind it")
        }

        // MARK: - A29 · the skeleton is the readout's own geometry

        @Test("the loading skeleton and the populated readout are one height")
        func skeletonMatchesPopulatedGeometry() throws {
            // Both forms are held to the same constant, which is the only way the sidebar does not
            // move when the first poll lands. Composed from tokens, so it follows `DESIGN.md`.
            #expect(ReadoutGeometry.height > 0)
            // The padding term became `cardPadding` when M27 put the readout inside the card the
            // design of record draws. The clause is that the two forms are one constant composed
            // from tokens — not that the constant never changes — so the formula is restated here
            // rather than the assertion loosened.
            #expect(
                ReadoutGeometry.height
                    == MetricToken.tableRows.leadingScalar * 2
                    + ReadoutGeometry.traceHeight
                    + ReadoutGeometry.spacing * 2
                    + ReadoutGeometry.cardPadding * 2
            )
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/Sidebar.swift")
            #expect(
                source.contains("ReadoutGeometry.height"),
                "the sidebar stopped holding the readout to its declared height"
            )
        }

        @Test("the loading state is a skeleton rather than a spinner")
        func loadingIsNeverASpinner() throws {
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterUI/Shell/Readout.swift")
            #expect(!source.contains("ProgressView"), "§5 forbids a spinner over a blank pane")
        }

        // MARK: - A15 · no number the router does not observe

        @Test("the readout's copy carries no figure beyond the counts and the trace")
        func copyCarriesNoFabricatedMetric() {
            let strings = [
                ReadoutCopy.childProcessesLabel,
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
    }
#endif
