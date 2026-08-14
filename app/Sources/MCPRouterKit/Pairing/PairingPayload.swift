import Foundation

/// What went wrong reading a scanned code, kept as three distinct outcomes rather than one.
///
/// The distinction is not pedantry — the three have different copy and different recoveries. "That
/// isn't an MCP Router code" sends you to the right screen on your Mac; "your Mac is running an
/// older version" sends you to update it; "that code couldn't be read" sends you to ask for a new
/// one. Collapsing them produces the one message that fits none of the three, and a user who
/// retries the thing that cannot work.
public enum PairingPayloadError: Error, Equatable, Sendable {
    /// Not our QR code at all — a URL, a Wi-Fi code, another app's.
    case notAPairingCode
    /// Our envelope, a version this build does not speak.
    case unsupportedVersion(found: Int)
    /// Our envelope and our version, but the body did not hold up.
    case malformedPayload(detail: String)
}

/// The QR payload the Mac encodes, decoded in two passes.
///
/// **Envelope first, then the versioned body.** A single `Codable` struct would collapse all three
/// failures above into "decoding failed", because `JSONDecoder` cannot tell you *why* it stopped in
/// terms the user needs. So the envelope — the discriminator and the version — is read on its own,
/// and only then is the body decoded against a version we know.
///
/// Nothing here is `try?`-and-default. A field that is absent is a failure with a name, never a
/// zero value that flows on to be rendered (`SWIFT_PRACTICES.md` §2).
public struct PairingPayload: Sendable, Equatable {
    /// The discriminator. A QR that does not carry exactly this is not ours.
    public static let discriminator = "mcp-router-pair"

    /// The payload versions this build speaks. A closed set, so an unknown one is a named outcome.
    public static let supportedVersions: Set<Int> = [1]

    public let version: Int
    public let code: PairingCode
    public let macName: String
    /// The **only** expiry the phone ever observes. `DESIGN.md` §6 forbids displaying a number the
    /// system has not observed, so a countdown exists on the scanned path and nowhere else.
    public let expiresAt: Date
    /// Carried for the transport M6 brings. Stored, never rendered, never logged.
    public let host: String
    public let port: Int
    public let fingerprint: String

    // MARK: Decoding

    /// Just enough to decide which of the three failures applies.
    private struct Envelope: Decodable {
        let t: String?
        let v: Int?
    }

    private struct Body: Decodable {
        let code: String
        let mac: String
        let exp: String
        let host: String
        let port: Int
        let fp: String
    }

    /// Decode the text a QR scanner handed back.
    public static func decode(_ text: String) throws(PairingPayloadError) -> PairingPayload {
        guard let data = text.data(using: .utf8) else { throw .notAPairingCode }

        // Pass 1 — is this ours at all?
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            // Unparseable JSON is indistinguishable from "some other app's QR", and that is the
            // honest reading: we cannot claim a version problem for bytes we could not parse.
            throw .notAPairingCode
        }
        guard envelope.t == discriminator else { throw .notAPairingCode }

        // Pass 2 — do we speak this version?
        guard let version = envelope.v else { throw .malformedPayload(detail: "no version") }
        guard supportedVersions.contains(version) else { throw .unsupportedVersion(found: version) }

        // Pass 3 — the body, every field required.
        let body: Body
        do {
            body = try JSONDecoder().decode(Body.self, from: data)
        } catch let DecodingError.keyNotFound(key, _) {
            throw .malformedPayload(detail: "missing \(key.stringValue)")
        } catch let DecodingError.typeMismatch(_, context) {
            throw .malformedPayload(
                detail: "wrong type for \(context.codingPath.map(\.stringValue).joined(separator: "."))"
            )
        } catch {
            throw .malformedPayload(detail: "unreadable body")
        }

        guard let code = PairingCode(body.code) else {
            throw .malformedPayload(detail: "code is not eight Crockford characters")
        }
        // An explicit ISO-8601 parse rather than `.iso8601`, which rejects the fractional-second
        // form a JavaScript `toISOString()` produces — and the Mac side is TypeScript today.
        guard let expires = ISO8601Instant.parse(body.exp) else {
            throw .malformedPayload(detail: "expiry is not an ISO-8601 instant")
        }
        guard !body.mac.isEmpty else { throw .malformedPayload(detail: "empty mac name") }
        guard !body.host.isEmpty else { throw .malformedPayload(detail: "empty host") }
        guard (1 ... 65535).contains(body.port) else { throw .malformedPayload(detail: "port out of range") }
        guard !body.fp.isEmpty else { throw .malformedPayload(detail: "empty fingerprint") }

        return PairingPayload(
            version: version,
            code: code,
            macName: body.mac,
            expiresAt: expires,
            host: body.host,
            port: body.port,
            fingerprint: body.fp
        )
    }

    public init(
        version: Int,
        code: PairingCode,
        macName: String,
        expiresAt: Date,
        host: String,
        port: Int,
        fingerprint: String
    ) {
        self.version = version
        self.code = code
        self.macName = macName
        self.expiresAt = expiresAt
        self.host = host
        self.port = port
        self.fingerprint = fingerprint
    }

    /// Whether the code is already dead by the phone's clock.
    public func hasExpired(at now: Date) -> Bool { expiresAt <= now }

    /// How long is left, or nil once it has gone. Nil rather than a negative number, because a
    /// countdown reading `-0:12` is a number the system observed and then rendered as nonsense.
    public func timeRemaining(at now: Date) -> TimeInterval? {
        let remaining = expiresAt.timeIntervalSince(now)
        return remaining > 0 ? remaining : nil
    }
}

/// ISO-8601 parsing that tolerates both forms the two routers emit.
///
/// `JSONDecoder.DateDecodingStrategy.iso8601` uses `ISO8601DateFormatter`'s default options, which
/// **reject** `2026-08-14T09:41:00.000Z` — the exact string `Date.prototype.toISOString()` produces,
/// and therefore the exact string today's TypeScript router would send. Accepting only the form our
/// own Swift encoder happens to emit is how a decoder passes every test in this repo and fails
/// against the shipping product.
public enum ISO8601Instant {
    public static func parse(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    /// The canonical form this app writes, used by the fixtures.
    public static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
