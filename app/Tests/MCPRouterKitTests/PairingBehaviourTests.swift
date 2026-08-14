import Foundation
import Testing
@testable import MCPRouterKit

/// Every outcome has a fixture that produces it, and every outcome has copy.
///
/// The two directions matter separately. A tenth outcome with no fixture is one nobody can see on
/// screen; a tenth outcome with no copy key renders blank. Enumerating from the outcome side
/// catches both.
@Suite("Pairing outcomes")
struct PairingOutcomeCoverageTests {
    /// Every case, constructed once, so the enumeration below is exhaustive by inspection.
    static let allOutcomes: [PairingOutcome] = [
        .paired(FixturePairingService.specimenMac),
        .notRecognised,
        .expired,
        .alreadyUsed,
        .versionMismatch(macName: "Luke's MacBook Pro"),
        .unreachable(macName: "Luke's MacBook Pro"),
        .refused(macName: "Luke's MacBook Pro"),
        .notAPairingCode,
        .malformedPayload
    ]

    @Test("every outcome has copy")
    func everyOutcomeHasCopy() {
        for outcome in Self.allOutcomes {
            let key = PairingCopy.key(for: outcome)
            #expect(key != nil, "\(outcome) has no copy key")
            guard let key else { continue }
            #expect(!PairingCopy.entry(key).body.isEmpty, "\(key) has empty copy")
        }
    }

    @Test("every failure outcome is reachable from some fixture scenario")
    func everyOutcomeHasAFixture() async {
        var produced: Set<String> = []
        let code = PairingCode("K7QN4FMB")!

        for scenario in FixturePairingService.Scenario.allCases {
            let outcome = await FixturePairingService(scenario).pair(using: .typed(code))
            produced.insert(label(for: outcome))
        }

        for outcome in Self.allOutcomes {
            let name = label(for: outcome)
            // The two decode failures never come from the service — they are produced before it is
            // called, by `PairingPayload.decode`, and `PairingPayloadTests` covers them.
            if name == "notAPairingCode" || name == "malformedPayload" { continue }
            #expect(produced.contains(name), "no fixture scenario produces \(name)")
        }
    }

    private func label(for outcome: PairingOutcome) -> String {
        switch outcome {
        case .paired: "paired"
        case .notRecognised: "notRecognised"
        case .expired: "expired"
        case .alreadyUsed: "alreadyUsed"
        case .versionMismatch: "versionMismatch"
        case .unreachable: "unreachable"
        case .refused: "refused"
        case .notAPairingCode: "notAPairingCode"
        case .malformedPayload: "malformedPayload"
        }
    }

    /// A refusal is a decision someone made at the Mac. Retrying against it is the app arguing with
    /// its user, so the copy's one action is not a retry.
    @Test("refused does not offer retry as its action")
    func refusedDoesNotRetry() {
        let entry = PairingCopy.entry(.outcomeRefused)
        #expect(entry.actionLabel == "Back to Settings")
        #expect(entry.actionLabel != "Try again")
    }

    /// The phone can determine this one on its own, so it does — without a round trip that would
    /// fail anyway.
    @Test("a scanned code whose window has closed is expired before the service is consulted")
    func expiredIsDecidedLocally() async {
        let payload = PairingPayload(
            version: 1,
            code: PairingCode("K7QN4FMB")!,
            macName: "Luke's MacBook Pro",
            expiresAt: Date(timeIntervalSince1970: 1),
            host: "192.168.1.24",
            port: 7333,
            fingerprint: "SHA256:5f2b9c0e"
        )
        // The scenario says it would pair. The expiry overrules it.
        let outcome = await FixturePairingService(.paired).pair(using: .scanned(payload))
        #expect(outcome == .expired)
    }
}

/// The honesty rule, as a test rather than a taste argument.
@Suite("Observed expiry")
struct ObservedExpiryTests {
    @Test("a typed attempt has observed no expiry")
    func typedHasNoExpiry() {
        let attempt = PairingAttempt.typed(PairingCode("K7QN4FMB")!)
        #expect(attempt.observedExpiry == nil)
        #expect(attempt.macName == nil, "a typed code cannot know the Mac's name either")
    }

    @Test("a scanned attempt carries the expiry the payload observed")
    func scannedCarriesExpiry() {
        let expiry = Date(timeIntervalSince1970: 1_755_172_800)
        let payload = PairingPayload(
            version: 1,
            code: PairingCode("K7QN4FMB")!,
            macName: "Luke's MacBook Pro",
            expiresAt: expiry,
            host: "192.168.1.24",
            port: 7333,
            fingerprint: "SHA256:5f2b9c0e"
        )
        let attempt = PairingAttempt.scanned(payload)
        #expect(attempt.observedExpiry == expiry)
        #expect(attempt.macName == "Luke's MacBook Pro")
    }
}

/// The three-way load, and the distinction the out-of-family review corrected.
@Suite("Pairing record store")
struct PairingRecordStoreTests {
    @Test("a missing record is 'never paired', not an error")
    func missingIsNotAnError() async {
        let store = InMemoryPairingStore()
        #expect(await store.load() == .missing)
    }

    @Test("a saved record round-trips")
    func roundTrip() async throws {
        let store = InMemoryPairingStore()
        try await store.save(FixturePairingService.specimenMac)
        guard case let .loaded(mac) = await store.load() else {
            Issue.record("expected a loaded record")
            return
        }
        #expect(mac == FixturePairingService.specimenMac)
    }

    @Test("clearing returns the store to missing, not to unreadable")
    func clearing() async throws {
        let store = InMemoryPairingStore()
        try await store.save(FixturePairingService.specimenMac)
        try await store.clear()
        #expect(await store.load() == .missing)
    }

    @Test("an unreadable record is its own state, distinct from missing")
    func unreadableIsDistinct() async {
        let store = InMemoryPairingStore(.unreadable(detail: "decode failed"))
        let load = await store.load()
        #expect(load != .missing)
        guard case .unreadable = load else {
            Issue.record("expected unreadable")
            return
        }
    }

    /// The record encodes and decodes as itself, including the optional that carries the Partial
    /// state — a `lastSeen` that silently became a non-optional default would delete that state.
    @Test("a record with no last-seen survives a round trip with it still absent")
    func optionalLastSeenSurvives() throws {
        let mac = PairedMac(
            name: "Luke's MacBook Pro",
            pairedAt: Date(timeIntervalSince1970: 1_755_000_000),
            lastSeen: nil,
            host: "192.168.1.24",
            port: 7333,
            fingerprint: "SHA256:5f2b9c0e"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(PairedMac.self, from: encoder.encode(mac))
        #expect(restored.lastSeen == nil)
        #expect(restored == mac)
    }
}

/// Four camera states, and the one that must not borrow the wrong recovery.
@Suite("Camera authorization")
struct CameraAuthorizationTests {
    @Test("only authorized can scan")
    func onlyAuthorizedScans() {
        for state in CameraAuthorization.allCases {
            #expect(state.canScan == (state == .authorized))
        }
    }

    @Test("only not-determined can be usefully asked")
    func onlyNotDeterminedPrompts() {
        for state in CameraAuthorization.allCases {
            #expect(state.canRequest == (state == .notDetermined))
        }
    }

    @Test("asking when the answer is already no changes nothing and shows nothing")
    func askingWhenDeniedIsInert() async {
        for state in [CameraAuthorization.denied, .restricted] {
            let camera = FixtureCameraAuthorization(state)
            #expect(await camera.request() == state)
        }
    }

    @Test("asking when undetermined resolves either way")
    func askingResolves() async {
        #expect(await FixtureCameraAuthorization(.notDetermined, grantsOnRequest: true).request() == .authorized)
        #expect(await FixtureCameraAuthorization(.notDetermined, grantsOnRequest: false).request() == .denied)
    }

    /// The distinction the out-of-family gate raised: restricted is not a stricter denied, and its
    /// recovery is the typed path rather than a trip to Settings the user may be unable to take.
    @Test("restricted has its own copy, and its action is not 'Open iOS Settings'")
    func restrictedHasItsOwnRecovery() {
        #expect(CameraAuthorization.restricted.copyKey == .cameraRestricted)
        #expect(CameraAuthorization.denied.copyKey == .cameraDenied)
        #expect(CameraAuthorization.restricted.copyKey != CameraAuthorization.denied.copyKey)

        let restricted = PairingCopy.entry(.cameraRestricted)
        #expect(restricted.actionLabel == "Enter the code instead")
        #expect(restricted.actionLabel != PairingCopy.entry(.cameraDenied).actionLabel)
        #expect(PairingCopy.entry(.cameraDenied).actionLabel == "Open iOS Settings")
    }

    @Test("the authorized state renders no permission copy — the scanner is the surface")
    func authorizedHasNoCopy() {
        #expect(CameraAuthorization.authorized.copyKey == nil)
    }
}

/// The row subtitle, and the gap it must admit rather than fill.
@Suite("Paired-Mac subtitle")
struct PairingSubtitleTests {
    static let now = Date(timeIntervalSince1970: 1_755_180_000)

    @Test("no last-seen renders 'unknown' rather than a plausible instant")
    func unknownRatherThanGuessed() {
        #expect(PairingSubtitle.lastSeenText(nil, now: Self.now) == "unknown")
    }

    @Test("recent times read as words, singular and plural both correct")
    func wording() {
        #expect(PairingSubtitle.lastSeenText(Self.now.addingTimeInterval(-10), now: Self.now) == "just now")
        #expect(PairingSubtitle.lastSeenText(Self.now.addingTimeInterval(-60), now: Self.now) == "1 minute ago")
        #expect(PairingSubtitle.lastSeenText(Self.now.addingTimeInterval(-120), now: Self.now) == "2 minutes ago")
        #expect(PairingSubtitle.lastSeenText(Self.now.addingTimeInterval(-3600), now: Self.now) == "1 hour ago")
        #expect(PairingSubtitle.lastSeenText(Self.now.addingTimeInterval(-7200), now: Self.now) == "2 hours ago")
        #expect(PairingSubtitle.lastSeenText(Self.now.addingTimeInterval(-86400), now: Self.now) == "1 day ago")
    }

    @Test("the whole subtitle names both facts")
    func fullSubtitle() {
        let mac = PairedMac(
            name: "Luke's MacBook Pro",
            pairedAt: Self.now.addingTimeInterval(-86400 * 2),
            lastSeen: Self.now,
            host: "h", port: 1, fingerprint: "f"
        )
        let text = PairingSubtitle.text(for: mac, now: Self.now)
        #expect(text.contains("paired "))
        #expect(text.hasSuffix("last seen just now"))
    }
}

/// Nothing secret reaches a log line.
@Suite("Pairing log redaction")
struct PairingLogRedactionTests {
    /// The sink is asserted to have *recorded something* first. A test that only checks "the log
    /// does not contain the secret" passes just as happily against a log that recorded nothing at
    /// all, which is the vacuous form of this check.
    @Test("the store logs the shape of a record and never its contents")
    func storeLogsShapeOnly() async throws {
        let sink = CollectingLogSink()
        let store = KeychainPairingStore(
            service: "app.fledgeling.mcprouter.pairing.test",
            account: "paired-mac-test",
            log: ControlLog(sink: sink)
        )

        try? await store.save(FixturePairingService.specimenMac)
        try? await store.clear()

        // Give the actor's queued writes a turn.
        try await Task.sleep(for: .milliseconds(50))
        let written = await sink.joined()

        #expect(!written.isEmpty, "the sink recorded nothing, so this check proved nothing")

        let mac = FixturePairingService.specimenMac
        for secret in [mac.fingerprint, mac.host, "\(mac.port)"] {
            #expect(!written.contains(secret), "'\(secret)' reached a log line: \(written)")
        }
        #expect(!written.contains("K7QN"), "a pairing code reached a log line")
    }

    @Test("the redaction helper reports a length and never the value")
    func redactionHelper() {
        #expect(ControlLog.redacted("K7QN4FMB") == "<8 chars>")
        #expect(ControlLog.redacted(nil) == "<none>")
        #expect(ControlLog.redacted("") == "<none>")
    }
}
