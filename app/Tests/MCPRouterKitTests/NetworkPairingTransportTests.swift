import Foundation
import Testing
@testable import MCPRouterKit

/// The production transport's two decisions that can be made without a socket: whether a presented
/// certificate is the one the QR named, and whether a length prefix is worth reading a body for.
///
/// The TLS handshake and the socket are not exercised here. A host test of the handshake would need
/// a private key for a certificate the Mac presents, and none is committed. The loopback run recorded
/// with this item covers that path instead.
@Suite("Network pairing transport")
struct NetworkPairingTransportTests {
    /// The committed router certificate, as DER. Its fingerprint is `LivePairingServiceTests.fingerprint`.
    static func certificateDER() throws -> Data {
        let pem = try String(
            contentsOf: Vectors.repoRoot().appendingPathComponent("planning/pairing/wire-test-cert.pem"),
            encoding: .utf8
        )
        let base64 = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        return try #require(Data(base64Encoded: base64))
    }

    @Test("a certificate whose fingerprint is the one the QR named is accepted")
    func pinAcceptsTheNamedCertificate() throws {
        let der = try Self.certificateDER()
        let fingerprint = LivePairingServiceTests.fingerprint
        #expect(PairingFingerprint.matches(certificateDER: der, expecting: fingerprint))
    }

    @Test("a certificate with another fingerprint is refused")
    func pinRefusesAnotherCertificate() throws {
        let der = try Self.certificateDER()
        var other = der
        other.append(0x00)
        let fingerprint = LivePairingServiceTests.fingerprint
        #expect(!PairingFingerprint.matches(certificateDER: other, expecting: fingerprint))
    }

    @Test("the pin compares the §2.4 form exactly, so a prefixed or upper-case value never matches")
    func pinIsExact() throws {
        let der = try Self.certificateDER()
        let fingerprint = LivePairingServiceTests.fingerprint
        #expect(!PairingFingerprint.matches(certificateDER: der, expecting: "SHA256:" + fingerprint))
        #expect(!PairingFingerprint.matches(certificateDER: der, expecting: fingerprint.uppercased()))
        #expect(!PairingFingerprint.matches(certificateDER: der, expecting: String(fingerprint.dropLast())))
    }

    @Test("a length prefix over the limit is refused before any body is requested")
    func oversizedPrefixReadsNoBody() async throws {
        var requests: [Int] = []
        let length = PairingFrame.maxBodyLength + 1
        let prefix = Data([0x00, 0x00, 0x10, 0x01])
        #expect(length == 4097)

        await #expect(throws: PairingFrameError.oversized(length: length)) {
            try await PairingFrame.readFrame { count in
                requests.append(count)
                return prefix
            }
        }
        #expect(requests == [4], "the body was requested after an oversized prefix: \(requests)")
    }

    @Test("a frame at the limit is read in full, prefix first")
    func frameAtTheLimitIsRead() async throws {
        var requests: [Int] = []
        let body = Data(repeating: 0x20, count: PairingFrame.maxBodyLength)
        let prefix = Data([0x00, 0x00, 0x10, 0x00])

        let frame = try await PairingFrame.readFrame { count in
            requests.append(count)
            return count == 4 ? prefix : body
        }
        #expect(requests == [4, PairingFrame.maxBodyLength])
        #expect(frame == prefix + body)
    }
}
