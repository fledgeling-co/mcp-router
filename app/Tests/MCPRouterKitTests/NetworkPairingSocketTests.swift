import CryptoKit
import Foundation
import Testing
@testable import MCPRouterKit

@Suite("Production pairing transport — independent socket peer")
struct NetworkPairingSocketTests {
    @Test("TLS 1.3 peer observes an outbound connection and the exact production frame")
    func peerReceivesProductionBytes() async throws {
        let peer = try SocketPeer()
        defer { peer.stop() }
        let transport = NetworkPairingTransport()
        let channel = try await bounded {
            try await transport.connect(host: "127.0.0.1", port: peer.port, expecting: peer.fingerprint)
        }
        let frame = Data([0, 0, 0, 4, 112, 105, 110, 103])
        try await channel.send(frame)
        let reply = try await bounded { try await channel.receive() }
        await channel.close()
        #expect(reply == frame)
        let receipt = try await peer.receipt()
        let version = receipt.tlsVersion ?? "none"
        print(
            "SOCKET-WITNESS accepted=\(receipt.acceptedSockets) "
                + "tls=\(version) bytes=\(receipt.plaintextBytes)"
        )
        #expect(receipt.acceptedSockets == 1)
        #expect(receipt.tlsVersion == "TLSv1.3")
        #expect(receipt.plaintextBytes == frame.count)
        #expect(receipt.frameSHA256 == SHA256.hash(data: frame).map { String(format: "%02x", $0) }.joined())
    }

    @Test("a mismatched pin opens a socket but sends no application frame")
    func pinRefusalHasNoApplicationBytes() async throws {
        let peer = try SocketPeer()
        defer { peer.stop() }
        let transport = NetworkPairingTransport()
        do {
            _ = try await bounded {
                try await transport.connect(
                    host: "127.0.0.1",
                    port: peer.port,
                    expecting: String(repeating: "0", count: 64)
                )
            }
            Issue.record("the production transport accepted another certificate")
        } catch PairingTransportError.identityMismatch {
            // Expected refusal, confirmed independently by the peer's byte count below.
        }
        let receipt = try await peer.receipt()
        print("SOCKET-REFUSAL accepted=\(receipt.acceptedSockets) bytes=\(receipt.plaintextBytes)")
        #expect(receipt.acceptedSockets == 1)
        #expect(receipt.plaintextBytes == 0)
    }
}

private func bounded<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await Task.sleep(for: .seconds(5))
            throw SocketPeer.Failure.timeout
        }
        defer { group.cancelAll() }
        return try await #require(group.next())
    }
}

private final class SocketPeer: @unchecked Sendable {
    enum Failure: Error { case processFailed, timeout }
    struct Receipt: Decodable {
        let acceptedSockets: Int
        let plaintextBytes: Int
        let tlsVersion: String?
        let frameSHA256: String?
    }

    let root: URL
    let process: Process
    let port: Int
    let fingerprint: String

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        let child = Process()
        process = child
        do {
            let cert = Process()
            cert.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            cert.arguments = [
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-days",
                "1",
                "-subj",
                "/CN=localhost",
                "-keyout",
                root.appendingPathComponent("key.pem").path,
                "-out",
                root.appendingPathComponent("cert.pem").path
            ]
            cert.standardOutput = FileHandle.nullDevice
            cert.standardError = FileHandle.nullDevice
            try cert.run()
            cert.waitUntilExit()
            guard cert.terminationStatus == 0 else { throw Failure.processFailed }
            let pem = try String(contentsOf: root.appendingPathComponent("cert.pem"), encoding: .utf8)
            let base64 = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
            fingerprint = try PairingFingerprint.render(certificateDER: #require(Data(base64Encoded: base64)))
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = try [
                "python3",
                Vectors.repoRoot().appendingPathComponent("scripts/fixtures/pairing-socket-peer.py").path,
                root.path
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(5)
            let portFile = root.appendingPathComponent("port")
            while !FileManager.default.fileExists(atPath: portFile.path), process.isRunning,
                  Date() < deadline
            {
                Thread.sleep(forTimeInterval: 0.01)
            }
            port = try #require(Int(String(contentsOf: portFile, encoding: .utf8)))
        } catch {
            if child.isRunning { child.terminate(); child.waitUntilExit() }
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func receipt() async throws -> Receipt {
        let file = root.appendingPathComponent("receipt.json")
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: file.path), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        return try JSONDecoder().decode(Receipt.self, from: Data(contentsOf: file))
    }

    func stop() {
        if process.isRunning { process.terminate(); process.waitUntilExit() }
        try? FileManager.default.removeItem(at: root)
    }
}
