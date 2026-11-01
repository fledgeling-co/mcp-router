import CryptoKit
import Foundation

/// The phone's own P-256 key, which identifies this phone to every Mac it pairs with.
///
/// Built to `PairingRecordStore`'s shape: a protocol, a Keychain implementation and an in-memory
/// double, because the Keychain is a process boundary.
public protocol PhoneKeyStore: Sendable {
    /// The phone's key, created on first use and kept.
    ///
    /// Created once rather than per pairing. A second pairing that minted a new key would leave the
    /// first Mac's record holding a public key whose private half no longer exists.
    func loadOrCreate() async throws -> P256.Signing.PrivateKey
    func loadExisting() async throws -> P256.Signing.PrivateKey
}

public extension PhoneKeyStore {
    func loadExisting() async throws -> P256.Signing.PrivateKey {
        throw PhoneKeyError.unreadable
    }
}

public enum PhoneKeyError: Error, Equatable, Sendable {
    case keychain(status: OSStatus)
    /// An item is present but is not a P-256 private key. It is not overwritten: a corrupt key may
    /// still belong to a pairing the phone already holds.
    case unreadable
}

/// The real store: a generic password in the Keychain, device-bound.
///
/// `ThisDeviceOnly` for the same reason as `KeychainPairingStore`: the key is the phone's identity to
/// every Mac, and a backup that restored it onto another device would give that device this phone's
/// identity.
public struct KeychainPhoneKeyStore: PhoneKeyStore {
    public let service: String
    public let account: String

    public init(service: String = "app.fledgeling.mcprouter.pairing", account: String = "phone-key") {
        self.service = service
        self.account = account
    }

    public func loadOrCreate() async throws -> P256.Signing.PrivateKey {
        if let existing = try read() { return existing }
        let key = P256.Signing.PrivateKey()
        try write(key)
        return key
    }

    public func loadExisting() async throws -> P256.Signing.PrivateKey {
        guard let key = try read() else { throw PhoneKeyError.unreadable }
        return key
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }

    /// The add query, built in one place so a test can read the accessibility class it carries.
    func addQuery(for key: P256.Signing.PrivateKey) -> [CFString: Any] {
        var query = baseQuery
        query[kSecValueData] = key.rawRepresentation
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return query
    }

    private func read() throws -> P256.Signing.PrivateKey? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw PhoneKeyError.keychain(status: status) }
        guard let data = item as? Data else { throw PhoneKeyError.unreadable }
        do {
            return try P256.Signing.PrivateKey(rawRepresentation: data)
        } catch {
            throw PhoneKeyError.unreadable
        }
    }

    private func write(_ key: P256.Signing.PrivateKey) throws {
        let status = SecItemAdd(addQuery(for: key) as CFDictionary, nil)
        guard status == errSecSuccess else { throw PhoneKeyError.keychain(status: status) }
    }
}

/// An in-memory key for tests. An actor, so the Sendable claim is checked rather than promised.
public actor InMemoryPhoneKeyStore: PhoneKeyStore {
    private var key: P256.Signing.PrivateKey?

    public init() {}

    public func loadExisting() async throws -> P256.Signing.PrivateKey {
        guard let key else { throw PhoneKeyError.unreadable }
        return key
    }

    public func loadOrCreate() async throws -> P256.Signing.PrivateKey {
        if let key { return key }
        let created = P256.Signing.PrivateKey()
        key = created
        return created
    }
}
