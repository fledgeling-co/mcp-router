import Foundation
import Testing
@testable import MCPRouterKit

@Suite("M6 — the Mac half of pairing")
struct MacPairingTests {
    /// A generator that yields a fixed sequence, so a "random" code is reproducible.
    ///
    /// Deterministic rather than seeded-random: a test that asserts on a specific code needs the
    /// same code every run, and a seeded system generator is not guaranteed stable across releases.
    struct FixedGenerator: RandomNumberGenerator {
        var values: [UInt64]
        var index = 0

        mutating func next() -> UInt64 {
            defer { index += 1 }
            return values[index % values.count]
        }
    }

    static let endpoint = PairingEndpoint(
        host: "192.168.1.24",
        port: 7333,
        fingerprint: "SHA256:5f2b9c0e"
    )

    static let now = Date(timeIntervalSince1970: 1_755_000_000)

    // MARK: - A8 · the alphabet, asserted where a mutation can be caught

    /// The exclusion, asserted on `randomCanonicalCharacters` **directly**.
    ///
    /// Not through `issue`, and that is the point rather than convenience: `issue` ends in a
    /// `preconditionFailure` if the characters are not canonical, and a precondition is a process
    /// trap that Swift Testing cannot catch. A mutation widening the alphabet would therefore crash
    /// the whole run rather than fail one assertion — a gate that cannot report. Asserting on the
    /// function that draws the characters catches it as a red test.
    @Test("a generated code never contains I, L, O or U")
    func generatedCodesExcludeTheAmbiguousLetters() {
        var generator = SystemRandomNumberGenerator()
        // Many draws, not one: with eight characters from a 32-letter alphabet, a single code
        // proves almost nothing about which letters can appear.
        for _ in 0 ..< 2000 {
            let characters = MacPairing.randomCanonicalCharacters(using: &generator)
            #expect(characters.count == PairingCode.length)
            for excluded in ["I", "L", "O", "U"] {
                #expect(!characters.contains(excluded), "\(characters) contains \(excluded)")
            }
            #expect(characters.allSatisfy { PairingCode.alphabet.contains($0) })
        }
    }

    /// The generated characters are accepted by **I1's own parser**, not by a local copy.
    @Test("a generated code round-trips through the phone's parser")
    func generatedCodesParse() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0 ..< 500 {
            let issued = MacPairing.issue(at: Self.now, using: &generator)
            let reparsed = PairingCode(issued.code.canonical)
            #expect(reparsed == issued.code)
            // And through the formatted shape a human would retype.
            #expect(PairingCode(issued.code.formatted) == issued.code)
        }
    }

    // MARK: - The version, and the drift it could hide

    /// `wireVersion` replaced `supportedVersions.max() ?? 1`, which reintroduced the literal it was
    /// meant to remove and picked the wrong end of the set. This is what keeps the two in step.
    @Test("the version the Mac emits is one the phone accepts")
    func wireVersionIsSupported() {
        #expect(PairingPayload.supportedVersions.contains(MacPairing.wireVersion))
        #expect(MacPairing.wireVersion == PairingPayload.supportedVersions.min())
    }

    // MARK: - Expiry

    /// The expiry is whole seconds, which is a **wire requirement** rather than tidiness.
    ///
    /// `ISO8601Instant.string` writes no fractional part while its parser accepts one, so a
    /// sub-second expiry encodes lossily and decodes to a different `Date` — and the wire-conformance
    /// test comparing fields would then fail against a payload that is otherwise correct.
    @Test("an issued expiry carries no sub-second component")
    func expiryIsWholeSeconds() {
        // A deliberately fractional issue instant, which is what `Date()` gives in practice.
        let fractional = Date(timeIntervalSince1970: 1_755_000_000.738_214)
        let issued = MacPairing.issue(at: fractional)
        let seconds = issued.expiresAt.timeIntervalSince1970
        #expect(seconds == seconds.rounded(.down))
    }

    @Test("the code lives for the stated lifetime and then reports expired")
    func expiryWindow() {
        let issued = MacPairing.issue(at: Self.now)
        #expect(!issued.hasExpired(at: Self.now))
        #expect(!issued.hasExpired(at: Self.now.addingTimeInterval(MacPairing.lifetime - 1)))
        #expect(issued.hasExpired(at: Self.now.addingTimeInterval(MacPairing.lifetime)))
        // Nil rather than a negative number: a countdown reading -0:12 is a number the system
        // observed and then rendered as nonsense.
        #expect(issued.timeRemaining(at: Self.now.addingTimeInterval(MacPairing.lifetime + 5)) == nil)
        #expect(issued.timeRemaining(at: Self.now) == MacPairing.lifetime)
    }

    // MARK: - A5, A7 · the endpoint is failable against the payload's own constraints

    /// An endpoint that could not produce a decodable payload cannot be constructed at all, which
    /// puts the check one layer earlier than the encoder.
    @Test("an endpoint the phone could not decode cannot be built")
    func endpointRejectsWhatThePayloadWouldReject() {
        #expect(PairingEndpoint(host: "", port: 7333, fingerprint: "fp") == nil)
        #expect(PairingEndpoint(host: "h", port: 0, fingerprint: "fp") == nil)
        #expect(PairingEndpoint(host: "h", port: 65536, fingerprint: "fp") == nil)
        #expect(PairingEndpoint(host: "h", port: 7333, fingerprint: "") == nil)
        #expect(PairingEndpoint(host: "h", port: 1, fingerprint: "fp") != nil)
        #expect(PairingEndpoint(host: "h", port: 65535, fingerprint: "fp") != nil)
    }

    // MARK: - A10 · deciding

    @Test("an unsupported version is refused by name, not as a generic failure")
    func unsupportedVersionIsNamed() throws {
        let issued = MacPairing.issue(at: Self.now)
        let refusal = MacPairing.decide(
            submitted: issued.code,
            version: 99,
            live: issued,
            spent: [],
            at: Self.now
        )
        #expect(refusal == .unsupportedVersion(found: 99))
        // And it maps to the outcome the phone already knows how to render.
        #expect(
            try MacPairing.outcome(for: #require(refusal), macName: "Mac")
                == .versionMismatch(macName: "Mac")
        )
    }

    /// **Spent is checked before liveness, and this is the assertion that pins the order.**
    ///
    /// A code that was used and then re-submitted must say `alreadyUsed` rather than
    /// `notRecognised` — which is what it would say if liveness were checked first, since by then a
    /// newer code has replaced it on screen. The two send the user to different places, so the
    /// order is behaviour rather than style.
    @Test("a spent code says so even once a newer code is live")
    func spentBeatsLive() {
        let first = MacPairing.issue(at: Self.now)
        let second = MacPairing.issue(at: Self.now.addingTimeInterval(10))
        let refusal = MacPairing.decide(
            submitted: first.code,
            version: MacPairing.wireVersion,
            live: second,
            spent: [first.code],
            at: Self.now.addingTimeInterval(10)
        )
        #expect(refusal == .alreadyUsed)
    }

    @Test("an expired live code is expired, and an unknown one is not recognised")
    func expiredAndUnknown() {
        let issued = MacPairing.issue(at: Self.now)
        #expect(
            MacPairing.decide(
                submitted: issued.code,
                version: MacPairing.wireVersion,
                live: issued,
                spent: [],
                at: Self.now.addingTimeInterval(MacPairing.lifetime + 1)
            ) == .expired
        )

        var generator = FixedGenerator(values: [7])
        let other = MacPairing.issue(at: Self.now, using: &generator)
        #expect(
            MacPairing.decide(
                submitted: other.code,
                version: MacPairing.wireVersion,
                live: issued,
                spent: [],
                at: Self.now
            ) == .notRecognised
        )

        // No code issued at all is also "not recognised" rather than a crash or a pass.
        #expect(
            MacPairing.decide(
                submitted: issued.code,
                version: MacPairing.wireVersion,
                live: nil,
                spent: [],
                at: Self.now
            ) == .notRecognised
        )
    }

    @Test("a live, unspent, unexpired code of a known version is accepted")
    func theHappyPath() {
        let issued = MacPairing.issue(at: Self.now)
        #expect(
            MacPairing.decide(
                submitted: issued.code,
                version: MacPairing.wireVersion,
                live: issued,
                spent: [],
                at: Self.now
            ) == nil
        )
    }

    /// Every refusal maps to its own outcome — never a generic failure, which is the argument
    /// `PairingOutcome` itself is built on.
    @Test("each refusal maps to a distinct outcome")
    func refusalsMapDistinctly() {
        let refusals: [PairingRefusal] = [
            .notRecognised, .expired, .alreadyUsed, .unsupportedVersion(found: 2), .declined
        ]
        let outcomes = refusals.map { MacPairing.outcome(for: $0, macName: "Mac") }
        #expect(Set(outcomes.map(String.init(describing:))).count == refusals.count)
        #expect(outcomes.allSatisfy { !$0.isSuccess })
    }
}

@Suite("M6 — A9 · wire-format conformance with the phone")
struct MacPairingWireTests {
    /// **This proves codec agreement, not delivery.**
    ///
    /// The Mac encodes and I1's shipped decoder reads it back. That is the whole claim, and it is
    /// worth stating precisely because the fleet's wave-6 gate asks for a phone-to-Mac *round trip*
    /// — which needs a transport neither app has. Calling this the round trip would be a fake gate.
    @Test("a payload the Mac encodes decodes to an equal payload, field for field")
    func encodeDecodeRoundTrip() throws {
        let endpoint = try #require(MacPairingTests.endpoint)
        let issued = MacPairing.issue(at: MacPairingTests.now)
        let payload = MacPairing.payload(for: issued, endpoint: endpoint, macName: "Luke's MacBook Pro")

        let text = try MacPairing.encode(payload)
        let decoded = try PairingPayload.decode(text)

        #expect(decoded.version == payload.version)
        #expect(decoded.code == payload.code)
        #expect(decoded.macName == payload.macName)
        #expect(decoded.expiresAt == payload.expiresAt)
        #expect(decoded.host == payload.host)
        #expect(decoded.port == payload.port)
        #expect(decoded.fingerprint == payload.fingerprint)
        #expect(decoded == payload)
    }

    /// The discriminator is the phone's first gate, so it is asserted on the produced bytes rather
    /// than on the type — a rename in the encoder would otherwise pass every equality above by
    /// changing both sides at once.
    @Test("the encoded text carries the discriminator and the code the phone looks for")
    func encodedBytesCarryTheAgreedKeys() throws {
        let endpoint = try #require(MacPairingTests.endpoint)
        let issued = MacPairing.issue(at: MacPairingTests.now)
        let payload = MacPairing.payload(for: issued, endpoint: endpoint, macName: "Mac")
        let text = try MacPairing.encode(payload)

        let object = try #require(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        #expect(object["t"] as? String == PairingPayload.discriminator)
        #expect(object["v"] as? Int == MacPairing.wireVersion)
        #expect(object["code"] as? String == issued.code.canonical)
        #expect(object["fp"] as? String == endpoint.fingerprint)
        #expect(object["port"] as? Int == endpoint.port)
    }

    /// A payload the Mac would not have produced is still rejected by the phone's parser, which is
    /// what stops this test passing merely because both sides share a bug.
    @Test("the phone's decoder still rejects a foreign payload")
    func foreignPayloadsAreRefused() {
        #expect(throws: PairingPayloadError.notAPairingCode) {
            try PairingPayload.decode(#"{"t":"something-else","v":1}"#)
        }
        #expect(throws: PairingPayloadError.unsupportedVersion(found: 99)) {
            try PairingPayload.decode(#"{"t":"mcp-router-pair","v":99}"#)
        }
    }
}
