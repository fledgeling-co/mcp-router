import CryptoKit
import Foundation
import Testing
@testable import MCPRouterKit

@Suite("Inbox submit receipts") struct InboxSubmitterTests {
    @Test func signatureVector() throws {
        let vector = try #require(Vectors.root()["inboxSigning"] as? [String: String])
        let nonce = try #require(vector["nonce"])
        let phone = try #require(vector["phoneId"])
        let items = try #require(vector["items"])
        #expect(InboxFrame.signedString(nonce: nonce, phoneID: phone, items: items) == vector["signedString"])
    }

    @Test func receiptsSurviveRelaunch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = FileCapabilityQueueWriter(directory: directory)
        let pick = QueuedCapability(
            id: "atlas",
            displayName: "Atlas",
            source: .official,
            install: nil,
            queuedAt: Date(timeIntervalSince1970: 123)
        )
        try await queue.enqueue(pick)
        try await queue.recordReceipts(["atlas"], at: Date(timeIntervalSince1970: 456))
        let saved = try await FileCapabilityQueueWriter(directory: directory).all()
        #expect(saved.count == 1)
        #expect(saved.first?.queuedAt == pick.queuedAt)
        #expect(saved.first?.receiptAt == Date(timeIntervalSince1970: 456))
    }
}

private actor InboxTestChannel: PairingChannel {
    nonisolated let peerFingerprint = "SHA256:test"
    let key: P256.Signing.PublicKey
    let refuses: Bool
    var receives = 0
    var ids: [String] = []
    var verified = false
    var dropFirstReceipt: Bool
    var submits = 0
    var transientReason: String?
    init(
        key: P256.Signing.PublicKey,
        refuses: Bool = false,
        dropFirstReceipt: Bool = false,
        transientReason: String? = nil
    ) {
        self.key = key
        self.refuses = refuses
        self.dropFirstReceipt = dropFirstReceipt
        self.transientReason = transientReason
    }

    func send(_ frame: Data) async throws {
        let body = try InboxFrame.decode(frame)
        if body["type"] as? String == "inbox.hello" { receives = 0 }
        if body["type"] as? String == "inbox.submit" {
            submits += 1
            let items = try #require(body["items"] as? String)
            let sig = try #require(Data(base64Encoded: body["sig"] as? String ?? ""))
            let signature = try P256.Signing.ECDSASignature(derRepresentation: sig)
            verified = key.isValidSignature(
                signature,
                for: Data(InboxFrame.signedString(nonce: "issued-nonce", phoneID: "phone-1", items: items)
                    .utf8)
            )
            guard verified else { throw InboxSubmitError.refused("badSignature") }
            let rows = try #require(JSONSerialization
                .jsonObject(with: Data(items.utf8)) as? [[String: String]])
            ids = rows.compactMap { $0["id"] }
        }
    }

    func receive() async throws -> Data {
        receives += 1
        if let reason = transientReason {
            transientReason = nil
            return try InboxFrame.encode(["type": "inbox.refused", "v": 1, "reason": reason])
        }
        if refuses {
            return try InboxFrame.encode(["type": "inbox.refused", "v": 1, "reason": "unknownPhone"])
        }
        if receives == 1 { return try InboxFrame.encode([
            "type": "inbox.nonce",
            "v": 1,
            "nonce": "issued-nonce"
        ]) }
        if dropFirstReceipt {
            dropFirstReceipt = false
            throw PairingTransportError.closed
        }
        return try InboxFrame.encode([
            "type": "inbox.receipt",
            "v": 1,
            "received": ids.map { ["id": $0, "state": "waiting"] }
        ])
    }

    func close() async {}
}

private struct InboxTestTransport: PairingTransport {
    let channel: InboxTestChannel
    func connect(
        host: String,
        port: Int,
        expecting fingerprint: String
    ) async throws -> any PairingChannel {
        channel
    }
}

private struct InboxTestKeys: PhoneKeyStore {
    let key: P256.Signing.PrivateKey
    func loadOrCreate() async throws -> P256.Signing.PrivateKey {
        key
    }

    func loadExisting() async throws -> P256.Signing.PrivateKey {
        key
    }
}

extension InboxSubmitterTests {
    @Test func signedDeliveryChangesOnlyReceipt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = FileCapabilityQueueWriter(directory: directory)
        let item = QueuedCapability(
            id: "atlas",
            displayName: "Atlas",
            source: .official,
            install: nil,
            queuedAt: Date(timeIntervalSince1970: 123)
        )
        try await queue.enqueue(item)
        let mac = PairedMac(
            name: "Mac",
            pairedAt: Date(),
            lastSeen: nil,
            host: "localhost",
            port: 7333,
            fingerprint: "SHA256:test",
            phoneID: "phone-1"
        )
        let key = P256.Signing.PrivateKey()
        let channel = InboxTestChannel(key: key.publicKey, dropFirstReceipt: true)
        let sender = InboxSubmitter(
            queue: queue,
            records: InMemoryPairingStore(.loaded(mac)),
            keys: InboxTestKeys(key: key),
            transport: InboxTestTransport(channel: channel)
        )
        await #expect(throws: PairingTransportError.closed) { try await sender.submitPending() }
        #expect(try await queue.all().first?.receiptAt == nil)
        #expect(try await queue.all().count == 1)
        try await sender.submitPending()
        #expect(await channel.submits == 2)
        let result = try await queue.all()
        #expect(result.count == 1)
        #expect(result[0].receiptAt != nil)
        #expect(result[0].queuedAt == item.queuedAt)
        #expect(await channel.verified)
    }

    @Test func refusalKeepsQueueAndNeverCreatesIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = FileCapabilityQueueWriter(directory: directory)
        try await queue.enqueue(QueuedCapability(
            id: "atlas",
            displayName: "Atlas",
            source: .official,
            install: nil,
            queuedAt: Date()
        ))
        let mac = PairedMac(
            name: "Mac",
            pairedAt: Date(),
            lastSeen: nil,
            host: "localhost",
            port: 7333,
            fingerprint: "SHA256:test",
            phoneID: "phone-1"
        )
        let key = P256.Signing.PrivateKey()
        let channel = InboxTestChannel(key: key.publicKey, refuses: true)
        let sender = InboxSubmitter(
            queue: queue,
            records: InMemoryPairingStore(.loaded(mac)),
            keys: InboxTestKeys(key: key),
            transport: InboxTestTransport(channel: channel)
        )
        do {
            try await sender.submitPending()
            Issue.record("refused delivery was accepted")
        } catch { #expect(error as? InboxSubmitError == .refused("unknownPhone")) }
        #expect(try await queue.all().first?.receiptAt == nil)
        #expect(try await queue.all().count == 1)
        let missing = InMemoryPhoneKeyStore()
        let noIdentity = InboxSubmitter(
            queue: queue,
            records: InMemoryPairingStore(.loaded(mac)),
            keys: missing,
            transport: InboxTestTransport(channel: channel)
        )
        do {
            try await noIdentity.submitPending()
            Issue.record("missing key was accepted")
        } catch { #expect(error as? InboxSubmitError == .needsPairing) }
        #expect(await channel.receives == 1)
    }
}

extension InboxSubmitterTests {
    @Test func transientNonceRefusalDoesNotRequirePairingAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = FileCapabilityQueueWriter(directory: directory)
        try await queue.enqueue(QueuedCapability(
            id: "atlas",
            displayName: "Atlas",
            source: .official,
            install: nil,
            queuedAt: Date()
        ))
        let key = P256.Signing.PrivateKey()
        let channel = InboxTestChannel(key: key.publicKey, transientReason: "staleNonce")
        let mac = PairedMac(
            name: "Mac",
            pairedAt: Date(),
            lastSeen: nil,
            host: "localhost",
            port: 7333,
            fingerprint: "SHA256:test",
            phoneID: "phone-1"
        )
        let sender = InboxSubmitter(
            queue: queue,
            records: InMemoryPairingStore(.loaded(mac)),
            keys: InboxTestKeys(key: key),
            transport: InboxTestTransport(channel: channel)
        )
        await #expect(throws: InboxSubmitError.refused("staleNonce")) { try await sender.submitPending() }
        #expect(try await queue.all().first?.receiptAt == nil)
        try await sender.submitPending()
        #expect(try await queue.all().first?.receiptAt != nil)
    }

    @Test func multibytePicksSplitBelowWireByteLimit() throws {
        let picks = (0 ..< 50).map { index in
            QueuedCapability(
                id: "row-\(index)-" + String(repeating: "🦘", count: 180),
                displayName: String(repeating: "🦘", count: 180),
                source: .official,
                install: nil,
                queuedAt: Date(timeIntervalSince1970: 123)
            )
        }
        let batches = try InboxFrame.batches(picks, phoneID: "phone-1")
        #expect(batches.count > 1)
        #expect(batches.flatMap(\.self).map(\.id) == picks.map(\.id))
        for batch in batches {
            let frame = try InboxFrame.encode([
                "type": "inbox.submit",
                "v": 1,
                "phoneId": "phone-1",
                "nonce": String(repeating: "n", count: 43),
                "sig": String(repeating: "s", count: 96),
                "items": InboxFrame.items(batch)
            ])
            #expect(frame.count <= InboxFrame.maxBodyLength + 4)
            #expect(batch.count <= 50)
        }
    }
}
