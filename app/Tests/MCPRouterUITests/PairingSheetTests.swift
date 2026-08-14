#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    @Suite("M6 — the Mac pairing sheet, and the rule that keeps it honest")
    @MainActor
    struct PairingSheetTests {
        static let now = Date(timeIntervalSince1970: 1_755_000_000)

        static func session(
            _ scenario: FixtureInboxService.Scenario,
            at now: Date = PairingSheetTests.now
        ) -> PairingSessionModel {
            PairingSessionModel(
                service: FixtureInboxService(scenario),
                macName: "Luke's MacBook Pro",
                clock: { now }
            )
        }

        // MARK: - A6 · the Release branch takes no input

        /// **The single most important assertion in this item.**
        ///
        /// `PairingPayload` carries a host, a port and a certificate fingerprint, and no listener is
        /// bound anywhere in either app target. A Release build that could be talked into the paired
        /// scenario would draw a QR encoding an endpoint nothing answers on and the fingerprint of no
        /// certificate — a phone would scan it, store it, and report "Paired." for a Mac it can never
        /// reach. So the Release branch ignores the environment, and it is asserted against **every**
        /// scenario name rather than against one, because a branch that reads the variable at all
        /// would pass a test that only ever tries the default.
        @Test("no environment value can make a Release build offer a fixture")
        func releaseIgnoresEveryScenario() {
            for scenario in FixtureInboxService.Scenario.allCases {
                let choice = ShellPairingFactory.choice(
                    isDebugBuild: false,
                    environment: [ShellPairingFactory.scenarioVariable: scenario.rawValue]
                )
                #expect(choice == .noTransport, "\(scenario.rawValue) reached a Release build")
            }
            // Including values that are not scenarios at all.
            #expect(
                ShellPairingFactory.choice(
                    isDebugBuild: false,
                    environment: [ShellPairingFactory.scenarioVariable: "paired "]
                ) == .noTransport
            )
            #expect(ShellPairingFactory.choice(isDebugBuild: false, environment: [:]) == .noTransport)
        }

        /// Debug reads the variable, and its unset default is what ships rather than the richest
        /// fixture — a developer who has set nothing should see the honest state.
        @Test("Debug takes a named scenario, and defaults to the shipping one")
        func debugTakesAScenario() {
            #expect(
                ShellPairingFactory.choice(
                    isDebugBuild: true,
                    environment: [ShellPairingFactory.scenarioVariable: "paired"]
                ) == .fixture(.paired)
            )
            #expect(ShellPairingFactory.choice(isDebugBuild: true, environment: [:]) == .fixture(.none))
            // An unrecognised name is the honest state too, not another scenario.
            #expect(
                ShellPairingFactory.choice(
                    isDebugBuild: true,
                    environment: [ShellPairingFactory.scenarioVariable: "typo"]
                ) == .fixture(.none)
            )
        }

        // MARK: - A5 · no endpoint, no code, no payload

        /// The whole no-endpoint path, asserted at the state rather than at the view: opening the
        /// sheet with no transport issues nothing at all.
        @Test("with no endpoint nothing is issued and nothing is encoded")
        func noEndpointIssuesNothing() {
            let session = Self.session(.none)
            session.open()
            #expect(session.phase == .noEndpoint)
            #expect(session.liveCode == nil)
            #expect(session.encodedPayload == nil, "no bytes exist for a QR to draw")
            #expect(session.remaining == nil, "there is no observed expiry to count down")
        }

        /// And the positive: with an endpoint, a code exists and the encoded bytes carry that exact
        /// code. Without this, A5 would pass on a tree where nothing was built.
        @Test("with an endpoint a code is issued and the bytes carry it")
        func endpointIssuesACode() throws {
            let session = Self.session(.paired)
            session.open()
            let issued = try #require(session.liveCode)
            let encoded = try #require(session.encodedPayload)

            let decoded = try PairingPayload.decode(encoded)
            #expect(decoded.code == issued.code)
            #expect(decoded.macName == "Luke's MacBook Pro")
            #expect(decoded.expiresAt == issued.expiresAt)
            #expect(session.remaining == MacPairing.lifetime)
        }

        // MARK: - A7 · the endpoint is never rendered

        /// `host`, `port` and `fingerprint` are stored and never shown. None of the three tells a
        /// user anything they can act on, and together they are most of what an attacker would want.
        ///
        /// Asserted against the **sources that draw the sheet**, because the value being absent from
        /// a rendered string is what matters — a type-level check would miss a view interpolating it.
        ///
        /// **The token list is the whole test, and the first one could not fail.** It scanned for
        /// `endpoint.host`, `endpoint.port` and `endpoint.fingerprint`; the string `endpoint` occurs
        /// nowhere in any of these four files, and a view reaching the value would spell it
        /// `availability.endpoint?.host`, `payload.host` or `session.…` — none of which the list
        /// matched. So it scanned for a spelling that could not appear and passed on its absence.
        ///
        /// The fix is to forbid the **field names as accessors**, whatever they hang off. The one
        /// exception is `InboxReviewSheet`'s `statement.host`, which is the *registry entry's* remote
        /// host — the thing Discover renders too, and not what A7 is about — so that file is scanned
        /// for the other two. The running-app half of A7 is in `m6-inbox-pairing.sh`, which sweeps
        /// the accessibility tree for the fixture's literal values under a scenario where they exist.
        @Test("no source that draws pairing reads the endpoint's fields")
        func endpointFieldsAreNeverDrawn() throws {
            let everyField = [".host", ".port", ".fingerprint"]
            let drawn: [(path: String, forbidden: [String])] = [
                ("app/Sources/MCPRouterUI/Boards/PairingSheet.swift", everyField),
                ("app/Sources/MCPRouterUI/Boards/InboxBoard.swift", everyField),
                ("app/Sources/MCPRouterUI/Boards/InboxBoardRow.swift", everyField),
                // `statement.host` is the registry entry's own remote host, not the Mac's endpoint.
                ("app/Sources/MCPRouterUI/Boards/InboxReviewSheet.swift", [".port", ".fingerprint"])
            ]
            for (path, forbidden) in drawn {
                let source = try ShellTestSupport.repoFile(path)
                for accessor in forbidden {
                    #expect(!source.contains(accessor), "\(path) reads \(accessor)")
                }
            }
        }

        /// The guard above only bites if the fields are spelled that way on the type. If a rename
        /// ever made them something else, the scan would go quiet rather than red — so the names it
        /// forbids are pinned to the type they came from.
        @Test("the forbidden accessor names are the endpoint's actual field names")
        func theScannedNamesAreReal() throws {
            let source = try ShellTestSupport.repoFile("app/Sources/MCPRouterKit/Pairing/MacPairing.swift")
            for field in ["host", "port", "fingerprint"] {
                #expect(
                    source.contains("public let \(field)"),
                    "PairingEndpoint no longer has a '\(field)' — the A7 scan is looking for nothing"
                )
            }
        }

        // MARK: - The clock

        /// Expiry is driven rather than waited for. `ShellTestSupport.waitUntil` is for a condition
        /// that becomes true on its own; a five-minute countdown is not something to wait on, so the
        /// clock is injected and `tick` is called directly.
        @Test("a code that outlives its window moves to expired, once")
        func expiryMovesThePhase() {
            var instant = Self.now
            let session = PairingSessionModel(
                service: FixtureInboxService(.paired),
                macName: "Mac",
                clock: { instant }
            )
            session.open()
            guard case .live = session.phase else {
                Issue.record("expected a live code, got \(session.phase)")
                return
            }

            instant = Self.now.addingTimeInterval(MacPairing.lifetime - 1)
            session.tick()
            guard case .live = session.phase else {
                Issue.record("expired a second early")
                return
            }

            instant = Self.now.addingTimeInterval(MacPairing.lifetime)
            session.tick()
            guard case .expired = session.phase else {
                Issue.record("expected expired, got \(session.phase)")
                return
            }
            #expect(session.liveCode == nil)
            #expect(session.encodedPayload == nil, "an expired code's bytes are not offered")
        }

        @Test("reissuing after expiry produces a different code")
        func reissueMints() throws {
            var instant = Self.now
            let session = PairingSessionModel(
                service: FixtureInboxService(.paired),
                macName: "Mac",
                clock: { instant }
            )
            session.open()
            let first = try #require(session.liveCode)

            instant = Self.now.addingTimeInterval(MacPairing.lifetime)
            session.tick()
            session.reissue()

            let second = try #require(session.liveCode)
            #expect(second.expiresAt > first.expiresAt)
        }

        // MARK: - One code, one device

        @Test("a paired code is spent, and a second attempt with it is refused as already used")
        func spentCodesAreRecorded() throws {
            let session = Self.session(.paired)
            session.open()
            let issued = try #require(session.liveCode)

            #expect(session.decide(submitted: issued.code) == nil, "the first attempt is accepted")
            session.markPaired(issued.code)
            #expect(session.decide(submitted: issued.code) == .alreadyUsed)
        }

        @Test("dismissing a request is a decision rather than an error")
        func decliningIsADecision() {
            let session = Self.session(.paired)
            #expect(session.declineRequest() == .declined)
            #expect(
                MacPairing.outcome(for: .declined, macName: "Mac") == .refused(macName: "Mac")
            )
        }

        // MARK: - Copy

        /// The countdown renders from an observed remaining interval, in the shape the mock draws.
        @Test("the countdown reads as minutes and padded seconds")
        func countdownFormatting() {
            #expect(InboxCopy.Pairing.expiresIn(292) == "expires in 4:52")
            #expect(InboxCopy.Pairing.expiresIn(60) == "expires in 1:00")
            #expect(InboxCopy.Pairing.expiresIn(9) == "expires in 0:09")
        }

        /// Every refusal has its own sentence — no generic failure, which is the whole argument
        /// `PairingOutcome` and `PairingRefusal` are built on.
        @Test("each refusal has copy of its own")
        func refusalCopyIsDistinct() {
            let refusals: [PairingRefusal] = [
                .notRecognised, .expired, .alreadyUsed, .unsupportedVersion(found: 2), .declined
            ]
            let sentences = refusals.map(InboxCopy.refusal)
            #expect(Set(sentences).count == refusals.count)
            #expect(sentences.allSatisfy { !$0.isEmpty })
            // The version case names the version, because "update the phone app" is only actionable
            // if the reader knows which side is behind.
            #expect(InboxCopy.refusal(.unsupportedVersion(found: 2)).contains("2"))
        }

        /// The no-endpoint copy names what is missing and does not blame the reader or their network.
        @Test("the no-endpoint copy is specific and non-blaming")
        func noEndpointCopy() {
            let detail = InboxCopy.Pairing.noEndpointDetail
            #expect(detail.contains("this build ships no way to listen"))
            #expect(detail.contains("Nothing is wrong with your phone or your network"))
            #expect(!InboxCopy.Pairing.noEndpointTitle.isEmpty)
        }
    }
#endif
