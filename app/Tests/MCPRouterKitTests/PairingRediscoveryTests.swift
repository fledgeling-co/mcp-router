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

    @Test("a browse is dialled no further than the cap, however many endpoints it lists")
    func browseIsCapped() async throws {
        var rig = Rig()
        // The Mac is the twelfth endpoint advertised, past the eight a probe will dial.
        rig.addresses = ["192.168.1.112:7333": Self.fingerprint]
        rig.discovered = (1 ... 12).map { DiscoveredMac(
            name: "Other \($0)",
            host: "192.168.1.\(100 + $0)",
            port: 7333
        ) }
        try await rig.store.save(storedMac())

        let state = await rig.service().reachability(of: storedMac())

        #expect(state == .notReachable)
        // The stored address, then the first eight endpoints the browse named, and nothing after them.
        #expect(await rig.trace.dialled.count == 9)
        #expect(await rig.store.load() == .loaded(storedMac()))
    }

    @Test("endpoints that accept and never answer, ahead of the Mac, do not hold the probe to its timeout")
    func stalledDecoysDoNotHideTheMac() async throws {
        var rig = Rig()
        rig.timeout = .seconds(1)
        // Seven endpoints advertise the Mac's own name and stall, so they are first in the likely group.
        // Dialled one at a time, the first holds the probe until its timeout and the Mac is never tried.
        let decoys = (1 ... 7).map { "192.168.1.\(200 + $0)" }
        rig.stalled = Set(decoys.map { "\($0):7333" })
        rig.addresses = [Self.movedAddress: Self.fingerprint]
        rig.discovered = decoys.map { DiscoveredMac(name: Self.macName, host: $0, port: 7333) }
            + [DiscoveredMac(name: Self.macName, host: "192.168.1.50", port: 7333)]
        try await rig.store.save(storedMac())

        let state = await rig.service().reachability(of: storedMac())

        #expect(state == .reachable)
        #expect(await rig.store.load() == .loaded(storedMac(host: "192.168.1.50", port: 7333)))
    }

    @Test("eight stalled endpoints ahead of the Mac use up the cap, and the Mac is not dialled")
    func capStillBoundsTheDials() async throws {
        var rig = Rig()
        rig.timeout = .seconds(1)
        // The cap is what bounds the dials a LAN peer can cause, so eight decoys ahead of the Mac exhaust
        // it. This pins that outcome rather than hiding it: the Mac is the ninth endpoint and is not tried.
        let decoys = (1 ... 8).map { "192.168.1.\(200 + $0)" }
        rig.stalled = Set(decoys.map { "\($0):7333" })
        rig.addresses = [Self.movedAddress: Self.fingerprint]
        rig.discovered = decoys.map { DiscoveredMac(name: Self.macName, host: $0, port: 7333) }
            + [DiscoveredMac(name: Self.macName, host: "192.168.1.50", port: 7333)]
        try await rig.store.save(storedMac())

        let state = await rig.service().reachability(of: storedMac())

        #expect(state == .notReachable)
        #expect(await rig.trace.dialled.count == 9)
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
