#if os(macOS)
    import Foundation
    import MCPRouterKit

    /// Ordinary builds read the token-gated router inbox and observed pairing endpoint.
    /// Explicit Debug scenarios retain the authored fixtures used by the surface state matrix.
    public enum ShellPairingFactory {
        /// The variable the acceptance gate sets to choose a state. Debug builds only.
        public static let scenarioVariable = "MCPROUTER_PAIRING"

        public enum Choice: Equatable, Sendable {
            /// No transport. What ships, and what a build with no listener honestly has.
            case noTransport
            /// A named fixture. Debug only, and only ever chosen deliberately.
            case fixture(FixtureInboxService.Scenario)
        }

        /// The decision, with the build configuration passed in rather than read, so a test can
        /// assert the Release branch from a Debug test run — the only way this rule is checkable at
        /// all.
        public static func choice(isDebugBuild: Bool, environment: [String: String]) -> Choice {
            guard isDebugBuild else {
                // Deliberately ignores the environment, including every named scenario. A Release
                // build that could be talked into a fixture is a Release build that can draw a QR
                // for an endpoint nothing is listening on.
                return .noTransport
            }
            guard let named = environment[scenarioVariable],
                  let scenario = FixtureInboxService.Scenario(rawValue: named)
            else {
                // The unset default is `.none`, not `.paired`: a developer who has set nothing
                // should see what ships, not the richest fixture. An unrecognised name lands here
                // too, so a typo shows the honest state rather than silently selecting another.
                return .fixture(.none)
            }
            return .fixture(scenario)
        }

        public static func currentChoice(
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> Choice {
            #if DEBUG
                choice(isDebugBuild: true, environment: environment)
            #else
                choice(isDebugBuild: false, environment: environment)
            #endif
        }

        public static func makeService(
            environment: [String: String] = ProcessInfo.processInfo.environment,
            client: any ControlAPIClient = LiveControlAPIClient()
        ) -> any InboxService {
            #if DEBUG
                if environment[scenarioVariable] != nil {
                    return service(for: currentChoice(environment: environment))
                }
            #endif
            return RouterInboxService(client: client)
        }

        /// The fixture matrix's availability. The live service instead reads the router listener.
        ///
        /// Takes the build configuration as a parameter for the same reason `choice` does, so a Debug
        /// test run can assert the Release answer.
        public static func availability(
            isDebugBuild: Bool,
            environment: [String: String]
        ) -> PairingAvailability {
            service(for: choice(isDebugBuild: isDebugBuild, environment: environment)).availability()
        }

        private static func service(for choice: Choice) -> any InboxService {
            switch choice {
            case .noTransport: NoTransportInboxService()
            case let .fixture(scenario): FixtureInboxService(scenario)
            }
        }
    }
#endif
