import Foundation
import Testing
@testable import MCPRouterKit

/// The two-pass decode, and the three failures it keeps apart.
///
/// The reason this suite is long is that the collapse it guards against is cheap to reintroduce: a
/// single `Codable` struct and one `catch` would pass a "decoding works" test and quietly turn
/// "your Mac is running an older version" into "that code couldn't be read".
@Suite("QR payload")
struct PairingPayloadTests {
    static func json(
        t: String = "mcp-router-pair",
        v: Int? = 1,
        code: String = "K7QN-4FMB",
        mac: String = "Luke's MacBook Pro",
        exp: String = "2099-01-01T00:00:00Z",
        host: String = "192.168.1.24",
        port: Int = 7333,
        fp: String = "SHA256:5f2b9c0e",
        omit: String? = nil
    ) -> String {
        var fields: [(String, String)] = [
            ("t", "\"\(t)\""),
            ("code", "\"\(code)\""),
            ("mac", "\"\(mac)\""),
            ("exp", "\"\(exp)\""),
            ("host", "\"\(host)\""),
            ("port", "\(port)"),
            ("fp", "\"\(fp)\"")
        ]
        if let v { fields.insert(("v", "\(v)"), at: 1) }
        if let omit { fields.removeAll { $0.0 == omit } }
        return "{" + fields.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ",") + "}"
    }

    @Test("a well-formed payload decodes into every field")
    func decodesFully() throws {
        let payload = try PairingPayload.decode(Self.json())
        #expect(payload.version == 1)
        #expect(payload.code.canonical == "K7QN4FMB")
        #expect(payload.macName == "Luke's MacBook Pro")
        #expect(payload.host == "192.168.1.24")
        #expect(payload.port == 7333)
        #expect(payload.fingerprint == "SHA256:5f2b9c0e")
    }

    // MARK: The three failures, kept apart

    @Test("another app's QR is 'not a pairing code', not a version problem")
    func foreignQR() {
        #expect(throws: PairingPayloadError.notAPairingCode) {
            try PairingPayload.decode("https://example.com")
        }
        #expect(throws: PairingPayloadError.notAPairingCode) {
            try PairingPayload.decode(Self.json(t: "some-other-app"))
        }
        // Unparseable bytes cannot honestly be called a version problem — we never read a version.
        #expect(throws: PairingPayloadError.notAPairingCode) {
            try PairingPayload.decode("{not json at all")
        }
    }

    @Test("our envelope with an unknown version is a version mismatch")
    func unknownVersion() {
        #expect(throws: PairingPayloadError.unsupportedVersion(found: 2)) {
            try PairingPayload.decode(Self.json(v: 2))
        }
    }

    @Test("our envelope and version with a broken body is malformed, and says which field")
    func malformedBody() throws {
        for field in ["code", "mac", "exp", "host", "port", "fp"] {
            let error = #expect(throws: PairingPayloadError.self) {
                try PairingPayload.decode(Self.json(omit: field))
            }
            guard case let .malformedPayload(detail) = error else {
                Issue.record("\(field) produced \(String(describing: error)), not malformedPayload")
                continue
            }
            #expect(detail.contains(field), "detail '\(detail)' does not name \(field)")
        }
    }

    @Test("a missing version is malformed rather than a mismatch — we have no version to blame")
    func missingVersion() {
        let error = #expect(throws: PairingPayloadError.self) {
            try PairingPayload.decode(Self.json(v: nil))
        }
        guard case .malformedPayload = error else {
            Issue.record("expected malformedPayload, got \(String(describing: error))")
            return
        }
    }

    @Test("a code that is not eight Crockford characters is malformed")
    func badCode() {
        let error = #expect(throws: PairingPayloadError.self) {
            try PairingPayload.decode(Self.json(code: "SHORT"))
        }
        guard case .malformedPayload = error else {
            Issue.record("expected malformedPayload, got \(String(describing: error))")
            return
        }
    }

    @Test("empty strings and an out-of-range port are refused rather than carried")
    func emptyFieldsRefused() {
        for payload in [
            Self.json(mac: ""),
            Self.json(host: ""),
            Self.json(fp: ""),
            Self.json(port: 0),
            Self.json(port: 70000)
        ] {
            #expect(throws: PairingPayloadError.self) { try PairingPayload.decode(payload) }
        }
    }

    // MARK: The expiry

    /// The trap this catches is not hypothetical: `JSONDecoder`'s `.iso8601` strategy rejects the
    /// fractional-second form, which is exactly what `Date.prototype.toISOString()` emits — and the
    /// Mac side is TypeScript today. A decoder that only accepts what our own encoder writes passes
    /// every test here and fails against the shipping product.
    @Test("both ISO-8601 forms parse, including the fractional seconds JavaScript emits")
    func iso8601Forms() throws {
        let plain = try PairingPayload.decode(Self.json(exp: "2099-01-01T00:00:00Z"))
        let fractional = try PairingPayload.decode(Self.json(exp: "2099-01-01T00:00:00.000Z"))
        #expect(plain.expiresAt == fractional.expiresAt)
    }

    @Test("a non-instant expiry is malformed")
    func badExpiry() {
        let error = #expect(throws: PairingPayloadError.self) {
            try PairingPayload.decode(Self.json(exp: "next Tuesday"))
        }
        guard case .malformedPayload = error else {
            Issue.record("expected malformedPayload, got \(String(describing: error))")
            return
        }
    }

    @Test("expiry is judged against a clock, and a dead code reports no remaining time")
    func expiryBoundary() throws {
        let payload = try PairingPayload.decode(Self.json(exp: "2026-08-14T12:00:00Z"))
        let before = Date(timeIntervalSince1970: 1_786_708_740) // 11:59:00Z
        let after = Date(timeIntervalSince1970: 1_786_708_860) // 12:01:00Z

        #expect(payload.hasExpired(at: before) == false)
        #expect(payload.hasExpired(at: after))
        #expect(payload.timeRemaining(at: before) == 60)
        // Nil rather than a negative number: a countdown reading "-0:12" is a number the system
        // observed and then rendered as nonsense.
        #expect(payload.timeRemaining(at: after) == nil)
        #expect(payload.hasExpired(at: payload.expiresAt), "the boundary instant itself is expired")
    }
}
