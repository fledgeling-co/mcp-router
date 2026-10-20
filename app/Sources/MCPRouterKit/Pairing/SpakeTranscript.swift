import CryptoKit
import Foundation

/// The SPAKE2 transcript and key schedule for the typed-code path (plan-pairing-typed-spake2 §2.1 and §2.3,
/// after RFC 9382 §3.3 and §4). Every point, the shared element K and w are inputs, computed by the group
/// layer. The hash, HKDF and MAC are CryptoKit's. Nothing here does curve arithmetic.
enum SpakeTranscript {
    enum Failure: Error, Equatable {
        /// w is reduced mod the group order, so it never exceeds 32 bytes. A longer value is a caller
        /// that did not reduce it, and TT would carry it without complaint.
        case scalarLongerThanThirtyTwoBytes(Int)
    }

    /// The fields of TT, in the order RFC 9382 §3.3 gives them. `k` is the shared group element K.
    struct Inputs: Equatable {
        let identityA: Data
        let identityB: Data
        let pA: Data
        let pB: Data
        let k: Data
        let w: Data
    }

    /// The keys one exchange derives. `ke` is the RFC's output but is not used in v1 (plan §2.3). It is
    /// kept so the vectors can check it.
    struct KeySchedule: Equatable {
        let ke: Data
        let ka: Data
        let kcA: Data
        let kcB: Data
    }

    /// TT (RFC 9382 §3.3). Each field is preceded by its length as an 8-byte little-endian number. w is
    /// big-endian and left-padded to 32 bytes, so a w with its leading zeros dropped still gives the same TT.
    static func transcript(_ inputs: Inputs) throws -> Data {
        guard inputs.w.count <= 32 else { throw Failure.scalarLongerThanThirtyTwoBytes(inputs.w.count) }
        let w = Data(repeating: 0x00, count: 32 - inputs.w.count) + inputs.w

        return lengthPrefixed(inputs.identityA)
            + lengthPrefixed(inputs.identityB)
            + lengthPrefixed(inputs.pA)
            + lengthPrefixed(inputs.pB)
            + lengthPrefixed(inputs.k)
            + lengthPrefixed(w)
    }

    /// Ke ‖ Ka = Hash(TT), each half the digest (RFC 9382 §4). KcA ‖ KcB = HKDF-SHA256(nil salt, Ka,
    /// "ConfirmationKeys" ‖ AAD, 32 bytes), so each confirmation key is 128 bits. AAD is nil when
    /// there is none.
    static func keySchedule(transcript: Data, aad: Data) -> KeySchedule {
        let digest = Data(SHA256.hash(data: transcript))
        let ke = Data(digest.prefix(16))
        let ka = Data(digest.suffix(16))

        let confirmationKeys = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: ka),
            salt: Data(),
            info: Data("ConfirmationKeys".utf8) + aad,
            outputByteCount: 32
        ).withUnsafeBytes { Data($0) }

        return KeySchedule(
            ke: ke,
            ka: ka,
            kcA: Data(confirmationKeys.prefix(16)),
            kcB: Data(confirmationKeys.suffix(16))
        )
    }

    /// cA = MAC(KcA, TT) and cB = MAC(KcB, TT) (RFC 9382 §3.3). The MAC is HMAC-SHA256, the one the
    /// suite the vectors use names. The caller compares the result in constant time, as the exchange
    /// requires.
    static func confirmation(key: Data, transcript: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: transcript, using: SymmetricKey(data: key)))
    }

    private static func lengthPrefixed(_ field: Data) -> Data {
        withUnsafeBytes(of: UInt64(field.count).littleEndian) { Data($0) } + field
    }
}
