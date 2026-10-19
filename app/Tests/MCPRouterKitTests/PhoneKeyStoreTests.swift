import CryptoKit
import Foundation
import Testing
@testable import MCPRouterKit

/// The phone's own key: the class it is stored under, and that it is created once and kept.
@Suite("Phone key store")
struct PhoneKeyStoreTests {
    @Test("the phone key is stored ThisDeviceOnly, so a backup cannot restore it onto another device")
    func thisDeviceOnly() {
        let query = KeychainPhoneKeyStore().addQuery(for: P256.Signing.PrivateKey())
        let accessible = query[kSecAttrAccessible] as? String

        #expect(accessible == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    }

    @Test("the key is generated once and every later call returns the same key")
    func createdOnce() async throws {
        let store = InMemoryPhoneKeyStore()
        let first = try await store.loadOrCreate()
        let second = try await store.loadOrCreate()

        #expect(first.publicKey.x963Representation == second.publicKey.x963Representation)
    }
}
