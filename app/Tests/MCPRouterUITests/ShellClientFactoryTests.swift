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
            let shipping = ShellClientFactory.Choice.live(ShellClientFactory.shippingEndpoint)
            #expect(ShellClientFactory.choice(isDebugBuild: false, environment: [:]) == shipping)
            // Every scenario name, tried against a Release build. If any one of them could talk a
            // shipped build into a fixture, that build could display invented numbers.
            for scenario in FixtureControlAPIClient.Scenario.allCases {
                let environment = [ShellClientFactory.scenarioVariable: scenario.rawValue]
                #expect(
                    ShellClientFactory.choice(isDebugBuild: false, environment: environment) == shipping,
                    "a Release build was talked into the \(scenario.rawValue) fixture"
                )
            }
        }

        /// The other half of the Release rule, and it did not exist before J5 gave the factory an
        /// endpoint to choose. A shipped build that could be pointed at a foreign router by an
        /// environment variable displays whatever that router says, under this product's name — a
        /// worse version of the fabricated-figure defect the suite above exists for, because the
        /// figures would be real and about something else.
        @Test("a Release build ignores the endpoint variable as well as the scenario")
        func releaseIgnoresTheEndpoint() {
            let shipping = ShellClientFactory.Choice.live(ShellClientFactory.shippingEndpoint)
            for raw in ["http://127.0.0.1:8973", "http://example.com", "http://localhost:1", "nonsense"] {
                let environment = [
                    ShellClientFactory.scenarioVariable: ShellClientFactory.liveScenarioName,
                    ShellClientFactory.endpointVariable: raw
                ]
                #expect(
                    ShellClientFactory.choice(isDebugBuild: false, environment: environment) == shipping,
                    "a Release build was pointed at \(raw)"
                )
            }
        }

        /// The capability J5 exists to buy: a Debug build that can be told to read the REAL router,
        /// at a router the caller started.
        ///
        /// Without this every board photographed by the acceptance lane is a photograph of
        /// `FixtureControlAPIClient`, which is this project's own account of itself — so `REQ-004`
        /// (the board reflects live server states), `REQ-005` (counts go absent when the router
        /// stops) and `REQ-007` (no unobserved figure is displayed) had no observation lane at all.
        @Test("a Debug build can be told to read the real router at a chosen loopback endpoint")
        func debugCanChooseLive() {
            let chosen = URL(string: "http://127.0.0.1:8973")
            #expect(chosen != nil)
            let environment = [
                ShellClientFactory.scenarioVariable: ShellClientFactory.liveScenarioName,
                ShellClientFactory.endpointVariable: "http://127.0.0.1:8973"
            ]
            #expect(ShellClientFactory.choice(isDebugBuild: true, environment: environment)
                == .live(chosen ?? ShellClientFactory.shippingEndpoint))
        }

        @Test("live with no endpoint named is the shipping endpoint")
        func liveDefaultsToShipping() {
            let environment = [ShellClientFactory.scenarioVariable: ShellClientFactory.liveScenarioName]
            #expect(ShellClientFactory.choice(isDebugBuild: true, environment: environment)
                == .live(ShellClientFactory.shippingEndpoint))
        }

        /// Loopback only, because the standing constraint is that this app talks to the router over
        /// loopback and nothing else. A Debug affordance that could name any host would be an
        /// exfiltration route wearing a test harness's clothes.
        ///
        /// Each rejected form is listed rather than sampled: the discriminator is the FALLBACK, so a
        /// case that quietly passed would be indistinguishable from one that was never tried.
        @Test("a Debug build refuses an endpoint that is not http over loopback")
        func debugRefusesForeignEndpoints() {
            let refused = [
                "http://example.com:8879", // not loopback
                "https://127.0.0.1:8879", // not http
                "http://127.0.0.2:8879", // loopback-ish, and not one of the three literals
                "http://[::2]:8879", // ditto, IPv6
                "file:///tmp/servers.json", // not a network scheme at all
                "127.0.0.1:8879", // no scheme: URL(string:) parses this as a path
                ""
            ]
            for raw in refused {
                let environment = [
                    ShellClientFactory.scenarioVariable: ShellClientFactory.liveScenarioName,
                    ShellClientFactory.endpointVariable: raw
                ]
                #expect(
                    ShellClientFactory.choice(isDebugBuild: true, environment: environment)
                        == .live(ShellClientFactory.shippingEndpoint),
                    "a Debug build honoured \(raw)"
                )
            }
        }

        @Test("the three loopback spellings are all honoured")
        func loopbackSpellings() {
            for raw in ["http://127.0.0.1:8973", "http://localhost:8973", "http://[::1]:8973"] {
                let environment = [
                    ShellClientFactory.scenarioVariable: ShellClientFactory.liveScenarioName,
                    ShellClientFactory.endpointVariable: raw
                ]
                let choice = ShellClientFactory.choice(isDebugBuild: true, environment: environment)
                #expect(choice != .live(ShellClientFactory.shippingEndpoint), "\(raw) was refused")
                #expect(choice != .fixture(.populated), "\(raw) fell through to a fixture")
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
                    ShellClientFactory
                        .choice(isDebugBuild: true, environment: environment) == .fixture(scenario)
                )
            }
        }

        @Test("an unrecognised scenario name falls back rather than crashing")
        func unknownNamesFallBack() {
            let environment = [ShellClientFactory.scenarioVariable: "not-a-scenario"]
            #expect(ShellClientFactory
                .choice(isDebugBuild: true, environment: environment) == .fixture(.populated))
        }

        /// The reserved name has to stay reserved, and this is the assertion that keeps it so.
        ///
        /// If a `Scenario` case were ever added with the raw value `live`, the branch above would
        /// stop being reachable and `MCPROUTER_SCENARIO=live` would quietly render a fixture again —
        /// which is precisely the failure that left three requirements standing on the project's own
        /// word, and it would return without a single line of this file changing.
        @Test("the live name is not also a fixture scenario")
        func liveNameIsReserved() {
            let names = FixtureControlAPIClient.Scenario.allCases.map(\.rawValue)
            #expect(!names.contains(ShellClientFactory.liveScenarioName))
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
