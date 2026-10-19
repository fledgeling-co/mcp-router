import CryptoKit
import Foundation

/// The fingerprint a phone pins, in the form the QR's `fp` carries (plan §2.4): lowercase hex SHA-256 of
/// the certificate's DER, 64 characters, with no prefix and no separators. The router renders the same
/// string in `src/pairing-identity.ts`. `PairingWireVectorsTests` checks both against one certificate.
public enum PairingFingerprint {
    public static func render(certificateDER: Data) -> String {
        SHA256.hash(data: certificateDER).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether a presented certificate is the one the QR named. An exact string comparison in the
    /// rendered form, so a `SHA256:` prefix or an upper-case digit is a mismatch, not a near miss.
    public static func matches(certificateDER: Data, expecting fingerprint: String) -> Bool {
        render(certificateDER: certificateDER) == fingerprint
    }
}
