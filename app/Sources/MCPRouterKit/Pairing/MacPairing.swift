import Foundation

/// Where a phone would reach this Mac, and the identity it would check on arrival.
///
/// **This type is the honesty control for the whole pairing surface.** `PairingPayload` requires a
/// host, a port and a certificate fingerprint. Today no listener is bound anywhere in either app
/// target, so a Mac that rendered a QR would encode a port nothing answers on and the fingerprint of
/// no certificate — a number nobody observed, written into a machine-readable artifact that another
/// device would then act on. `DESIGN.md` §6 forbids displaying an unobserved number; this would be
/// worse than displaying one, because it is actionable.
///
/// So an endpoint is an **input**, never something the sheet invents, and it is failable against
/// exactly the constraints `PairingPayload.validated` enforces. An endpoint that could not produce a
/// payload the phone can decode cannot be constructed at all, which puts the check one layer earlier
/// than the encoder — where a test can reach it without a QR.
public struct PairingEndpoint: Sendable, Equatable {
    public let host: String
    public let port: Int
    /// The fingerprint of the certificate the listener presents. Stored, never rendered, never
    /// logged — `PairedMac` says the same of its copy, and for the same reason.
    public let fingerprint: String

    public init?(host: String, port: Int, fingerprint: String) {
        guard !host.isEmpty, (1 ... 65535).contains(port), !fingerprint.isEmpty else { return nil }
        self.host = host
        self.port = port
        self.fingerprint = fingerprint
    }
}

/// Whether this Mac can be paired with at all.
///
/// Two cases, and the second is not an error. A build with no listener is not broken — it is a build
/// whose pairing transport has not shipped, which is a fact the surface states rather than hides.
public enum PairingAvailability: Sendable, Equatable {
    case available(PairingEndpoint)
    /// No transport. **The only case a Release build reaches today**, by construction rather than by
    /// configuration: see `ShellPairingFactory`.
    case noEndpoint

    public var endpoint: PairingEndpoint? {
        guard case let .available(endpoint) = self else { return nil }
        return endpoint
    }
}

/// A code this Mac has issued, with the window it is alive for.
///
/// The expiry is **observed** — this Mac chose it — which is what makes a countdown on the Mac
/// legitimate where a countdown on a typed phone code is not (`PairingAttempt.observedExpiry` is nil
/// for exactly that reason).
public struct IssuedPairingCode: Sendable, Equatable {
    public let code: PairingCode
    public let issuedAt: Date
    public let expiresAt: Date

    public init(code: PairingCode, issuedAt: Date, expiresAt: Date) {
        self.code = code
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    public func hasExpired(at now: Date) -> Bool {
        expiresAt <= now
    }

    /// How long is left, or nil once it has gone — nil rather than a negative number, matching
    /// `PairingPayload.timeRemaining(at:)` so the two sides of the same countdown agree.
    public func timeRemaining(at now: Date) -> TimeInterval? {
        let remaining = expiresAt.timeIntervalSince(now)
        return remaining > 0 ? remaining : nil
    }
}

/// Why this Mac refused a pairing request.
///
/// Each case is a decision the Mac took, and each maps to exactly one `PairingOutcome` the phone
/// already knows how to render. A generic failure would collapse four different recoveries into the
/// one message that fits none of them — the argument `PairingOutcome` itself is built on.
public enum PairingRefusal: Sendable, Equatable {
    /// No live code matches. The commonest case, and the one a typo produces.
    case notRecognised
    /// The code was this Mac's and its window has closed.
    case expired
    /// Each code pairs one device once, and this one is spent.
    case alreadyUsed
    /// The phone speaks a version this build does not.
    ///
    /// This is the Mac's mirror of `PairingOutcome.versionMismatch`, and it is the **reachable**
    /// half. The phone-facing outcome is not a Mac surface: the Mac never submits an attempt, so a
    /// Mac screen for it would be dead code dressed as state coverage. A rejection the Mac decides
    /// is a different thing from an outcome the Mac suffers.
    case unsupportedVersion(found: Int)
    /// A human at this Mac dismissed the request. A decision, not an error.
    case declined
}

/// The Mac half of pairing: issuing a code, encoding the payload the phone decodes, and deciding
/// what happens when one comes back.
///
/// **The Mac issues; the phone consumes.** `PairingCode` says so and deliberately ships no generator
/// — a phone that can mint a code is a phone that can pair itself. This is the generator, on the
/// side that is allowed to have one.
///
/// Everything here is pure and takes its clock and its randomness as parameters, so every branch is
/// reachable from a test without a network, a camera or a wall clock.
public enum MacPairing {
    /// How long an issued code lives.
    ///
    /// Five minutes: long enough to walk to the other device and type eight characters, short enough
    /// that a code left on screen in a shared office is not a standing invitation. It is a named
    /// constant rather than a literal because the countdown, the expiry check and the tests must all
    /// read the same number.
    public static let lifetime: TimeInterval = 300

    /// The payload version this Mac emits.
    ///
    /// A stored constant rather than `supportedVersions.max()`, and the difference is not cosmetic.
    /// `max()` returns an optional, so it needs a `?? 1` default — which puts the literal back that
    /// reading the set was meant to remove, and `SWIFT_PRACTICES.md` §2 forbids a silent default on
    /// a value this load-bearing. It also picks the wrong end: the Mac should emit the version every
    /// paired phone can read, which is the floor of the shared set, not the newest thing this build
    /// knows. `MacPairingTests` asserts `PairingPayload.supportedVersions.contains(wireVersion)`, so
    /// the two cannot drift apart silently.
    public static let wireVersion = 1

    // MARK: - Issuing

    /// The eight characters of a code, drawn from Crockford's alphabet.
    ///
    /// Extracted from `issue` so it can be **tested directly**. That matters more than it looks:
    /// `issue` ends in a `preconditionFailure` if the characters are not canonical, and a
    /// precondition is a process trap that no test can catch — so a mutation that widened the
    /// alphabet would crash the test run rather than fail an assertion, which is a gate that cannot
    /// report. Asserting on this function's output catches that mutation as a red test instead.
    ///
    /// Drawn from `PairingCode.alphabet` directly, so `I`, `L`, `O` and `U` cannot appear by
    /// construction. Generating from `A...Z` and filtering afterwards would put the guarantee in a
    /// filter that a later edit can drop.
    static func randomCanonicalCharacters(using generator: inout some RandomNumberGenerator) -> String {
        let alphabet = Array(PairingCode.alphabet)
        var characters = ""
        characters.reserveCapacity(PairingCode.length)
        for _ in 0 ..< PairingCode.length {
            characters.append(alphabet[Int.random(in: 0 ..< alphabet.count, using: &generator)])
        }
        return characters
    }

    /// Mint a code.
    ///
    /// **The expiry is truncated to whole seconds, and that is a wire requirement rather than
    /// tidiness.** `ISO8601Instant.string` — I1's canonical writer — emits `[.withInternetDateTime]`
    /// with no fractional part, while its parser accepts both forms. So an expiry carrying
    /// sub-second precision encodes lossily and decodes to a *different* `Date`, and the
    /// wire-conformance test comparing the decoded payload field for field would fail against a
    /// payload that is otherwise correct. Truncating here makes the round trip exact, and costs
    /// nothing: a pairing window measured to the microsecond is precision nobody asked for.
    public static func issue(
        at now: Date,
        lifetime: TimeInterval = MacPairing.lifetime,
        using generator: inout some RandomNumberGenerator
    ) -> IssuedPairingCode {
        let characters = randomCanonicalCharacters(using: &generator)
        // `canonical:` rather than the lenient parser: these characters came from the alphabet, so a
        // failure here would mean the alphabet and the validator disagree, which is a defect rather
        // than a user's typo. Falling back to a fixed code would hide it, so the precondition stands
        // — and `randomCanonicalCharacters` is tested directly so nothing depends on reaching it.
        guard let code = PairingCode(canonical: characters) else {
            preconditionFailure("the generator produced characters outside PairingCode.alphabet")
        }
        let expiry = Date(timeIntervalSince1970: (now.timeIntervalSince1970 + lifetime).rounded(.down))
        return IssuedPairingCode(code: code, issuedAt: now, expiresAt: expiry)
    }

    public static func issue(
        at now: Date,
        lifetime: TimeInterval = MacPairing.lifetime
    ) -> IssuedPairingCode {
        var generator = SystemRandomNumberGenerator()
        return issue(at: now, lifetime: lifetime, using: &generator)
    }

    // MARK: - The payload the phone decodes

    /// Build the payload for an issued code.
    ///
    /// Takes an endpoint rather than three strings, so there is no call site that can supply a host
    /// without a fingerprint.
    public static func payload(
        for issued: IssuedPairingCode,
        endpoint: PairingEndpoint,
        macName: String
    ) -> PairingPayload {
        PairingPayload(
            version: wireVersion,
            code: issued.code,
            macName: macName,
            expiresAt: issued.expiresAt,
            host: endpoint.host,
            port: endpoint.port,
            fingerprint: endpoint.fingerprint
        )
    }

    /// The exact text the QR carries.
    ///
    /// Hand-built rather than `JSONEncoder`-with-a-Codable-struct on purpose: `PairingPayload`
    /// decodes an envelope whose keys are `t`, `v`, `code`, `mac`, `exp`, `host`, `port`, `fp`, and
    /// an encoder driven by a *separate* struct is free to drift from the decoder that has already
    /// shipped. The keys are written here beside the decoder's own `Body`, and
    /// `MacPairingWireTests` decodes what this produces through `PairingPayload.decode` rather than
    /// comparing strings — so agreement is proven over the bytes, not asserted over a literal.
    public static func encode(_ payload: PairingPayload) throws -> String {
        let object: [String: Any] = [
            "t": PairingPayload.discriminator,
            "v": payload.version,
            "code": payload.code.canonical,
            "mac": payload.macName,
            "exp": ISO8601Instant.string(from: payload.expiresAt),
            "host": payload.host,
            "port": payload.port,
            "fp": payload.fingerprint
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw PairingPayloadError.malformedPayload(detail: "payload is not UTF-8")
        }
        return text
    }

    // MARK: - Deciding

    /// What this Mac does with a submitted code.
    ///
    /// `live` is the code currently on screen, or nil when none has been issued. `spent` is the set
    /// of codes already used — one code pairs one device once, and this Mac is the issuer, so this
    /// is where that is enforced rather than trusted to the caller. Typed as `Set<PairingCode>`
    /// rather than `Set<String>`: a stringly set invites a caller to insert an unnormalised or
    /// unvalidated string that then never matches, which would silently turn "already used" back
    /// into "not recognised".
    public static func decide(
        submitted: PairingCode,
        version: Int,
        live: IssuedPairingCode?,
        spent: Set<PairingCode>,
        at now: Date
    ) -> PairingRefusal? {
        guard PairingPayload.supportedVersions.contains(version) else {
            return .unsupportedVersion(found: version)
        }
        // Spent is checked before liveness: a code that was used and then re-submitted must say so,
        // rather than reporting "not recognised" once the next code has replaced it on screen. The
        // two send the user to different places.
        guard !spent.contains(submitted) else { return .alreadyUsed }
        guard let live, live.code == submitted else { return .notRecognised }
        guard !live.hasExpired(at: now) else { return .expired }
        return nil
    }

    /// The outcome the phone is told, for a refusal this Mac decided.
    ///
    /// Mapped in one place so a refusal cannot be reported as one thing on the Mac and another on
    /// the phone — `DESIGN.md` §6 asks for one name per state across both devices.
    ///
    /// `unsupportedVersion`'s `found` is deliberately dropped here: `PairingOutcome.versionMismatch`
    /// carries no version because the phone cannot act on the number — the only recovery is to
    /// update. The value stays on the Mac's own `PairingRefusal`, which is what the Mac's surface
    /// renders.
    public static func outcome(for refusal: PairingRefusal, macName: String?) -> PairingOutcome {
        switch refusal {
        case .notRecognised: .notRecognised
        case .expired: .expired
        case .alreadyUsed: .alreadyUsed
        case .unsupportedVersion: .versionMismatch(macName: macName)
        case .declined: .refused(macName: macName)
        }
    }
}
