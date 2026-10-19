import Foundation
import Testing
@testable import MCPRouterKit

/// The frame codec for the pairing wire (plan §2.4).
@Suite("Pairing frame codec")
struct PairingFrameCodecTests {
    static let code = "K7QN4FMB"

    static func messages() throws -> [PairingMessage] {
        guard let pairingCode = PairingCode(code) else { throw CodecFixtureError.badCode }
        let key = Data(repeating: 4, count: 65)
        return [
            .request(code: pairingCode, phoneName: "Luke's iPhone", phoneKey: key),
            .ok(macName: "Luke's MacBook Pro", phoneId: "phone-1"),
            .refused(.notRecognised),
            .refused(.expired),
            .refused(.alreadyUsed),
            .refused(.unsupportedVersion(found: 2)),
            .refused(.declined),
            .ack(phoneId: "phone-1")
        ]
    }

    @Test("every message survives an encode and decode")
    func roundTrip() throws {
        for message in try Self.messages() {
            let frame = try PairingFrame.encode(message)
            #expect(try PairingFrame.decode(frame) == message, "\(message)")
        }
    }

    @Test("the length prefix is big-endian and counts the body alone")
    func lengthPrefix() throws {
        let frame = try PairingFrame.encode(.ack(phoneId: "phone-1"))
        let prefix = Array(frame.prefix(4))
        let length = prefix.reduce(0) { ($0 << 8) | Int($1) }
        #expect(length == frame.count - 4)
        #expect(frame.count > 4)
    }

    @Test("a body over the limit is refused when encoded")
    func oversizedEncode() throws {
        guard let pairingCode = PairingCode(Self.code) else { throw CodecFixtureError.badCode }
        let name = String(repeating: "x", count: PairingFrame.maxBodyLength + 1)
        let message = PairingMessage.request(
            code: pairingCode,
            phoneName: name,
            phoneKey: Data(repeating: 4, count: 65)
        )
        #expect(throws: PairingFrameError.self) {
            try PairingFrame.encode(message)
        }
    }

    @Test("a length prefix over the limit is refused before the body is read")
    func oversizedDecode() {
        let length = PairingFrame.maxBodyLength + 1
        var frame = rawLengthPrefix(length)
        frame.append(Data(repeating: 0x20, count: 16))
        #expect(throws: PairingFrameError.oversized(length: length)) {
            try PairingFrame.decode(frame)
        }
    }

    @Test("a frame shorter than its prefix says is truncated")
    func truncated() {
        let frame = rawFrame(body: #"{"type":"pair.ack","v":1,"phoneId":"p"}"#).dropLast(3)
        #expect(throws: PairingFrameError.truncated) {
            try PairingFrame.decode(frame)
        }
    }

    @Test("fewer than four bytes is truncated, not malformed")
    func truncatedPrefix() {
        #expect(throws: PairingFrameError.truncated) {
            try PairingFrame.decode(Data([0, 0]))
        }
    }

    @Test("bytes after one complete frame are malformed")
    func trailingBytes() {
        var frame = rawFrame(body: #"{"type":"pair.ack","v":1,"phoneId":"p"}"#)
        frame.append(0x7D)
        #expect(throws: PairingFrameError.self) {
            try PairingFrame.decode(frame)
        }
    }

    @Test("a message type this build does not know is named")
    func unknownType() {
        #expect(throws: PairingFrameError.unknownType("pair.bogus")) {
            try PairingFrame.decode(rawFrame(body: #"{"type":"pair.bogus","v":1}"#))
        }
    }

    @Test("a version outside the supported set is a named refusal, not a parse error")
    func badVersion() {
        #expect(throws: PairingFrameError.unsupportedVersion(found: 9)) {
            try PairingFrame.decode(rawFrame(body: #"{"type":"pair.ack","v":9,"phoneId":"p"}"#))
        }
    }

    @Test("a body that is not JSON is malformed")
    func notJSON() {
        #expect(throws: PairingFrameError.self) {
            try PairingFrame.decode(rawFrame(body: "not json"))
        }
    }

    @Test("a request whose code is not eight Crockford characters is malformed")
    func badCode() {
        let head = #"{"type":"pair.request","v":1,"code":"nope","phoneName":"x","phoneKey":"AA==""#
        let body = head + #","entry":"scan"}"#
        #expect(throws: PairingFrameError.self) {
            try PairingFrame.decode(rawFrame(body: body))
        }
    }

    @Test("a request must say how its code was entered, scan or typed, and anything else is malformed")
    func entryIsRequired() {
        let head = #"{"type":"pair.request","v":1,"code":"K7QN4FMB","phoneName":"x","phoneKey":"AA==""#
        let missing = head + "}"
        let unknown = head + #","entry":"nope"}"#
        #expect(throws: PairingFrameError.self) {
            try PairingFrame.decode(rawFrame(body: missing))
        }
        #expect(throws: PairingFrameError.self) {
            try PairingFrame.decode(rawFrame(body: unknown))
        }
    }

    @Test("a version refusal without the version it refused is malformed")
    func refusalWithoutFound() {
        let body = #"{"type":"pair.refused","v":1,"reason":"unsupportedVersion"}"#
        #expect(throws: PairingFrameError.self) {
            try PairingFrame.decode(rawFrame(body: body))
        }
    }
}

private enum CodecFixtureError: Error {
    case badCode
}

/// The four length-prefix bytes for `length`, big-endian.
func rawLengthPrefix(_ length: Int) -> Data {
    Data([
        UInt8((length >> 24) & 0xFF),
        UInt8((length >> 16) & 0xFF),
        UInt8((length >> 8) & 0xFF),
        UInt8(length & 0xFF)
    ])
}

/// A frame built by hand, so a test can make the bytes wrong in a chosen way.
func rawFrame(body: String) -> Data {
    var frame = rawLengthPrefix(body.utf8.count)
    frame.append(contentsOf: body.utf8)
    return frame
}
