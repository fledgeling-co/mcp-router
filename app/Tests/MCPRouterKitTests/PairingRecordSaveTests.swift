import Foundation
import Testing
@testable import MCPRouterKit

/// A save the Keychain refuses leaves the record it was replacing. The phone's pairing rests on that: the
/// earlier Mac is the one the phone still has if a replacement cannot be written.
@Suite("Pairing record save")
struct PairingRecordSaveTests {
    @Test("a save the Keychain refuses leaves the earlier record where it was")
    func refusedSaveKeepsTheEarlierRecord() async throws {
        let service = "app.fledgeling.mcprouter.pairing.test.\(UUID().uuidString)"
        let store = KeychainPairingStore(service: service, account: "paired-mac-test")
        let earlier = FixturePairingService.specimenMac
        try await store.save(earlier)

        let refusing = KeychainPairingStore(
            service: service,
            account: "paired-mac-test",
            log: ControlLog(),
            keychain: PairingKeychain(
                update: { _, _ in errSecInteractionNotAllowed },
                add: { _ in errSecInteractionNotAllowed }
            )
        )
        let replacement = PairedMac(
            name: "Replacement Mac",
            pairedAt: Date(timeIntervalSince1970: 1_756_000_000),
            lastSeen: nil,
            host: "192.168.1.60",
            port: 7333,
            fingerprint: "SHA256:replacement"
        )
        await #expect(throws: TokenStoreError.keychain(status: errSecInteractionNotAllowed)) {
            try await refusing.save(replacement)
        }

        #expect(await store.load() == .loaded(earlier))
        try await store.clear()
    }

    @Test("a save the Keychain accepts replaces the record it was given")
    func acceptedSaveReplaces() async throws {
        let service = "app.fledgeling.mcprouter.pairing.test.\(UUID().uuidString)"
        let store = KeychainPairingStore(service: service, account: "paired-mac-test")
        try await store.save(FixturePairingService.specimenMac)
        let replacement = PairedMac(
            name: "Replacement Mac",
            pairedAt: Date(timeIntervalSince1970: 1_756_000_000),
            lastSeen: nil,
            host: "192.168.1.60",
            port: 7333,
            fingerprint: "SHA256:replacement"
        )

        try await store.save(replacement)

        #expect(await store.load() == .loaded(replacement))
        try await store.clear()
    }
}
