#if os(macOS)
    import Foundation
    import MCPRouterKit

    /// Which control client the shell talks to, and the one rule that must never bend.
    ///
    /// **A Release build may never render a fixture.** `DESIGN.md` §6 and the product's standing
    /// constraint are the same sentence — no number is displayed that the router does not observe —
    /// and a shell wired to `FixtureControlAPIClient` states "3 of 5 running" in the present tense,
    /// from a JSON file, on a machine with no router at all. That is a fabricated figure however
    /// temporary the wiring was meant to be, and a comment saying so is not a control.
    ///
    /// So the choice is made here, where a test can drive both branches, and the Release branch takes
    /// no input: the environment cannot talk a shipped build into a fixture. What a Release build
    /// shows without a control token is the *unauthorised* state — which is true, is one of
    /// `DESIGN.md` §5's designed states, and is what M8's pairing flow will resolve.
    ///
    /// **The Debug branch takes a scenario from the environment**, which is what makes the running
    /// app reachable in more than one state. Before this existed the app was hardwired to
    /// `.populated`, so every clause whose evidence names the *running app* in a failure or overflow
    /// state — A14's four-digit badge, A28's offline and unauthorised copy — had no lane at all, and
    /// the acceptance gate could not have proven them however long it ran.
    public enum ShellClientFactory {
        /// The variable the acceptance gate sets to choose a state. Debug builds only.
        public static let scenarioVariable = "MCPROUTER_SCENARIO"

        public enum Choice: Equatable, Sendable {
            /// The real loopback control API. What ships.
            case live
            /// A named fixture. Debug only, and only ever chosen deliberately.
            case fixture(FixtureControlAPIClient.Scenario)
        }

        /// The decision, with the build configuration passed in rather than read, so a test can
        /// assert the Release branch from a Debug test run — which is the only way the rule above is
        /// checkable at all.
        public static func choice(isDebugBuild: Bool, environment: [String: String]) -> Choice {
            guard isDebugBuild else {
                // Deliberately ignores the environment. A Release build that could be talked into a
                // fixture by an env var is a Release build that can display invented numbers.
                return .live
            }
            guard let named = environment[scenarioVariable],
                  let scenario = FixtureControlAPIClient.Scenario(rawValue: named)
            else {
                return .fixture(.populated)
            }
            return .fixture(scenario)
        }

        /// The choice this build and this process actually make.
        public static func currentChoice(
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> Choice {
            #if DEBUG
                choice(isDebugBuild: true, environment: environment)
            #else
                choice(isDebugBuild: false, environment: environment)
            #endif
        }

        public static func makeClient(
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> any ControlAPIClient {
            switch currentChoice(environment: environment) {
            case .live: LiveControlAPIClient()
            case let .fixture(scenario): FixtureControlAPIClient(scenario)
            }
        }
    }
#endif
