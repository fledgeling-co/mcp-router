using System.Security.Cryptography;

namespace MCPRouter.Shell.Model.Pairing;

/// <summary>
/// The fingerprint a client pins, in the form the QR's <c>fp</c> carries (plan §2.4): lowercase hex SHA-256 of the
/// certificate's DER, 64 characters, no prefix and no separators. The router renders the same string in
/// <c>src/pairing-identity.ts</c>, and the phone in <c>PairingFingerprint.render</c>.
/// </summary>
public static class PairingFingerprint
{
    public static string Render(byte[] certificateDer) =>
        Convert.ToHexString(SHA256.HashData(certificateDer)).ToLowerInvariant();
}

