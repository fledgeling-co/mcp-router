import Foundation
import Testing
@testable import MCPRouterKit

/// The reachability probe when the Mac's address has moved.
///
/// The stored record keeps the Mac's identity (its name, its pairing date and its certificate fingerprint).
/// A browse refreshes only the address. The fingerprint pin decides which endpoint is the Mac, so an endpoint
/// that merely advertises the right name is refused, and one with a different name is accepted when its
/// certificate is the stored one.
@Suite("Pairing rediscovery")
struct PairingRediscoveryTests {
    static let macName = LivePairingServiceTests.macName
    static let fingerprint = LivePairingServiceTests.fingerprint
    static let storedAddress = "192.168.1.24:7333"
    static let movedAddress = "192.168.1.50:7333"

    @Test("a Mac still answering at its stored address is not searched for")
    func storedAddressAnswers() async throws {
        var rig = Rig()
        rig.addresses = [Self.storedAddress: Self.fingerprint]
        try await rig.store.save(storedMac())

        let state = await rig.service().reachability(of: storedMac())

        #expect(state == .reachable)
        #expect(await !(rig.trace.events).contains("browse"))
        #expect(await rig.store.load() == .loaded(storedMac()))
    }

    @Test("a Mac whose address moved is found by browsing, and its record takes the new address")
    func movedMacIsFound() async throws {
        var rig = Rig()
        rig.addresses = [Self.movedAddress: Self.fingerprint]
        rig.discovered = [DiscoveredMac(name: Self.macName, host: "192.168.1.50", port: 7333)]
        try await rig.store.save(storedMac())

        let state = await rig.service().reachability(of: storedMac())

        #expect(state == .reachable)
        #expect(await rig.trace.dialled == [Self.storedAddress, Self.movedAddress])
        #expect(await rig.store.load() == .loaded(storedMac(host: "192.168.1.50", port: 7333)))
    }

    @Test("an endpoint that presents another certificate is not the Mac, and the record keeps its address")
    func impostorIsRefused() async throws {
        var rig = Rig()
        rig.addresses = [Self.movedAddress: "SHA256:deadbeef"]
        rig.discovered = [DiscoveredMac(name: Self.macName, host: "192.168.1.50", port: 7333)]
        try await rig.store.save(storedMac())

        let state = await rig.service().reachability(of: storedMac())

        #expect(state == .notReachable)
        #expect(await rig.store.load() == .loaded(storedMac()))
    }

    @Test("the advertised name orders the probes, and the pin decides which endpoint is the Mac")
    func pinDecidesNotName() async throws {
        var rig = Rig()
        rig.addresses = [
            "192.168.1.50:7333": "SHA256:deadbeef", // named like the Mac, but another certificate
            "192.168.1.60:7333": Self.fingerprint // renamed, but the stored certificate
        ]
        rig.discovered = [
            DiscoveredMac(name: Self.macName, host: "192.168.1.50", port: 7333),
            DiscoveredMac(name: "Renamed Mac", host: "192.168.1.60", port: 7333)
        ]
        try await rig.store.save(storedMac())

        let state = await rig.service().reachability(of: storedMac())

        #expect(state == .reachable)
        #expect(await rig.store.load() == .loaded(storedMac(host: "192.168.1.60", port: 7333)))
    }

    @Test("a Mac nothing advertises and nothing answers stays unreachable, with its record unchanged")
    func nothingFound() async throws {
        var rig = Rig()
        // An empty address book, so the stored address refuses too. A nil book answers everywhere.
        rig.addresses = [:]
        rig.discovered = []
        try await rig.store.save(storedMac())

        let state = await rig.service().reachability(of: storedMac())

        #expect(state == .notReachable)
        #expect(await rig.store.load() == .loaded(storedMac()))
    }

    // MARK: Fixtures

    /// The record as the pairing wrote it. Fixed dates, so a stored record compares equal to the one read
    /// back.
    private func storedMac(host: String = "192.168.1.24", port: Int = 7333) -> PairedMac {
        PairedMac(
            name: Self.macName,
            pairedAt: Date(timeIntervalSince1970: 1_755_000_000),
            lastSeen: Date(timeIntervalSince1970: 1_755_003_600),
            host: host,
            port: port,
            fingerprint: Self.fingerprint
        )
    }
}
