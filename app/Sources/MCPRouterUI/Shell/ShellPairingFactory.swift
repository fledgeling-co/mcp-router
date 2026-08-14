#if os(macOS)
    import Foundation
    import MCPRouterKit

    /// Which inbox the shell talks to, and the one rule that must never bend.
    ///
    /// This is `ShellClientFactory`'s rule applied to the second seam that can fabricate: **a Release
    /// build may never render a fixture.** There it was invented server counts; here it is worse.
    /// `PairingPayload` carries a host, a port and a certificate fingerprint, and no listener is
    /// bound anywhere in either app target — so a Release build that could be talked into the
    /// "paired" scenario would draw a **QR code encoding an endpoint that does not exist**. A phone
    /// scans it, stores it, and reports "Paired." for a Mac it can never reach. That is not merely an
    /// unobserved number (`DESIGN.md` §6); it is an unobserved number made actionable and handed to
    /// another device.
    ///
    /// So the Release branch takes no input — the environment cannot talk a shipped build into a
    /// fixture — and it does not name the fixture type at all: it returns `NoTransportInboxService`,
    /// which is the *truthful* implementation for a build in which nothing can arrive, rather than a
    /// fixture happening to be configured empty.
    ///
    /// **The Debug branch takes a scenario from the environment**, which is what makes every cell of
    /// `spec-M6.md`'s state matrix reachable in the running app. Without it, eleven of eighteen cells
    /// would have no lane, and the acceptance gate could not have proven them however long it ran.
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
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> any InboxService {
            switch currentChoice(environment: environment) {
            case .noTransport: NoTransportInboxService()
            case let .fixture(scenario): FixtureInboxService(scenario)
            }
        }
    }
#endif
