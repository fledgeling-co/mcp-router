import Foundation
import Testing
@testable import MCPRouterKit

/// Which pairing service the phone composes, decided from the build configuration and environment
/// passed in, so a Debug test run can assert the Release branch.
@Suite("Phone pairing factory")
struct PhonePairingFactoryTests {
    /// Every named scenario, set as the Debug environment variable. Release must ignore all of them.
    static let everyScenarioVariable: [[String: String]] =
        FixturePairingService.Scenario.allCases.map { [PhonePairingFactory.scenarioVariable: $0.rawValue] }

    @Test("a Release build always composes the live service, whatever the environment says")
    func releaseIsAlwaysLive() {
        for environment in Self.everyScenarioVariable {
            #expect(PhonePairingFactory.choice(isDebugBuild: false, environment: environment) == .live)
        }
    }

    @Test("a Debug build with nothing set composes the live service")
    func debugDefaultIsLive() {
        #expect(PhonePairingFactory.choice(isDebugBuild: true, environment: [:]) == .live)
    }

    @Test("a Debug build with a named scenario composes that fixture")
    func debugNamedScenarioIsFixture() {
        let environment = [PhonePairingFactory.scenarioVariable: "alreadyUsed"]
        #expect(PhonePairingFactory
            .choice(isDebugBuild: true, environment: environment) == .fixture(.alreadyUsed))
    }

    @Test("an unrecognised scenario name falls back to the live service, not to a fixture")
    func unknownScenarioIsLive() {
        let environment = [PhonePairingFactory.scenarioVariable: "pairedForever"]
        #expect(PhonePairingFactory.choice(isDebugBuild: true, environment: environment) == .live)
    }

    @Test("the live choice composes the live service")
    func liveChoiceIsLiveService() {
        let service = PhonePairingFactory.service(
            for: .live,
            deviceName: "Luke's iPhone",
            records: InMemoryPairingStore(),
            keys: InMemoryPhoneKeyStore()
        )
        #expect(service is LivePairingService)
    }

    @Test("a fixture choice composes the fixture, and only that")
    func fixtureChoiceIsFixture() {
        let service = PhonePairingFactory.service(
            for: .fixture(.paired),
            deviceName: "Luke's iPhone",
            records: InMemoryPairingStore(),
            keys: InMemoryPhoneKeyStore()
        )
        #expect(service is FixturePairingService)
    }

    @Test("the phone's name is kept as sent when it is short")
    func shortNameIsKept() {
        #expect(PhonePairingFactory.phoneName(from: "Luke's iPhone") == "Luke's iPhone")
    }

    @Test("a name longer than the router accepts is clamped to 64 characters")
    func longNameIsClamped() {
        let name = PhonePairingFactory.phoneName(from: String(repeating: "a", count: 200))
        #expect(name.count == 64)
    }

    @Test("the clamp counts UTF-16 units, the way the router's length check does")
    func clampCountsUTF16() {
        // Each emoji is one Character but two UTF-16 units. Sixty-four units is thirty-two of them.
        let name = PhonePairingFactory.phoneName(from: String(repeating: "🫥", count: 40))
        #expect(name.utf16.count == 64)
        #expect(name.count == 32)
    }

    @Test("surrounding whitespace is trimmed before the length is taken")
    func whitespaceIsTrimmed() {
        #expect(PhonePairingFactory.phoneName(from: "  Luke's iPhone \n") == "Luke's iPhone")
    }

    @Test("a name that is empty once trimmed is replaced, since the router refuses an empty name")
    func emptyNameGetsAFallback() {
        #expect(PhonePairingFactory.phoneName(from: "   ") == "iPhone")
        #expect(PhonePairingFactory.phoneName(from: "") == "iPhone")
    }

    @Test("the live service browses with Bonjour, so a Mac whose address has moved can be found")
    func liveServiceBrowsesWithBonjour() throws {
        let service = try #require(PhonePairingFactory.service(
            for: .live,
            deviceName: "Luke's iPhone",
            records: InMemoryPairingStore(),
            keys: InMemoryPhoneKeyStore()
        ) as? LivePairingService)
        let discovery = Mirror(reflecting: service).children.first { $0.label == "discovery" }?.value
        #expect(discovery is BonjourPairingDiscovery)
    }
}
