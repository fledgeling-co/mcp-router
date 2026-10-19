#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// B3 — the Mac sheet asks the router for its code, gives it back on close, and asks for nothing
    /// at all in a build with no endpoint.
    ///
    /// The code comes from the router's `POST /pairing/codes`, which is a fact a test can count, so
    /// every assertion here reads a call count on a recording decorator rather than a value the
    /// sheet could have computed locally.
    @Suite("B3 — the Mac sheet takes its code from the router and gives it back on close")
    @MainActor
    struct PairingRouterCodeTests {
        /// The instant the captured fixture was issued at, so the clock and the router agree.
        static let now = Date(timeIntervalSince1970: 1_792_375_158)

        static func session(
            _ scenario: FixtureInboxService.Scenario,
            client: any ControlAPIClient
        ) -> PairingSessionModel {
            PairingSessionModel(
                service: FixtureInboxService(scenario),
                client: client,
                macName: "Luke's MacBook Pro",
                clock: { Self.now }
            )
        }

        @Test("the code on screen is the one the router issued, and it is asked for once")
        func theCodeIsTheRoutersCode() async throws {
            let recorder = RecordingControlAPIClient(wrapping: FixtureControlAPIClient(.populated))
            let session = Self.session(.paired, client: recorder)
            session.open()
            try await ShellTestSupport.waitUntil { session.liveCode != nil }

            let expected = try await FixtureControlAPIClient(.populated).issuePairingCode()
            #expect(session.liveCode == expected)
            #expect(recorder.calls.pairingIssue == 1)
            #expect(recorder.calls.pairingRevoke == 0, "nothing has closed yet")
        }

        @Test("closing the sheet takes the code back from the router")
        func closingRevokes() async throws {
            let recorder = RecordingControlAPIClient(wrapping: FixtureControlAPIClient(.populated))
            let session = Self.session(.paired, client: recorder)
            session.open()
            try await ShellTestSupport.waitUntil { session.liveCode != nil }

            session.close()
            try await ShellTestSupport.waitUntil { recorder.calls.pairingRevoke == 1 }
            #expect(recorder.calls.pairingRevoke == 1)
        }

        /// Pairing disabled means the router is never asked. A revoke for a code that was never
        /// minted would be a call to the router about nothing, so the count is checked after the
        /// close has had a turn to spawn one.
        @Test("with no endpoint the sheet asks the router for nothing and revokes nothing")
        func noEndpointTouchesNoRouter() async throws {
            let recorder = RecordingControlAPIClient(wrapping: FixtureControlAPIClient(.populated))
            let session = Self.session(.none, client: recorder)
            session.open()
            #expect(session.phase == .noEndpoint)
            session.close()
            try await Task.sleep(for: .milliseconds(50))
            #expect(recorder.calls.pairingIssue == 0)
            #expect(recorder.calls.pairingRevoke == 0)
        }

        @Test("a Release build's service reports no endpoint whatever the environment says")
        func releaseReportsNoEndpoint() {
            for scenario in FixtureInboxService.Scenario.allCases {
                #expect(
                    ShellPairingFactory.availability(
                        isDebugBuild: false,
                        environment: [ShellPairingFactory.scenarioVariable: scenario.rawValue]
                    ) == .noEndpoint,
                    "\(scenario.rawValue) reached a Release build's availability"
                )
            }
            #expect(ShellPairingFactory.availability(isDebugBuild: false, environment: [:]) == .noEndpoint)
        }

        /// The Debug branch is the only one that can report an endpoint, and only when a scenario
        /// names one. Without this, the Release assertion above could pass on a factory that never
        /// reports anything.
        @Test("a Debug build reports an endpoint only for a scenario that has one")
        func debugReportsAnEndpointWhenNamed() {
            #expect(ShellPairingFactory.availability(isDebugBuild: true, environment: [:]) == .noEndpoint)
            #expect(
                ShellPairingFactory.availability(
                    isDebugBuild: true,
                    environment: [ShellPairingFactory.scenarioVariable: "paired"]
                ) != .noEndpoint
            )
        }

        @Test("a router that is not running is a stated failure, not a code")
        func offlineRouterIsAFailure() async throws {
            let session = Self.session(.paired, client: FixtureControlAPIClient(.offline))
            session.open()
            try await ShellTestSupport.waitUntil { session.phase != .preparing }

            guard case .failed = session.phase else {
                Issue.record("expected a stated failure, got \(session.phase)")
                return
            }
            #expect(session.liveCode == nil)
            #expect(session.encodedPayload == nil, "no bytes exist for a QR to draw")
        }

        @Test("reissuing after expiry asks the router again")
        func reissueAsksAgain() async throws {
            let recorder = RecordingControlAPIClient(wrapping: FixtureControlAPIClient(.populated))
            let session = Self.session(.paired, client: recorder)
            session.open()
            try await ShellTestSupport.waitUntil { session.liveCode != nil }

            session.reissue()
            try await ShellTestSupport
                .waitUntil { recorder.calls.pairingIssue == 2 && session.liveCode != nil }
            #expect(recorder.calls.pairingIssue == 2)
        }

        /// The race the revoke-on-close exists for. The router can mint a code after the sheet has
        /// already closed: the close's revoke then runs before the code exists, and nothing else
        /// would take it back. The gate holds the issue in flight so the close lands first.
        @Test("a code the router mints after the sheet closed is taken back, and never shown")
        func lateCodeIsRevoked() async throws {
            let (gate, release) = AsyncStream<Void>.makeStream()
            let recorder = RecordingControlAPIClient(
                wrapping: FixtureControlAPIClient(.populated),
                issueGate: {
                    var iterator = gate.makeAsyncIterator()
                    _ = await iterator.next()
                }
            )
            let session = Self.session(.paired, client: recorder)
            session.open()
            try await ShellTestSupport.waitUntil { recorder.calls.pairingIssue == 1 }

            session.close()
            release.yield(())
            // `waitUntil` only polls, so the count it waits for is asserted here as well.
            try await ShellTestSupport.waitUntil { recorder.calls.pairingRevoke == 2 }
            #expect(recorder.calls.pairingRevoke == 2, "the close's revoke, then the late code's")
            #expect(session.liveCode == nil, "the sheet was closed, so nothing it minted is on screen")
        }
    }
#endif
