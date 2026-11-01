import Foundation

/// The body `POST /pairing/codes` and `GET /pairing/state` carry for one code, as the router writes it.
///
/// Internal, because the protocol hands callers an `IssuedPairingCode` and nothing outside the Kit
/// needs the wire form. The instants are the router's own whole-second `Z` form, which
/// `ISO8601Instant` reads; a value that does not parse is refused rather than defaulted, since a
/// countdown built on a guessed expiry would be a number nobody observed.
struct PairingCodeWire: Codable {
    let code: PairingCode
    let issuedAt: Date
    let expiresAt: Date

    private enum CodingKeys: String, CodingKey {
        case code, issuedAt, expiresAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .code)
        guard let code = PairingCode(canonical: text) else {
            throw DecodingError.dataCorruptedError(
                forKey: .code,
                in: container,
                debugDescription: "the router sent a code that is not canonical Crockford Base32"
            )
        }
        self.code = code
        issuedAt = try Self.instant(in: container, forKey: .issuedAt)
        expiresAt = try Self.instant(in: container, forKey: .expiresAt)
    }

    /// Writes the router's own form, so a body that round-trips through this type keeps every key it
    /// was sent with. The instants go out whole-second, as `ISO8601Instant.string` writes them.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code.canonical, forKey: .code)
        try container.encode(ISO8601Instant.string(from: issuedAt), forKey: .issuedAt)
        try container.encode(ISO8601Instant.string(from: expiresAt), forKey: .expiresAt)
    }

    private static func instant(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Date {
        let text = try container.decode(String.self, forKey: key)
        guard let date = ISO8601Instant.parse(text) else {
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "the router sent a value that is not an ISO-8601 instant"
            )
        }
        return date
    }

    var issued: IssuedPairingCode {
        IssuedPairingCode(code: code, issuedAt: issuedAt, expiresAt: expiresAt)
    }
}

/// The `listener` member of `GET /pairing/state`, as the router writes it. Every key is required and read
/// by its own type: a router that does not say whether its listener is bound is not one the sheet can read.
/// `port` is written even when it is null, because the router writes it that way while the listener is off.
struct PairingListenerWire: Codable {
    let enabled: Bool
    let port: Int?
    let advertising: Bool
    let host: String?
    let fingerprint: String?

    var listener: PairingListener {
        PairingListener(
            enabled: enabled,
            port: port,
            advertising: advertising,
            host: host,
            fingerprint: fingerprint
        )
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, port, advertising, host, fingerprint
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(port, forKey: .port)
        try container.encode(advertising, forKey: .advertising)
        try container.encodeIfPresent(host, forKey: .host)
        try container.encodeIfPresent(fingerprint, forKey: .fingerprint)
    }
}

/// One phone whose request the router has accepted and is waiting to hear acknowledged, as `awaitingAck`
/// lists it. The sheet does not show these. They are decoded so every key the router sends has a field, and
/// the time is read by the same instant rule as the code's expiry.
struct PairingAwaitingAckWire: Codable {
    let phoneName: String
    let requestedAt: Date

    private enum CodingKeys: String, CodingKey {
        case phoneName, requestedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        phoneName = try container.decode(String.self, forKey: .phoneName)
        let text = try container.decode(String.self, forKey: .requestedAt)
        guard let date = ISO8601Instant.parse(text) else {
            throw DecodingError.dataCorruptedError(
                forKey: .requestedAt,
                in: container,
                debugDescription: "the router sent a value that is not an ISO-8601 instant"
            )
        }
        requestedAt = date
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(phoneName, forKey: .phoneName)
        try container.encode(ISO8601Instant.string(from: requestedAt), forKey: .requestedAt)
    }
}

/// The body `GET /pairing/state` answers: the live code, or `null` once there is none to pair with;
/// the phones awaiting an ack; and whether the router's phone listener is bound.
struct PairingStateWire: Codable {
    let code: PairingCodeWire?
    let awaitingAck: [PairingAwaitingAckWire]
    let listener: PairingListenerWire

    var state: PairingState {
        PairingState(code: code?.issued, listener: listener.listener)
    }

    private enum CodingKeys: String, CodingKey {
        case code, awaitingAck, listener
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(code, forKey: .code)
        try container.encode(awaitingAck, forKey: .awaitingAck)
        try container.encode(listener, forKey: .listener)
    }
}

/// The body `DELETE /pairing/codes` answers: whether a live code was there to revoke.
struct PairingRevokeWire: Codable {
    let revoked: Bool
}
