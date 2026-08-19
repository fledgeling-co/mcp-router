import CryptoKit
import Foundation

/// PKCE, RFC 7636, in the shape the reference's `pkce-challenge` produces.
///
/// The verifier's alphabet and length are not decoration: a 43-character verifier drawn from
/// `A-Za-z0-9-._~` is what the reference writes into the credential file and sends to the token
/// endpoint, and the two routers are compared on the *shape* of that value with the value itself
/// normalised, so a port that emitted a 32-byte base64url string would be caught.
public enum OAuthPKCE {
    /// `pkce-challenge`'s mask, character for character.
    public static let alphabet: [Character] = Array(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )

    /// `pkceChallenge()`'s default length.
    public static let verifierLength = 43

    /// A fresh code verifier.
    ///
    /// The randomness comes from `SystemRandomNumberGenerator`, which is the platform CSPRNG; the
    /// injectable parameter exists so a test can pin the value rather than assert on a range.
    public static func verifier(
        length: Int = verifierLength,
        randomIndex: () -> Int = { Int.random(in: 0 ..< alphabet.count) }
    ) -> String {
        String((0 ..< length).map { _ in alphabet[randomIndex() % alphabet.count] })
    }

    /// `generateChallenge`: base64url of SHA-256 over the verifier's UTF-8, unpadded.
    public static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// `S256`. The only method this client offers, and the only one the reference's SDK offers.
    public static let challengeMethod = "S256"
}
