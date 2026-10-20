import Dispatch
import Foundation
import Network
import Security

// E1: the TLS 1.3 exporter that a Network.framework client derives, for comparison with Node's
// `exportKeyingMaterial` on the same connection (plan §2.2, §4 G3).
//
// Usage: e1-nw-exporter <port> <label> <anchor.der>
//
// Prints `<negotiated-version> <exporter-hex>` on stdout and exits 0. Exits 2 when the connection,
// the negotiated version, the trust evaluation or the export fails, with the reason on stderr.
//
// The server certificate is evaluated against one anchor, the DER file given on the command line,
// and nothing else. The spike's certificates are self-signed, so the anchor is the server's own
// certificate, and a client given the other certificate must be refused. That refusal is a gate.

guard CommandLine.arguments.count == 4, let port = UInt16(CommandLine.arguments[1]) else {
    fputs("usage: e1-nw-exporter <port> <label> <anchor.der>\n", stderr)
    exit(2)
}
let label = CommandLine.arguments[2]
let anchorPath = CommandLine.arguments[3]

func fail(_ reason: String) -> Never {
    fputs("e1-nw-exporter: \(reason)\n", stderr)
    exit(2)
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined()
}

guard let anchorData = FileManager.default.contents(atPath: anchorPath),
      let anchor = SecCertificateCreateWithData(nil, anchorData as CFData) else {
    fail("cannot read the trust anchor at \(anchorPath)")
}

// The product's client options, from NetworkPairingTransport.swift: TLS 1.3 minimum. Only the
// minimum is set, so a server that negotiates anything lower is observed rather than prevented.
let tls = NWProtocolTLS.Options()
sec_protocol_options_set_min_tls_protocol_version(tls.securityProtocolOptions, .TLSv13)
// Trust is evaluated against the one anchor, and nothing else is trusted.
sec_protocol_options_set_verify_block(
    tls.securityProtocolOptions,
    { _, secTrust, complete in
        let trust = sec_trust_copy_ref(secTrust).takeRetainedValue()
        SecTrustSetAnchorCertificates(trust, [anchor] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        var error: CFError?
        complete(SecTrustEvaluateWithError(trust, &error))
    },
    DispatchQueue.global()
)

let parameters = NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
let connection = NWConnection(
    host: "127.0.0.1",
    port: NWEndpoint.Port(rawValue: port)!,
    using: parameters
)

let finished = DispatchSemaphore(value: 0)
var output: String?

connection.stateUpdateHandler = { state in
    switch state {
    case .ready:
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            fail("no TLS metadata on a ready connection")
        }
        let secMetadata = metadata.securityProtocolMetadata
        let version = sec_protocol_metadata_get_negotiated_tls_protocol_version(secMetadata)
        guard version == .TLSv13 else {
            fail("negotiated TLS version is not 1.3 (raw \(version.rawValue))")
        }
        guard let secret = sec_protocol_metadata_create_secret(secMetadata, label.utf8.count, label, 32) else {
            fail("sec_protocol_metadata_create_secret returned nil")
        }
        let bytes = [UInt8](secret as DispatchData)
        output = "TLSv1.3 \(hex(bytes))"
        finished.signal()
    case .failed(let error):
        fail("connection failed: \(error)")
    case .waiting(let error):
        fail("connection waiting on loopback: \(error)")
    default:
        break
    }
}

connection.start(queue: DispatchQueue(label: "e1.nw.exporter"))

guard finished.wait(timeout: .now() + 10) == .success, let line = output else {
    fail("timed out waiting for the TLS handshake")
}
connection.cancel()
print(line)
exit(0)
