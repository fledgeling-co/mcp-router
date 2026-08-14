import Foundation

/// What reading the stored pairing produced.
///
/// Three outcomes, and keeping `missing` apart from `unreadable` is the point rather than tidiness.
/// A Keychain item stored `ThisDeviceOnly` does **not** travel in a backup, so on a device restored
/// from one the item is **absent** — which means "no Mac paired yet", the ordinary first-run state
/// with its ordinary first-run action. Folding absent into an error state would greet a user with
/// "Can't read this phone's pairing" on a phone that has never paired anything, and offer to fix a
/// problem that does not exist.
public enum PairingRecordLoad: Sendable, Equatable {
    case missing
    case loaded(PairedMac)
    case unreadable(detail: String)
}

/// Where the pairing record lives between launches.
///
/// Built to `ControlTokenStore`'s shape — a protocol, a Keychain implementation, an in-memory
/// double — because the Keychain is a process boundary and this repo's testing rule substitutes a
/// double exactly there and nowhere else.
public protocol PairingRecordStore: Sendable {
    func load() async -> PairingRecordLoad
    func save(_ mac: PairedMac) async throws
    func clear() async throws
}

/// The real store: a generic password in the Keychain, device-bound.
///
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` rather than the plain form, and the difference
/// is load-bearing. This record authorises a phone to queue executable capabilities onto someone's
/// laptop. The plain accessibility class travels in an encrypted backup and would therefore restore
/// onto a *different* device, handing that device a pairing its owner never granted. `ThisDeviceOnly`
/// does not leave the phone it was created on.
public struct KeychainPairingStore: PairingRecordStore {
    public let service: String
    public let account: String
    private let log: ControlLog

    public init(
        service: String = "app.fledgeling.mcprouter.pairing",
        account: String = "paired-mac",
        log: ControlLog = ControlLog()
    ) {
        self.service = service
        self.account = account
        self.log = log
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }

    public func load() async -> PairingRecordLoad {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess else {
            // The status, never the item. A Keychain status is a diagnostic; the payload is a
            // credential.
            log.warning("pairing record unreadable, OSStatus \(status)")
            return .unreadable(detail: "OSStatus \(status)")
        }
        guard let data = item as? Data else {
            log.warning("pairing record was not data")
            return .unreadable(detail: "not data")
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try .loaded(decoder.decode(PairedMac.self, from: data))
        } catch {
            // Present and undecodable — an older or newer record shape. This is the *observed*
            // failure the Error state renders, and the only route to it.
            log.warning("pairing record failed to decode (\(data.count) bytes)")
            return .unreadable(detail: "decode failed")
        }
    }

    public func save(_ mac: PairedMac) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(mac)

        // Delete-then-add rather than update, matching `KeychainTokenStore`: an update on a missing
        // item fails, and branching on which case applies is one more state to get wrong.
        SecItemDelete(baseQuery as CFDictionary)

        var query = baseQuery
        query[kSecValueData] = data
        query[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError.keychain(status: status) }
        log.info("pairing record stored (\(data.count) bytes)")
    }

    public func clear() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.keychain(status: status)
        }
        log.info("pairing record cleared")
    }
}

/// An in-memory store for tests. An actor, so no `@unchecked Sendable` promise has to be audited.
public actor InMemoryPairingStore: PairingRecordStore {
    private var state: PairingRecordLoad

    public init(_ initial: PairingRecordLoad = .missing) {
        state = initial
    }

    public func load() async -> PairingRecordLoad {
        state
    }

    public func save(_ mac: PairedMac) async throws {
        state = .loaded(mac)
    }

    public func clear() async throws {
        state = .missing
    }
}
