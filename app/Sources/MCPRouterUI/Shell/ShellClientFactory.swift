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
    ///
    /// ## J5 — the Debug branch can also choose the REAL router, at a router of the caller's choosing
    ///
    /// Every scenario above is a fixture, and a fixture is this project's own account of itself. A
    /// board photographed against `FixtureControlAPIClient(.populated)` proves the board renders that
    /// JSON file; it says nothing about whether the board reflects a router, and nothing at all about
    /// what it does when a router that WAS answering stops. `REQ-004`, `REQ-005` and `REQ-007` are
    /// exactly those three claims, and all three stood on `reported` evidence because a Debug build
    /// had no way to reach a live router: `MCPROUTER_SCENARIO=live` fell through
    /// `Scenario(rawValue:)` and silently rendered `.populated`.
    ///
    /// `MCPROUTER_SCENARIO=live` now selects `LiveControlAPIClient`, and `MCP_ROUTER_URL` names which
    /// router — so the acceptance lane can start a throwaway router on a port of its own, author what
    /// that router declares, kill it mid-run, and photograph what the boards say about each of those
    /// conditions. The figures on screen then have an external oracle: the same router, read
    /// independently over HTTP.
    ///
    /// Three properties of this branch are deliberate and are what keep it from becoming a second way
    /// to lie:
    ///
    /// - **Release still ignores all of it.** The guard below returns `.live(shippingEndpoint)` before
    ///   any variable is read, so a shipped build can be pointed at neither a fixture nor a foreign
    ///   endpoint.
    /// - **Loopback only.** The product's standing constraint is that the Mac app talks to the router
    ///   over loopback and nothing else. An endpoint that is not loopback is refused and the shipping
    ///   endpoint is used instead — a Debug affordance may not become an exfiltration route.
    /// - **A chosen endpoint reads the router's OWN token file** (honouring `MCP_ROUTER_HOME`, which
    ///   is how `ControlProbe` is pointed at a throwaway router) through an in-memory store, so the
    ///   user's Keychain is neither read nor written and their real token is never sent to a scratch
    ///   router. That wiring lives in `LiveControlAPIClient.init(scratchAt:)` rather than here, and
    ///   the reason is A36: the shell reaches the outside world through the client and through
    ///   nothing else, and `ShellIntegrationTests.theClientIsTheOnlyChannel` enforces it by
    ///   grepping this file for every type that could open a channel of its own.
    ///   An earlier draft of this feature assembled the session here and that test caught it.
    public enum ShellClientFactory {
        /// The variable the acceptance gate sets to choose a state. Debug builds only.
        public static let scenarioVariable = "MCPROUTER_SCENARIO"

        /// The value of `scenarioVariable` that selects the real router rather than a fixture.
        ///
        /// It is not a `Scenario` case, and deliberately so: `Scenario` is the fixture vocabulary and
        /// a "live fixture" is a contradiction. Reserving the name here also closes the trap that
        /// made this feature necessary — before this, `MCPROUTER_SCENARIO=live` was an unrecognised
        /// name, and an unrecognised name renders `.populated` without saying so.
        public static let liveScenarioName = "live"

        /// The variable that names WHICH router a Debug build talks to. Debug builds only.
        ///
        /// The same variable `ControlProbe` and `MeasureDump --document-from` already use, so a lane
        /// that starts a throwaway router sets one name for every tool that has to reach it.
        public static let endpointVariable = "MCP_ROUTER_URL"

        /// The router a shipped build talks to, and the fallback for a Debug build that named one
        /// this factory will not honour.
        public static let shippingEndpoint = URL(string: "http://127.0.0.1:8879")!

        /// The hosts a Debug build may be pointed at.
        ///
        /// Loopback literals and `localhost`, and nothing else. `URL.host` strips the brackets from
        /// an IPv6 literal, so `[::1]` arrives here as `::1`.
        static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1"]

        public enum Choice: Equatable, Sendable {
            /// The real loopback control API, at this endpoint. What ships — always at
            /// `shippingEndpoint` in a Release build.
            case live(URL)
            /// A named fixture. Debug only, and only ever chosen deliberately.
            case fixture(FixtureControlAPIClient.Scenario)
        }

        /// The decision, with the build configuration passed in rather than read, so a test can
        /// assert the Release branch from a Debug test run — which is the only way the rule above is
        /// checkable at all.
        public static func choice(isDebugBuild: Bool, environment: [String: String]) -> Choice {
            guard isDebugBuild else {
                // Deliberately ignores the environment. A Release build that could be talked into a
                // fixture by an env var is a Release build that can display invented numbers, and one
                // that could be talked into a foreign endpoint is a worse version of the same thing.
                return .live(shippingEndpoint)
            }
            guard let named = environment[scenarioVariable] else {
                return .fixture(.populated)
            }
            if named == liveScenarioName {
                return .live(endpoint(in: environment))
            }
            guard let scenario = FixtureControlAPIClient.Scenario(rawValue: named) else {
                return .fixture(.populated)
            }
            return .fixture(scenario)
        }

        /// The endpoint a Debug build was pointed at, or the shipping one.
        ///
        /// A URL that is not http-over-loopback is refused rather than honoured. The refusal is
        /// silent here on purpose — this returns a `URL`, not a diagnosis — and the lane that sets
        /// the variable is what notices: it authors what its own router declares, so a shell that
        /// fell back to `shippingEndpoint` reads a different router and the assertion goes red on the
        /// server names rather than passing against the wrong world.
        static func endpoint(in environment: [String: String]) -> URL {
            guard let raw = environment[endpointVariable],
                  let url = URL(string: raw),
                  url.scheme == "http",
                  let host = url.host,
                  loopbackHosts.contains(host)
            else { return shippingEndpoint }
            return url
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
            case let .live(url): makeLiveClient(at: url)
            case let .fixture(scenario): FixtureControlAPIClient(scenario)
            }
        }

        /// The live client, wired one of two ways.
        ///
        /// At the shipping endpoint everything is the default: the shared session and the Keychain,
        /// which is what the product needs and what it has always done. At a chosen endpoint the
        /// token comes from that router's own file under `MCP_ROUTER_HOME` through an in-memory
        /// store, so a lane pointed at a throwaway router neither reads nor writes the user's
        /// Keychain and never sends their credential to a router this repository started.
        private static func makeLiveClient(at url: URL) -> LiveControlAPIClient {
            url == shippingEndpoint ? LiveControlAPIClient() : LiveControlAPIClient(scratchAt: url)
        }

        /// The live call feed, chosen by exactly the same rule as the client.
        ///
        /// It is here rather than inside the board for one reason: a Debug build running a fixture
        /// must not open a socket to 127.0.0.1. If the board built its own `ControlEventStream` it
        /// would do precisely that — the client would be answering from a recording while the feed
        /// hammered a port with nothing behind it, and the reconnect policy would spend its six
        /// attempts before reporting a disconnection that says nothing about the app. One decision,
        /// made once, in the place that already makes it.
        ///
        /// A fixture scenario whose recording cannot be read returns `nil` rather than a source that
        /// yields nothing: "no feed configured" and "the feed is silent" are different conditions,
        /// and a surface told the second about the first would sit reporting a live stream forever.
        public static func makeEventSource(
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> (any ActivityEventSource)? {
            switch currentChoice(environment: environment) {
            case let .live(url):
                LiveActivityEventSource(makeEventStream(at: url))
            case let .fixture(scenario):
                (try? FixtureControlAPIClient(scenario).streamEvents())
                    .map(ReplayActivityEventSource.init)
            }
        }

        /// The feed, pointed at the same router as the client above and by the same rule.
        ///
        /// Splitting the two would let a Debug build read one router's servers while streaming
        /// another's calls, which is the tracker's merge fed from two worlds — the one input shape
        /// `ServerStateTracker`'s precedence rules cannot make honest.
        private static func makeEventStream(at url: URL) -> ControlEventStream {
            url == shippingEndpoint ? ControlEventStream() : ControlEventStream(scratchAt: url)
        }
    }
#endif
