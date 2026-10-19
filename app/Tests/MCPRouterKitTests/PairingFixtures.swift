import CryptoKit
import Foundation
@testable import MCPRouterKit

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
    private(set) var phoneKeys: [Data] = []
    /// Every address the transport was asked to connect to, in order. Kept apart from `events` so the
    /// ordering assertions above do not change with it.
    private(set) var dialled: [String] = []

    func record(_ event: String) {
        events.append(event)
    }

    func recordPhoneKey(_ key: Data) {
        phoneKeys.append(key)
    }

    func recordDial(_ address: String) {
        dialled.append(address)
    }
}

struct FakeDiscovery: PairingDiscovery {
    let trace: Trace
    let endpoints: [DiscoveredMac]

    func browse() async -> [DiscoveredMac] {
        await trace.record("browse")
        return endpoints
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
    /// When set, each "host:port" answers with the fingerprint given, and every other address refuses.
    /// Nil keeps the single-address behaviour above, which every older test depends on.
    var addresses: [String: String]?
    /// What a browse of the local network returns.
    var discovered: [DiscoveredMac] = []

    func service() -> LivePairingService {
        LivePairingService(
            transport: FakeTransport(
                trace: trace,
                connectFails: connectFails,
                peerFingerprint: peerFingerprint,
                reply: reply,
                failsOnAck: failsOnAck,
                addresses: addresses
            ),
            keys: FakeKeyStore(trace: trace, inner: keys, fails: failsOnKey),
            records: RecordingStore(trace: trace, inner: store, failsOnSave: failsOnSave),
            discovery: FakeDiscovery(trace: trace, endpoints: discovered),
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
    let addresses: [String: String]?

    func connect(host: String, port: Int) async throws -> any PairingChannel {
        await trace.record("connect")
        await trace.recordDial("\(host):\(port)")
        if let addresses {
            guard let presented = addresses["\(host):\(port)"] else {
                throw PairingTransportError.connectFailed
            }
            return FakeChannel(
                trace: trace,
                peerFingerprint: presented,
                reply: reply,
                failsOnAck: failsOnAck
            )
        }
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
        case let .request(_, _, phoneKey)?:
            await trace.record("send request")
            await trace.recordPhoneKey(phoneKey)
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
