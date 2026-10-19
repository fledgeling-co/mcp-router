import CryptoKit
import Foundation
import Testing
@testable import MCPRouterKit

/// The phone's exchange, run against a scripted Mac and a recorded trace of what the phone did.
///
/// The ordering assertions are the point of this suite: REQ-016 says the paired-Mac record is written
/// only after `pair.ok` and the key write, and the trace is what shows the order actually happened.
@Suite("Live pairing service")
struct LivePairingServiceTests {
    static let macName = "Luke's MacBook Pro"
    static let fingerprint = "SHA256:5f2b9c0e"

    @Test("a record is written after pair.ok, and the ack follows it")
    func recordOrdering() async throws {
        var rig = Rig()
        rig.reply = try okReply()
        let result = try await rig.service().result(for: .scanned(payload()))

        guard case .paired = result else {
            Issue.record("expected paired, got \(result)")
            return
        }
        #expect(await rig.trace.events == [
            "key", "connect", "send request", "receive", "save record", "send ack", "close"
        ])
    }

    @Test("the stored record names the Mac from pair.ok and the endpoint from the QR")
    func recordContents() async throws {
        var rig = Rig()
        rig.reply = try okReply()
        let outcome = try await rig.service().pair(using: .scanned(payload()))

        guard case let .paired(mac) = outcome else {
            Issue.record("expected paired, got \(outcome)")
            return
        }
        #expect(mac.name == Self.macName)
        #expect(mac.host == "192.168.1.24")
        #expect(mac.port == 7333)
        #expect(mac.fingerprint == Self.fingerprint)
        #expect(await rig.store.load() == .loaded(mac))
    }

    @Test("a refused code writes nothing and sends no ack")
    func refusal() async throws {
        var rig = Rig()
        rig.reply = try .frame(PairingFrame.encode(.refused(.alreadyUsed)))
        let result = try await rig.service().result(for: .scanned(payload()))

        #expect(result == .refused(.alreadyUsed))
        #expect(await rig.store.load() == .missing)
        #expect(await !(rig.trace.events).contains("save record"))
        #expect(await !(rig.trace.events).contains("send ack"))
    }

    @Test("a transport failure writes nothing")
    func transportFailure() async throws {
        var rig = Rig()
        rig.connectFails = true
        let result = try await rig.service().result(for: .scanned(payload()))

        #expect(result == .failed(.transport))
        #expect(await rig.store.load() == .missing)
    }

    @Test("a Mac that never answers times out, writes nothing, and sends no ack")
    func timeout() async throws {
        var rig = Rig()
        rig.reply = .hang
        rig.timeout = .milliseconds(50)
        let result = try await rig.service().result(for: .scanned(payload()))

        #expect(result == .failed(.timedOut))
        #expect(await rig.store.load() == .missing)
        #expect(await !(rig.trace.events).contains("send ack"))
    }

    @Test("a key that cannot be stored stops the exchange before any connection")
    func keyWriteFailure() async throws {
        var rig = Rig()
        rig.failsOnKey = true
        rig.reply = try okReply()
        let result = try await rig.service().result(for: .scanned(payload()))

        #expect(result == .failed(.keyStore))
        #expect(await !(rig.trace.events).contains("connect"))
        #expect(await rig.store.load() == .missing)
    }

    @Test("a record that cannot be stored sends no ack, so the Mac's record stays pending")
    func recordWriteFailure() async throws {
        var rig = Rig()
        rig.failsOnSave = true
        rig.reply = try okReply()
        let result = try await rig.service().result(for: .scanned(payload()))

        #expect(result == .failed(.recordStore))
        #expect(await !(rig.trace.events).contains("send ack"))
        #expect(await rig.store.load() == .missing)
    }

    @Test("an ack that does not go out withdraws the record it was sent for")
    func ackFailureRollsBack() async throws {
        var rig = Rig()
        rig.failsOnAck = true
        rig.reply = try okReply()
        let result = try await rig.service().result(for: .scanned(payload()))

        #expect(result == .failed(.ackNotSent))
        #expect(await rig.trace.events.contains("clear record"))
        #expect(await rig.store.load() == .missing)
    }

    @Test("an ack that does not go out puts back the Mac that was paired before")
    func ackFailureRestoresEarlierPairing() async throws {
        var rig = Rig()
        let earlier = PairedMac(
            name: "Old Mac",
            pairedAt: Date(timeIntervalSince1970: 1_755_000_000),
            lastSeen: nil,
            host: "192.168.1.9",
            port: 7333,
            fingerprint: "SHA256:00000000"
        )
        try await rig.store.save(earlier)
        rig.failsOnAck = true
        rig.reply = try okReply()
        let result = try await rig.service().result(for: .scanned(payload()))

        #expect(result == .failed(.ackNotSent))
        #expect(await rig.store.load() == .loaded(earlier))
    }

    @Test("a certificate that is not the one the QR named gets no request")
    func fingerprintMismatch() async throws {
        var rig = Rig()
        rig.peerFingerprint = "SHA256:deadbeef"
        rig.reply = try okReply()
        let result = try await rig.service().result(for: .scanned(payload()))

        #expect(result == .failed(.identityMismatch))
        #expect(await !(rig.trace.events).contains("send request"))
        #expect(await rig.store.load() == .missing)
    }

    @Test("a reply that is not a pairing message is a protocol violation")
    func protocolViolation() async throws {
        var rig = Rig()
        rig.reply = .frame(rawFrame(body: #"{"t":"pair.request","v":1}"#))
        let result = try await rig.service().result(for: .scanned(payload()))

        #expect(result == .failed(.protocolViolation))
        #expect(await rig.store.load() == .missing)
    }

    @Test("an expired code is refused before any connection")
    func expired() async throws {
        let rig = Rig()
        let outcome = try await rig.service().pair(using: .scanned(payload(expiresIn: -10)))

        #expect(outcome == .expired)
        #expect(await rig.trace.events.isEmpty)
    }

    @Test("a typed code cannot be pinned, so nothing is sent")
    func typedAttempt() async throws {
        let rig = Rig()
        let outcome = try await rig.service().pair(using: .typed(code()))

        #expect(outcome == .unreachable(macName: nil))
        #expect(await rig.trace.events.isEmpty)
    }

    @Test("reachability is reported only for a Mac whose certificate matches the record")
    func reachabilityPinned() async {
        let rig = Rig()
        let state = await rig.service().reachability(of: expectedMac())

        #expect(state == .reachable)
        #expect(await !(rig.trace.events).contains("send request"))
        #expect(await rig.trace.events.contains("close"))
    }

    @Test("reachability fails closed on a certificate that does not match")
    func reachabilityMismatch() async {
        var rig = Rig()
        rig.peerFingerprint = "SHA256:deadbeef"
        let state = await rig.service().reachability(of: expectedMac())

        #expect(state == .notReachable)
    }

    @Test("reachability fails closed when nothing connects")
    func reachabilityUnreachable() async {
        var rig = Rig()
        rig.connectFails = true
        let state = await rig.service().reachability(of: expectedMac())

        #expect(state == .notReachable)
    }

    // MARK: Fixtures

    private func okReply() throws -> FakeReply {
        try .frame(PairingFrame.encode(.ok(macName: Self.macName, phoneId: "phone-1")))
    }

    private func code() throws -> PairingCode {
        guard let code = PairingCode("K7QN4FMB") else { throw FixtureError.badCode }
        return code
    }

    private func payload(expiresIn: TimeInterval = 300) throws -> PairingPayload {
        try PairingPayload(
            version: 1,
            code: code(),
            macName: Self.macName,
            expiresAt: Date().addingTimeInterval(expiresIn),
            host: "192.168.1.24",
            port: 7333,
            fingerprint: Self.fingerprint
        )
    }

    private func expectedMac() -> PairedMac {
        PairedMac(
            name: Self.macName,
            pairedAt: Date(),
            lastSeen: Date(),
            host: "192.168.1.24",
            port: 7333,
            fingerprint: Self.fingerprint
        )
    }
}

private enum FixtureError: Error {
    case badCode
}

/// A store or key write the test has chosen to refuse.
enum FixtureFailure: Error {
    case write
}

/// What the scripted Mac does when the phone reads from it.
enum FakeReply: Sendable {
    case frame(Data)
    case hang
}

/// A shared, ordered record of everything the phone did, across the transport, the stores and the
/// key store.
actor Trace {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

/// Everything one test needs: a scripted Mac, a trace, and stores that can be told to fail.
struct Rig {
    let trace = Trace()
    let store = InMemoryPairingStore()
    let keys = InMemoryPhoneKeyStore()

    var connectFails = false
    var peerFingerprint = LivePairingServiceTests.fingerprint
    var reply: FakeReply = .hang
    var failsOnAck = false
    var failsOnSave = false
    var failsOnKey = false
    var timeout: Duration = .seconds(5)

    func service() -> LivePairingService {
        LivePairingService(
            transport: FakeTransport(
                trace: trace,
                connectFails: connectFails,
                peerFingerprint: peerFingerprint,
                reply: reply,
                failsOnAck: failsOnAck
            ),
            keys: FakeKeyStore(trace: trace, inner: keys, fails: failsOnKey),
            records: RecordingStore(trace: trace, inner: store, failsOnSave: failsOnSave),
            phoneName: "Test iPhone",
            timeout: timeout
        )
    }
}

struct FakeTransport: PairingTransport {
    let trace: Trace
    let connectFails: Bool
    let peerFingerprint: String
    let reply: FakeReply
    let failsOnAck: Bool

    func connect(host: String, port: Int) async throws -> any PairingChannel {
        await trace.record("connect")
        if connectFails { throw PairingTransportError.connectFailed }
        return FakeChannel(
            trace: trace,
            peerFingerprint: peerFingerprint,
            reply: reply,
            failsOnAck: failsOnAck
        )
    }
}

struct FakeChannel: PairingChannel {
    let trace: Trace
    let peerFingerprint: String
    let reply: FakeReply
    let failsOnAck: Bool

    func send(_ frame: Data) async throws {
        let message = try? PairingFrame.decode(frame)
        switch message {
        case .request?: await trace.record("send request")
        case .ack?:
            await trace.record("send ack")
            if failsOnAck { throw PairingTransportError.closed }
        default: await trace.record("send other")
        }
    }

    func receive() async throws -> Data {
        await trace.record("receive")
        switch reply {
        case let .frame(data):
            return data
        case .hang:
            try await Task.sleep(for: .seconds(3600))
            return Data()
        }
    }

    func close() async {
        await trace.record("close")
    }
}

struct FakeKeyStore: PhoneKeyStore {
    let trace: Trace
    let inner: InMemoryPhoneKeyStore
    let fails: Bool

    func loadOrCreate() async throws -> P256.Signing.PrivateKey {
        await trace.record("key")
        if fails { throw FixtureFailure.write }
        return try await inner.loadOrCreate()
    }
}

struct RecordingStore: PairingRecordStore {
    let trace: Trace
    let inner: InMemoryPairingStore
    let failsOnSave: Bool

    func load() async -> PairingRecordLoad {
        await inner.load()
    }

    func save(_ mac: PairedMac) async throws {
        await trace.record("save record")
        if failsOnSave { throw FixtureFailure.write }
        try await inner.save(mac)
    }

    func clear() async throws {
        await trace.record("clear record")
        try await inner.clear()
    }
}
