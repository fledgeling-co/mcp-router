import Foundation
import MCPRouterKit

/// Which control client the phone talks to, and the one rule that must never bend.
///
/// **A Release build may never render a fixture.** This is `ShellClientFactory`'s rule, written
/// for the Mac and stated there in full — and until I3 the phone had no equivalent at all.
/// `MCPRouterIOSApp` passed no `client:`, so `PhoneShell` took its `FixtureControlAPIClient()`
/// default in every configuration, Release included.
///
/// I2 shipped under that gap and it went unregistered. This item cannot, because the **Library**
/// is the one surface whose entire claim is *this is what you have installed*: a fixture there
/// presents four invented servers as the user's real declared set, in the present tense, on a
/// device with no router. Discover showing recorded search results is misleading; the Library
/// showing recorded servers is a false statement about the user's own machine.
///
/// **This file lives in `MCPRouterUI`, not in `app/MCPRouterIOS/`.** That is deliberate and it
/// is what makes the rule checkable: `app/MCPRouterIOS` is an Xcode target and not a SwiftPM
/// one, so nothing in it is compiled or run by `swift test`. A factory placed there could only
/// be exercised by booting a simulator — and the whole argument for taking `isDebugBuild` as a
/// parameter is that a Debug test run can assert the *Release* branch. `ShellClientFactory` is
/// `#if os(macOS)` inside this same target for exactly the same reason.
///
/// **And this file carries no `#if os(iOS)` of its own**, which is the other half of that argument.
/// `ShellClientFactory` needs its gate because it builds Mac-only collaborators; nothing here is
/// platform-specific — the decision is a pure function and both clients are the kit's, which
/// compiles for both platforms. Gating it to iOS would exclude it from the macOS host run and put
/// the Release-branch assertion back behind a simulator, which is the situation this file exists to
/// avoid.
///
/// What a Release build honestly shows today is **Offline**: `LiveControlAPIClient`'s loopback
/// is the *phone's* loopback, and there is no router on it. That is true, it is one of
/// `DESIGN.md` §5's designed states, and the transport (M6's D-m6-a) is what resolves it.
public enum PhoneClientFactory {
    /// The variable the acceptance gate sets to choose a state. Debug builds only.
    public static let scenarioVariable = "MCPROUTER_SCENARIO"

    public enum Choice: Equatable, Sendable {
        /// The real loopback control API. What ships.
        case live
        /// A named fixture. Debug only, and only ever chosen deliberately.
        case fixture(FixtureControlAPIClient.Scenario)
    }

    /// The decision, with the build configuration passed in rather than read, so a test can
    /// assert the Release branch from a Debug test run — the only way the rule above is
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
