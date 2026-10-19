import Foundation

/// Which pairing service the phone composes, and the one rule that must never bend.
///
/// **A Release build always gets the live service.** The fixture would otherwise let a shipped phone
/// report "Paired." for a Mac it never reached, which `DESIGN.md` §6 forbids. The fixture is reachable
/// only in a Debug build, and only when `scenarioVariable` names one of its scenarios on purpose.
///
/// The decision is a pure function over `(isDebugBuild, environment)`, so a Debug test run can assert
/// the Release branch. `ShellPairingFactory` and `PhoneCameraFactory` use the same shape for the same
/// reason.
public enum PhonePairingFactory {
    /// The variable a Debug build reads to choose a fixture scenario.
    public static let scenarioVariable = "MCPROUTER_PHONE_PAIRING"

    /// The router refuses a `phoneName` longer than this. It counts UTF-16 code units, as JavaScript's
    /// `length` does, so this clamp counts the same way (`src/pairing-listener.ts`, `PHONE_NAME_MAX`).
    public static let maxPhoneNameLength = 64

    /// Stands in for a device name that is empty once trimmed. The router refuses an empty name.
    static let fallbackPhoneName = "iPhone"

    public enum Choice: Equatable, Sendable {
        /// The network transport. What ships, and the only choice a Release build can make.
        case live
        /// A named fixture. Debug only, and only when chosen deliberately.
        case fixture(FixturePairingService.Scenario)
    }

    public static func choice(isDebugBuild: Bool, environment: [String: String]) -> Choice {
        guard isDebugBuild else { return .live }
        guard let named = environment[scenarioVariable],
              let scenario = FixturePairingService.Scenario(rawValue: named)
        else {
            // An unset or unrecognised name is the live service. A typo should show the real behaviour
            // rather than quietly select a fixture.
            return .live
        }
        return .fixture(scenario)
    }

    /// The choice this build and this process actually make.
    public static func currentChoice(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Choice {
        #if DEBUG
            choice(isDebugBuild: true, environment: environment)
        #else
            choice(isDebugBuild: false, environment: environment)
        #endif
    }

    /// The service for a choice. Takes its stores as parameters, so a test can compose the live service
    /// over in-memory stores.
    public static func service(
        for choice: Choice,
        deviceName: String,
        records: any PairingRecordStore,
        keys: any PhoneKeyStore
    ) -> any PairingService {
        switch choice {
        case .live:
            LivePairingService(
                transport: NetworkPairingTransport(),
                keys: keys,
                records: records,
                discovery: BonjourPairingDiscovery(),
                phoneName: phoneName(from: deviceName)
            )
        case let .fixture(scenario):
            FixturePairingService(scenario)
        }
    }

    /// The service this build composes, over the stores the app uses.
    public static func makeService(
        deviceName: String,
        records: any PairingRecordStore,
        keys: any PhoneKeyStore = KeychainPhoneKeyStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any PairingService {
        service(
            for: currentChoice(environment: environment),
            deviceName: deviceName,
            records: records,
            keys: keys
        )
    }

    /// The name the phone sends in `pair.request`: trimmed, clamped to what the router accepts, and never
    /// empty.
    ///
    /// The clamp is by UTF-16 units and stops before a unit that would overflow, so a surrogate pair is
    /// never split. Trimming happens before and after, because the router trims before it checks
    /// emptiness.
    public static func phoneName(from deviceName: String) -> String {
        var clamped = ""
        for character in deviceName.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard clamped.utf16.count + character.utf16.count <= maxPhoneNameLength else { break }
            clamped.append(character)
        }
        let trimmed = clamped.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallbackPhoneName : trimmed
    }
}
