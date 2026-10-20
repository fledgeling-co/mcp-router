import Foundation
import Testing
@testable import MCPRouterKit

/// G1 on Swift (plan-pairing-typed-spake2 §4): the four RFC 9382 Appendix B vectors through the
/// transcript and key schedule. The vectors are `planning/pairing/spake2-rfc9382-vectors.json`, which
/// the Node side reads too. The P-256 points are inputs here, so no curve arithmetic runs on the phone.
@Suite("SPAKE2 transcript and key schedule, G1 on Swift")
struct SpakeTranscriptTests {
    @Test("each RFC 9382 vector reproduces TT, HASH(TT), Ke, Ka, both Kc keys and both confirmations")
    func rfcVectors() throws {
        let vectors = try SpakeVector.load()
        #expect(vectors.count == 4, "the four published vectors were read: \(vectors.count)")

        for vector in vectors {
            let tt = try SpakeTranscript.transcript(vector.inputs(w: vector.w))
            #expect(tt == vector.tt, "\(vector.name): TT")

            let schedule = SpakeTranscript.keySchedule(transcript: tt, aad: Data())
            #expect(schedule.ke + schedule.ka == vector.hashTT, "\(vector.name): HASH(TT)")
            #expect(schedule.ke == vector.ke, "\(vector.name): Ke")
            #expect(schedule.ka == vector.ka, "\(vector.name): Ka")
            #expect(schedule.kcA == vector.kcA, "\(vector.name): KcA")
            #expect(schedule.kcB == vector.kcB, "\(vector.name): KcB")

            let confA = SpakeTranscript.confirmation(key: schedule.kcA, transcript: tt)
            let confB = SpakeTranscript.confirmation(key: schedule.kcB, transcript: tt)
            #expect(confA == vector.confA, "\(vector.name): A confirmation")
            #expect(confB == vector.confB, "\(vector.name): B confirmation")
        }
    }

    /// RFC 9382 §3.3 encodes w big-endian, padded to the length of p (32 bytes here). A w whose
    /// leading zeros were dropped must give the same TT as the padded one. A w longer than 32 bytes
    /// is refused.
    @Test("w is padded to 32 bytes, and a longer w is refused")
    func wIsPaddedToThirtyTwoBytes() throws {
        let vector = try #require(try SpakeVector.load().first)
        func transcript(w: Data) throws -> Data {
            try SpakeTranscript.transcript(vector.inputs(w: w))
        }

        let padded = Data(repeating: 0x00, count: 1) + vector.w.suffix(31)
        #expect(try transcript(w: vector.w.suffix(31)) == transcript(w: padded), "a short w is padded")
        #expect(throws: SpakeTranscript.Failure.scalarLongerThanThirtyTwoBytes(33)) {
            try transcript(w: Data(repeating: 0x01, count: 33))
        }
    }
}

/// One RFC 9382 Appendix B vector as the shared file carries it.
private struct SpakeVector {
    enum Failure: Error {
        case malformed(String)
    }

    let name: String
    let identityA: String
    let identityB: String
    let pA: Data
    let pB: Data
    let k: Data
    let tt: Data
    let hashTT: Data
    let ke: Data
    let ka: Data
    let kcA: Data
    let kcB: Data
    let confA: Data
    let confB: Data
    let w: Data

    func inputs(w: Data) -> SpakeTranscript.Inputs {
        SpakeTranscript.Inputs(
            identityA: Data(identityA.utf8),
            identityB: Data(identityB.utf8),
            pA: pA,
            pB: pB,
            k: k,
            w: w
        )
    }

    static func load() throws -> [SpakeVector] {
        let url = try Vectors.repoRoot()
            .appendingPathComponent("planning/pairing/spake2-rfc9382-vectors.json")
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        return try file.vectors.map { raw in
            try SpakeVector(
                name: raw.name,
                identityA: raw.identityA,
                identityB: raw.identityB,
                pA: bytes(raw.pA, raw.name),
                pB: bytes(raw.pB, raw.name),
                k: bytes(raw.k, raw.name),
                tt: bytes(raw.tt, raw.name),
                hashTT: bytes(raw.hashTT, raw.name),
                ke: bytes(raw.ke, raw.name),
                ka: bytes(raw.ka, raw.name),
                kcA: bytes(raw.kcA, raw.name),
                kcB: bytes(raw.kcB, raw.name),
                confA: bytes(raw.confA, raw.name),
                confB: bytes(raw.confB, raw.name),
                w: bytes(raw.w, raw.name)
            )
        }
    }

    private struct File: Decodable {
        let vectors: [RawVector]
    }

    /// Lower-case hex, no prefix, as the vector file writes it. A malformed value is a failure of the
    /// file, not a value to compare against.
    private static func bytes(_ hex: String, _ name: String) throws -> Data {
        guard hex.count.isMultiple(of: 2) else {
            throw Failure.malformed("\(name) has an odd number of hex digits")
        }
        var out = Data()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index ..< next], radix: 16) else {
                throw Failure.malformed("\(name) has a value that is not hex")
            }
            out.append(byte)
            index = next
        }
        return out
    }
}

/// The file's keys are the RFC's own labels (`A`, `K`, `Ke`, ...), mapped onto Swift names here.
private struct RawVector: Decodable {
    let name: String
    let identityA: String
    let identityB: String
    let w: String
    let pA: String
    let pB: String
    let k: String
    let tt: String
    let hashTT: String
    let ke: String
    let ka: String
    let kcA: String
    let kcB: String
    let confA: String
    let confB: String

    enum CodingKeys: String, CodingKey {
        case name, w, pA, pB, hashTT, confA, confB
        case identityA, identityB, k = "K", tt = "TT"
        case ke = "Ke", ka = "Ka", kcA = "KcA", kcB = "KcB"
    }
}
