import Foundation

/// The messages on the pairing listener. Nothing else is accepted on it (plan §2.4).
public enum PairingMessage: Sendable, Equatable {
    /// Phone to Mac. `phoneKey` is the DER (SubjectPublicKeyInfo) form of the phone's P-256 public key.
    case request(code: PairingCode, phoneName: String, phoneKey: Data)
    /// Mac to phone, once the code is accepted and the pending record is written.
    case ok(macName: String, phoneId: String)
    /// Mac to phone, when the code is refused. The reason is the Mac's own vocabulary.
    case refused(PairingRefusal)
    /// Phone to Mac, once the phone has stored its record. Confirms the Mac's pending record.
    case ack(phoneId: String)
}

/// What a frame failed on. Kept apart so a size limit is never reported as a parse error.
public enum PairingFrameError: Error, Equatable, Sendable {
    case oversized(length: Int)
    case truncated
    case malformed(detail: String)
    case unknownType(String)
    case unsupportedVersion(found: Int)
}

/// Four-byte big-endian length, then UTF-8 JSON (plan §2.4).
public enum PairingFrame {
    /// The largest body accepted in either direction. A pairing message is a few hundred bytes, so a
    /// larger length prefix is refused before anything is buffered for it.
    public static let maxBodyLength = 4096

    /// The version this build writes. A member of `PairingPayload.supportedVersions`, which is what
    /// the reader checks against.
    public static let version = 1

    public static func encode(_ message: PairingMessage) throws(PairingFrameError) -> Data {
        let encoder = JSONEncoder()
        let body: Data
        do {
            body = try encoder.encode(wire(for: message))
        } catch {
            throw .malformed(detail: "message could not be encoded")
        }
        guard body.count <= maxBodyLength else { throw .oversized(length: body.count) }
        var frame = Data(lengthPrefix(body.count))
        frame.append(body)
        return frame
    }

    public static func decode(_ frame: Data) throws(PairingFrameError) -> PairingMessage {
        guard frame.count >= 4 else { throw .truncated }
        let length = frame.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        // Refused on the prefix alone, so an oversized frame is never buffered or parsed.
        guard length <= maxBodyLength else { throw .oversized(length: length) }
        let body = frame.dropFirst(4)
        guard body.count >= length else { throw .truncated }
        guard body.count == length else { throw .malformed(detail: "bytes after the frame") }

        let wire: Wire
        do {
            wire = try JSONDecoder().decode(Wire.self, from: body)
        } catch {
            throw .malformed(detail: "body is not a pairing message")
        }
        guard PairingPayload.supportedVersions.contains(wire.v) else {
            throw .unsupportedVersion(found: wire.v)
        }
        return try message(from: wire)
    }

    // MARK: Wire

    /// Every field the four messages use, optional where a message does not carry it. A missing
    /// required field is a named failure in `message(from:)`, not a decoding default.
    private struct Wire: Codable {
        let type: String
        let v: Int
        var code: String?
        var phoneName: String?
        var phoneKey: String?
        var macName: String?
        var phoneId: String?
        var reason: String?
        var found: Int?
        var entry: String?
    }

    private static func wire(for message: PairingMessage) -> Wire {
        switch message {
        case let .request(code, phoneName, phoneKey):
            Wire(
                type: "pair.request",
                v: version,
                code: code.canonical,
                phoneName: phoneName,
                phoneKey: phoneKey.base64EncodedString(),
                entry: "scan"
            )
        case let .ok(macName, phoneId):
            Wire(type: "pair.ok", v: version, macName: macName, phoneId: phoneId)
        case let .refused(refusal):
            refusedWire(refusal)
        case let .ack(phoneId):
            Wire(type: "pair.ack", v: version, phoneId: phoneId)
        }
    }

    private static func refusedWire(_ refusal: PairingRefusal) -> Wire {
        var wire = Wire(type: "pair.refused", v: version)
        switch refusal {
        case .notRecognised: wire.reason = "notRecognised"
        case .expired: wire.reason = "expired"
        case .alreadyUsed: wire.reason = "alreadyUsed"
        case .declined: wire.reason = "declined"
        case let .unsupportedVersion(found):
            wire.reason = "unsupportedVersion"
            wire.found = found
        }
        return wire
    }

    private static func message(from wire: Wire) throws(PairingFrameError) -> PairingMessage {
        switch wire.type {
        case "pair.request":
            let code = try pairingCode(wire.code)
            let key = try phoneKey(wire.phoneKey)
            try checkEntry(wire.entry)
            return try .request(code: code, phoneName: required(wire.phoneName, "phoneName"), phoneKey: key)
        case "pair.ok":
            return try .ok(
                macName: required(wire.macName, "macName"),
                phoneId: required(wire.phoneId, "phoneId")
            )
        case "pair.refused":
            return try .refused(refusal(from: wire))
        case "pair.ack":
            return try .ack(phoneId: required(wire.phoneId, "phoneId"))
        default:
            throw .unknownType(wire.type)
        }
    }

    private static func refusal(from wire: Wire) throws(PairingFrameError) -> PairingRefusal {
        switch try required(wire.reason, "reason") {
        case "notRecognised": return .notRecognised
        case "expired": return .expired
        case "alreadyUsed": return .alreadyUsed
        case "declined": return .declined
        case "unsupportedVersion":
            guard let found = wire.found else { throw .malformed(detail: "missing found") }
            return .unsupportedVersion(found: found)
        default:
            throw .malformed(detail: "unknown refusal reason")
        }
    }

    private static func pairingCode(_ text: String?) throws(PairingFrameError) -> PairingCode {
        guard let code = try PairingCode(required(text, "code")) else {
            throw .malformed(detail: "code is not eight Crockford characters")
        }
        return code
    }

    private static func phoneKey(_ text: String?) throws(PairingFrameError) -> Data {
        guard let key = try Data(base64Encoded: required(text, "phoneKey")) else {
            throw .malformed(detail: "phoneKey is not base64")
        }
        return key
    }

    /// `entry` says how the code was typed in. The phone sends `scan`; the router refuses `typed` by name.
    private static func checkEntry(_ text: String?) throws(PairingFrameError) {
        switch try required(text, "entry") {
        case "scan", "typed": return
        default: throw .malformed(detail: "entry is not scan or typed")
        }
    }

    private static func required(_ value: String?, _ field: String) throws(PairingFrameError) -> String {
        guard let value else { throw .malformed(detail: "missing \(field)") }
        return value
    }

    private static func lengthPrefix(_ length: Int) -> [UInt8] {
        [
            UInt8((length >> 24) & 0xFF),
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF)
        ]
    }
}
