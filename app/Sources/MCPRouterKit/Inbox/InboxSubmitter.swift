import CryptoKit
import Foundation

public enum InboxSubmitError: Error, Sendable, Equatable {
    case needsPairing
    case refused(String)
    case malformed
}

/// The inbox codec shares the TLS channel with pairing, while keeping its own 64 KiB write cap.
public enum InboxFrame {
    public static let maxBodyLength = 65536

    public static func signedString(nonce: String, phoneID: String, items: String) -> String {
        let digest = SHA256.hash(data: Data(items.utf8)).map { String(format: "%02x", $0) }.joined()
        return "mcp-router-inbox-v1\n\(nonce)\n\(phoneID)\n\(digest)"
    }

    public static func encode(_ fields: [String: Any]) throws -> Data {
        let body = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        guard body.count <= maxBodyLength else { throw InboxSubmitError.refused("frameTooLarge") }
        var length = UInt32(body.count).bigEndian
        return withUnsafeBytes(of: &length) { Data($0) } + body
    }

    static func decode(_ frame: Data) throws -> [String: Any] {
        guard frame.count >= 4 else { throw InboxSubmitError.malformed }
        let length = frame.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
        guard length <= maxBodyLength, frame.count == length + 4,
              let fields = try JSONSerialization.jsonObject(with: frame.dropFirst(4)) as? [String: Any],
              fields["v"] as? Int == 1 else { throw InboxSubmitError.malformed }
        if fields["type"] as? String == "inbox.refused" {
            throw InboxSubmitError.refused(fields["reason"] as? String ?? "badRequest")
        }
        return fields
    }
}

public protocol InboxSubmitting: Sendable {
    func submitPending() async throws
}

/// Signs only queue coordinates. The router resolves capabilities and no submit installs anything.
public actor InboxSubmitter: InboxSubmitting {
    private let queue: any CapabilityReceiptStore
    private let records: any PairingRecordStore
    private let keys: any PhoneKeyStore
    private let transport: any PairingTransport
    private var running = false
    private var refusedPairing: PairedMac?

    public init(
        queue: any CapabilityReceiptStore,
        records: any PairingRecordStore,
        keys: any PhoneKeyStore = KeychainPhoneKeyStore(),
        transport: any PairingTransport = NetworkPairingTransport(maxBodyLength: InboxFrame
            .maxBodyLength)
    ) {
        self.queue = queue
        self.records = records
        self.keys = keys
        self.transport = transport
    }

    public func submitPending() async throws {
        guard !running else { return }
        running = true
        defer { running = false }
        let pending = try await queue.all().filter { $0.receiptAt == nil }
        guard !pending.isEmpty else { return }
        guard case let .loaded(mac) = await records.load(), let phoneID = mac.phoneID else {
            throw InboxSubmitError.needsPairing
        }
        guard refusedPairing != mac else { throw InboxSubmitError.needsPairing }
        let key: P256.Signing.PrivateKey
        do { key = try await keys.loadExisting() } catch { throw InboxSubmitError.needsPairing }
        do {
            for start in stride(from: 0, to: pending.count, by: 50) {
                let batch = Array(pending[start ..< min(start + 50, pending.count)])
                try await send(batch, to: mac, phoneID: phoneID, key: key)
            }
        } catch let error as InboxSubmitError {
            if case .refused = error { refusedPairing = mac }
            throw error
        }
    }

    private func send(
        _ batch: [QueuedCapability],
        to mac: PairedMac,
        phoneID: String,
        key: P256.Signing.PrivateKey
    ) async throws {
        // A deadline cancels Network.framework operations, including a stalled TLS handshake.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await self.exchange(batch, to: mac, phoneID: phoneID, key: key) }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw PairingTransportError.closed
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private func exchange(
        _ batch: [QueuedCapability],
        to mac: PairedMac,
        phoneID: String,
        key: P256.Signing.PrivateKey
    ) async throws {
        let channel = try await transport.connect(host: mac.host, port: mac.port, expecting: mac.fingerprint)
        do {
            guard channel.peerFingerprint == mac.fingerprint
            else { throw PairingTransportError.identityMismatch }
            try await channel.send(InboxFrame.encode(["type": "inbox.hello", "v": 1, "phoneId": phoneID]))
            let challenge = try await InboxFrame.decode(channel.receive())
            guard challenge["type"] as? String == "inbox.nonce", let nonce = challenge["nonce"] as? String,
                  !nonce.isEmpty else { throw InboxSubmitError.malformed }
            let coordinates = batch.map { ["id": $0.id, "displayName": $0.displayName,
                                           "queuedAt": ISO8601Instant.string(from: $0.queuedAt)] }
            let data = try JSONSerialization.data(withJSONObject: coordinates, options: [.sortedKeys])
            guard let items = String(data: data, encoding: .utf8) else { throw InboxSubmitError.malformed }
            let signature = try key.signature(for: Data(InboxFrame.signedString(
                nonce: nonce,
                phoneID: phoneID,
                items: items
            ).utf8))
            try await channel.send(InboxFrame.encode(["type": "inbox.submit", "v": 1, "phoneId": phoneID,
                                                      "nonce": nonce, "items": items,
                                                      "sig": signature.derRepresentation
                                                          .base64EncodedString()]))
            let receipt = try await InboxFrame.decode(channel.receive())
            guard receipt["type"] as? String == "inbox.receipt",
                  let received = receipt["received"] as? [[String: String]]
            else { throw InboxSubmitError.malformed }
            let expected = Set(batch.map(\.id))
            let ids = received.compactMap { row -> String? in
                guard let id = row["id"], expected.contains(id),
                      ["waiting", "duplicate"].contains(row["state"]) else { return nil }
                return id
            }
            guard ids.count == batch.count, Set(ids) == expected else { throw InboxSubmitError.malformed }
            try await queue.recordReceipts(expected, at: Date())
            await channel.close()
        } catch {
            await channel.close()
            throw error
        }
    }
}
