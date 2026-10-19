import Foundation
import Testing
@testable import MCPRouterKit

/// The phone's side of the shared wire vectors (`planning/pairing/wire-vectors.json`, plan §2.4). The
/// router reads the same file in `test/pairing-listener.test.ts`.
///
/// A vector is checked here only where it names a phone expectation: `decodes` or `error` for a frame the
/// phone receives, `encodes` for a frame the phone sends. A vector with no phone expectation is the
/// router's to refuse.
@Suite("Pairing wire vectors, phone side")
struct PairingWireVectorsTests {
    @Test("every frame the phone receives decodes, or is refused with the error its vector names")
    func decodesOrRefuses() throws {
        var checked = 0
        for vector in try Vectors.frames() {
            let name = Vectors.name(vector)
            guard let phone = Vectors.expectation(vector, for: "phone") else { continue }
            let frame = try Vectors.frame(vector)

            if let refused = phone["error"] as? String {
                checked += 1
                do {
                    _ = try PairingFrame.decode(frame)
                    Issue.record("\(name) decoded, but its vector says the phone refuses it")
                } catch {
                    #expect(Vectors.errorLabel(error) == Vectors.expectedError(refused, phone), "\(name)")
                }
            } else if let decodes = phone["decodes"] as? String {
                checked += 1
                let message = try PairingFrame.decode(frame)
                #expect(Vectors.label(message) == Vectors.expectedLabel(decodes, phone), "\(name)")
            }
        }
        #expect(checked >= 20, "the vectors were read: \(checked) phone expectations checked")
    }

    @Test("every frame the phone sends is the frame its vector gives, field for field")
    func encodesWhatItSends() throws {
        var checked = 0
        for vector in try Vectors.frames() {
            let name = Vectors.name(vector)
            guard Vectors.expectation(vector, for: "phone")?["encodes"] != nil else { continue }
            checked += 1

            let body = try Vectors.substitutedBody(vector)
            let frame = try PairingFrame.encode(Vectors.message(from: body, name: name))
            let sent = try JSONSerialization.jsonObject(with: frame.dropFirst(4))

            guard let sentObject = sent as? [String: Any] else {
                Issue.record("\(name) did not encode as a JSON object")
                continue
            }
            #expect(NSDictionary(dictionary: sentObject).isEqual(to: body), "\(name)")
        }
        #expect(checked == 2, "the request and the ack both have a phone expectation to encode")
    }

    @Test("the committed certificate renders the fingerprint the vectors carry")
    func fingerprintOfTheKnownCertificate() throws {
        let fingerprint = try #require(Vectors.root()["fingerprint"] as? [String: Any])
        let certificate = try #require(fingerprint["certificate"] as? String)
        let expected = try #require(fingerprint["sha256"] as? String)

        let pem = try String(
            contentsOf: Vectors.repoRoot().appendingPathComponent(certificate),
            encoding: .utf8
        )
        let base64 = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        let der = try #require(Data(base64Encoded: base64))

        #expect(PairingFingerprint.render(certificateDER: der) == expected)
        #expect(expected.count == 64 && expected.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }
}

/// Reads the vector file and turns each vector into the bytes and messages the phone deals in.
enum Vectors {
    enum Failure: Error {
        case noRepoRoot
        case malformed(String)
    }

    static func root() throws -> [String: Any] {
        let url = try repoRoot().appendingPathComponent("planning/pairing/wire-vectors.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let root = object as? [String: Any]
        else { throw Failure.malformed("the vector file is not an object") }
        return root
    }

    static func frames() throws -> [[String: Any]] {
        guard let frames = try root()["frames"] as? [[String: Any]] else {
            throw Failure.malformed("no frames array")
        }
        return frames
    }

    static func name(_ vector: [String: Any]) -> String {
        vector["name"] as? String ?? "unnamed"
    }

    /// A side's expectation, or nil when the vector does not name one for that side.
    static func expectation(_ vector: [String: Any], for side: String) -> [String: Any]? {
        (vector["expect"] as? [String: Any])?[side] as? [String: Any]
    }

    /// The vector's body with `{{code}}` and `{{phoneId}}` replaced, as the JSON object the phone would
    /// write.
    static func substitutedBody(_ vector: [String: Any]) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: substitutedText(vector))
        guard let body = object as? [String: Any]
        else { throw Failure.malformed("\(name(vector)) has no object body") }
        return body
    }

    /// The bytes a vector puts on the wire: the length prefix, the body, then any trailing bytes.
    static func frame(_ vector: [String: Any]) throws -> Data {
        let payload = try substitutedText(vector)
        let declared = vector["declaredLength"] as? Int ?? payload.count
        var frame = rawLengthPrefix(declared)
        frame.append(payload)
        frame.append(Data(((vector["trailing"] as? String) ?? "").utf8))
        return frame
    }

    /// Builds the message a phone sends from a request or ack body.
    static func message(from body: [String: Any], name: String) throws -> PairingMessage {
        switch body["type"] as? String {
        case "pair.request":
            guard let code = PairingCode(body["code"] as? String ?? ""),
                  let phoneName = body["phoneName"] as? String,
                  let phoneKey = Data(base64Encoded: body["phoneKey"] as? String ?? "")
            else { throw Failure.malformed("\(name) is not a request the phone can build") }
            return .request(code: code, phoneName: phoneName, phoneKey: phoneKey)
        case "pair.ack":
            return .ack(phoneId: body["phoneId"] as? String ?? "")
        default:
            throw Failure.malformed("\(name) is not a message the phone sends")
        }
    }

    /// `{{code}}` and `{{phoneId}}` take the fixed values in `placeholders`. The router takes the live ones.
    static func substitutedText(_ vector: [String: Any]) throws -> Data {
        if let raw = vector["rawBody"] as? String { return Data(raw.utf8) }
        guard let body = vector["body"] as? [String: Any]
        else { throw Failure.malformed("\(name(vector)) has no body") }
        let placeholders = try (root()["placeholders"] as? [String: String]) ?? [:]
        let json = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        guard let encoded = String(data: json, encoding: .utf8) else {
            throw Failure.malformed("\(name(vector)) is not UTF-8")
        }
        var text = encoded
        for (key, value) in placeholders {
            text = text.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return Data(text.utf8)
    }

    static func label(_ message: PairingMessage) -> String {
        switch message {
        case .request: "pair.request"
        case .ok: "pair.ok"
        case let .refused(refusal): "pair.refused:" + reasonLabel(refusal)
        case .ack: "pair.ack"
        }
    }

    static func expectedLabel(_ decodes: String, _ phone: [String: Any]) -> String {
        var label = decodes
        if let reason = phone["reason"] as? String { label += ":\(reason)" }
        if let found = phone["found"] as? Int { label += ":\(found)" }
        return label
    }

    static func errorLabel(_ error: PairingFrameError) -> String {
        switch error {
        case .oversized: "oversized"
        case .truncated: "truncated"
        case .malformed: "malformed"
        case let .unknownType(type): "unknownType:\(type)"
        case let .unsupportedVersion(found): "unsupportedVersion:\(found)"
        }
    }

    static func expectedError(_ name: String, _ phone: [String: Any]) -> String {
        if let type = phone["type"] as? String { return "\(name):\(type)" }
        if let found = phone["found"] as? Int { return "\(name):\(found)" }
        return name
    }

    private static func reasonLabel(_ refusal: PairingRefusal) -> String {
        switch refusal {
        case .notRecognised: "notRecognised"
        case .expired: "expired"
        case .alreadyUsed: "alreadyUsed"
        case .declined: "declined"
        case let .unsupportedVersion(found): "unsupportedVersion:\(found)"
        }
    }

    /// Walks up from this file to the directory that holds DESIGN.md, the file only the repository root has.
    static func repoRoot(from filePath: String = #filePath) throws -> URL {
        var dir = URL(fileURLWithPath: filePath).deletingLastPathComponent()
        for _ in 0 ..< 8 {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("DESIGN.md").path) {
                return dir
            }
            dir = dir.deletingLastPathComponent()
        }
        throw Failure.noRepoRoot
    }
}
