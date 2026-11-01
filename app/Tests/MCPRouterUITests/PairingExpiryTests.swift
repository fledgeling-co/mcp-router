#if os(macOS)
    import Foundation
    import MCPRouterKit
    import Testing
    @testable import MCPRouterUI

    /// M39 — the pairing sheet's expiry ring, and the typed-code fallback the Mac states rather
    /// than offers as a control.
    ///
    /// A suite of its own rather than more of `PairingSheetTests`, because that file is at
    /// `swiftlint`'s 400-line ceiling and its type body at the 250-line one. Splitting on the item
    /// that added the surface keeps each suite readable and keeps the M6 file describing M6.
    ///
    /// **Everything here is presentation over a fixture, and that is the honest frame rather than a
    /// caveat.** `ShellPairingFactory` returns `NoTransportInboxService` in any Release build, so
    /// `PairingSessionModel.Phase.live` — the only phase that draws a ring or a fallback line — is
    /// unreachable outside a Debug build with `MCPROUTER_PAIRING` set. DEF-001 is why: no symbol in
    /// either app target opens a connection to a paired device. These assertions establish that the
    /// Mac draws an observed remaining fraction when it has one. They establish nothing whatever
    /// about a phone reaching this Mac, and no case here claims an effect.
    @Suite("M39 — the expiry ring, and a fallback stated rather than offered")
    @MainActor
    struct PairingExpiryTests {
        static let now = RecordedPairingClock.issuedAt

        static func session(
            _ scenario: FixtureInboxService.Scenario,
            at now: Date = PairingExpiryTests.now
        ) -> PairingSessionModel {
            PairingSessionModel(
                service: FixtureInboxService(scenario),
                client: FixtureControlAPIClient(.populated),
                macName: "Luke's MacBook Pro",
                clock: { now }
            )
        }

        /// The model's half of the ring: it exists exactly when a live code does, and it moves.
        ///
        /// Three readings rather than one, because a `fractionRemaining` hard-wired to 1 would
        /// satisfy any single-instant assertion — and a full ring that never depletes is precisely
        /// the indeterminate spinner this item replaced.
        @Test("the fraction the ring draws is observed, and it falls as the clock runs")
        func theFractionFalls() async throws {
            var instant = Self.now
            let session = PairingSessionModel(
                service: FixtureInboxService(.paired),
                client: FixtureControlAPIClient(.populated),
                macName: "Mac",
                clock: { instant }
            )

            let dark = Self.session(.none)
            dark.open()
            #expect(dark.fractionRemaining == nil, "no code means no window to draw")

            session.open()
            try await ShellTestSupport.waitUntil { session.liveCode != nil }
            #expect(session.fractionRemaining == 1)

            instant = Self.now.addingTimeInterval(MacPairing.lifetime / 2)
            session.tick()
            let half = try #require(session.fractionRemaining)
            #expect(abs(half - 0.5) < 0.0001, "the ring is half full halfway through")

            instant = Self.now.addingTimeInterval(MacPairing.lifetime)
            session.tick()
            #expect(session.fractionRemaining == nil, "an expired code draws no arc")
            #expect(session.remaining == nil, "and no countdown either — they go together")
        }

        /// The ring reads the model rather than a constant.
        ///
        /// A source gate, and the weaker rung is stated rather than dressed up: this host has no
        /// accessor for a SwiftUI `Shape`'s trim value, so what is checkable here is the binding.
        /// The names it scans for are pinned by `theRingSymbolsAreReal` below, because a scan for a
        /// spelling that cannot appear passes on its own absence — the failure
        /// `endpointFieldsAreNeverDrawn` above records having shipped once already.
        @Test("the countdown draws the ring from the session's own fraction")
        func theCountdownBindsTheRing() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Boards/PairingSheet.swift"
            )
            let body = try ShellTestSupport.declarationBody(
                of: "private var countdown: some View",
                in: source
            )
            #expect(body.contains("session.fractionRemaining"))
            #expect(body.contains("PairingExpiryRing(fraction:"))
            #expect(body.contains("session.remaining"), "the words are still drawn beside the arc")
        }

        /// The arc's own drawing: an observed fraction, the two tokens the mock names, and nothing
        /// the accessibility tree has to read twice.
        @Test("the ring trims to the fraction it is handed and is hidden from VoiceOver")
        func theRingDrawsTheFraction() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Boards/PairingSheet.swift"
            )
            let body = try ShellTestSupport.declarationBody(
                of: "struct PairingExpiryRing: View",
                in: source
            )
            #expect(body.contains(".trim(from: 0, to: fraction)"), "the arc is the fraction")
            #expect(body.contains("ColorToken.lineStrong.color"), "the track")
            #expect(
                body.contains("ColorToken.t2.color"),
                "the head is the countdown's own colour, not the ask-a-human one"
            )
            #expect(
                !body.contains("ColorToken.attention.color"),
                "InboxConformanceTests' A15 census is the gate that settled this"
            )
            #expect(body.contains(".accessibilityHidden(true)"))
            #expect(
                !body.contains(".repeatForever"),
                "a spinner would turn at one rate whatever the remaining time"
            )
        }

        /// The scans above only bite while these names are the real ones. A rename would otherwise
        /// leave them looking for nothing and passing on the absence.
        @Test("the ring's scanned names are the ones the product declares")
        func theRingSymbolsAreReal() throws {
            let view = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Boards/PairingSheet.swift"
            )
            #expect(view.contains("struct PairingExpiryRing: View"))
            let model = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Boards/PairingSessionModel.swift"
            )
            #expect(
                model.contains("public var fractionRemaining: Double?"),
                "PairingSessionModel no longer publishes a fraction — the ring scan reads nothing"
            )
            #expect(ColorToken.lineStrong.rawValue == "--line-strong")
            #expect(ColorToken.t2.rawValue == "--t2")
        }

        /// The ring's geometry comes from documented tokens, which is what keeps `DESIGN.md`
        /// authoritative for a shape `no-raw-design-values.sh` would not otherwise measure — a
        /// `lineWidth:` naming a property passes that lint whatever the property holds.
        @Test("the ring's size and weight are tokens rather than picked numbers")
        func theRingGeometryIsTokenised() {
            #expect(InboxBoardMetrics.expiryRing == MetricToken.controlMini.leadingScalar)
            #expect(InboxBoardMetrics.expiryRingStroke == MetricToken.focusRing.leadingScalar)
        }

        /// The fallback the brief asks for, and **the reason it is a sentence rather than a button.**
        ///
        /// DEF-064 measured the Mac sheet declaring `Can't scan? Type a code` — the phone's control
        /// — with nothing behind it. The Mac has no second screen to reveal: it already draws the
        /// eight characters under the QR, and the device that does the typing is the other one. So
        /// what ships here is the instruction, and the assertion below is that no control came with
        /// it.
        @Test("the live state states the typed fallback, and adds no control for it")
        func theTypedFallbackIsStated() throws {
            let source = try ShellTestSupport.repoFile(
                "app/Sources/MCPRouterUI/Boards/PairingSheet.swift"
            )
            let live = try ShellTestSupport.declarationBody(
                of: "private func live(issued: IssuedPairingCode, encoded: String) -> some View",
                in: source
            )
            #expect(live.contains("typedFallback"))

            let fallback = try ShellTestSupport.declarationBody(
                of: "private var typedFallback: some View",
                in: source
            )
            #expect(fallback.contains("InboxCopy.Pairing.typeInsteadDetail"))
            #expect(!fallback.contains("Button"), "a Mac button here would have nothing behind it")

            let bar = try ShellTestSupport.declarationBody(
                of: "private var actionBar: some View",
                in: source
            )
            #expect(!bar.contains("typeInstead"), "the fallback did not become a fourth control")
        }

        /// The copy itself: this Mac's sentence, not the phone's button re-used.
        @Test("the Mac's fallback copy points at the phone and is not the phone's own button")
        func theFallbackCopyIsTheMacs() {
            let detail = InboxCopy.Pairing.typeInsteadDetail
            #expect(detail != InboxCopy.Pairing.typeInstead, "the phone's control is a different string")
            #expect(detail.contains("eight characters"), "it names what to type")
            #expect(detail.contains("phone"), "and where to type it")
            #expect(!detail.isEmpty)
        }
    }
#endif
