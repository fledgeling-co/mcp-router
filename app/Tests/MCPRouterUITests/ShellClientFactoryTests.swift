#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// The rule that a Release build can never render a fixture, and the switch that makes the
    /// running app reachable in more than one state.
    ///
    /// This suite exists because of a specific finding: the shell shipped wired to
    /// `FixtureControlAPIClient(.populated)`, so a built app on a machine with no router stated
    /// "N of M running" in the present tense, from a bundled JSON file. `DESIGN.md` §6 and the
    /// product's standing constraint both forbid displaying a number the router did not observe, and
    /// A18's reasoning condemns an invented non-zero more strongly than the zero it names.
    @Suite("Shell control-client selection")
    struct ShellClientFactoryTests {
        @Test("a Release build is live, and the environment cannot change that")
        func releaseIsAlwaysLive() {
            #expect(ShellClientFactory.choice(isDebugBuild: false, environment: [:]) == .live)
            // Every scenario name, tried against a Release build. If any one of them could talk a
            // shipped build into a fixture, that build could display invented numbers.
            for scenario in FixtureControlAPIClient.Scenario.allCases {
                let environment = [ShellClientFactory.scenarioVariable: scenario.rawValue]
                #expect(
                    ShellClientFactory.choice(isDebugBuild: false, environment: environment) == .live,
                    "a Release build was talked into the \(scenario.rawValue) fixture"
                )
            }
        }

        @Test("a Debug build with nothing set is the populated fixture")
        func debugDefaultsToPopulated() {
            #expect(ShellClientFactory.choice(isDebugBuild: true, environment: [:]) == .fixture(.populated))
        }

        @Test("every fixture scenario is reachable through the variable")
        func everyScenarioIsReachable() {
            // Not a sample: a scenario that cannot be selected is a state the acceptance gate can
            // never drive the running app into, which is exactly the gap this switch closes.
            for scenario in FixtureControlAPIClient.Scenario.allCases {
                let environment = [ShellClientFactory.scenarioVariable: scenario.rawValue]
                #expect(
                    ShellClientFactory.choice(isDebugBuild: true, environment: environment) == .fixture(scenario)
                )
            }
        }

        @Test("an unrecognised scenario name falls back rather than crashing")
        func unknownNamesFallBack() {
            let environment = [ShellClientFactory.scenarioVariable: "not-a-scenario"]
            #expect(ShellClientFactory.choice(isDebugBuild: true, environment: environment) == .fixture(.populated))
        }

        /// The assembly layer must not name a client, for the same reason it must not name an
        /// operation: nothing in `app/MCPRouter` can be reached by a test, so a decision written
        /// there has no evidence lane. A grep, because a wiring that compiles is not a wiring that
        /// was decided.
        @Test("the app's Scene names no client of its own")
        func assemblyNamesNoClient() throws {
            let source = try ShellTestSupport.repoFile("app/MCPRouter/MCPRouterApp.swift")
            #expect(!source.contains("FixtureControlAPIClient("))
            #expect(!source.contains("LiveControlAPIClient("))
            #expect(source.contains("ShellClientFactory.makeClient"))
        }
    }
#endif
