import Foundation

/// What this build calls itself, passed into the Settings window rather than read there.
///
/// The Advanced pane draws one line naming the running version, and the value has exactly one
/// honest source: the process's own bundle. `no-raw-design-values.sh`'s A36 rule forbids the name
/// `Bundle` anywhere under `MCPRouterUI`'s gated directories — the Mac app talks to the router over
/// one loopback channel and reads nothing else itself — so the read happens in
/// `app/MCPRouter/MCPRouterApp.swift`, which is outside that rule, and the *value* travels in.
///
/// **Every field is optional and the unknown case is drawn rather than defaulted.** A process with
/// no `Info.plist` — every `swift test` run, and the `MeasureDump` executable — has no version, and
/// a placeholder there would be exactly the invented figure `DESIGN.md` §6 forbids.
public struct BuildIdentity: Equatable, Sendable {
    public let name: String?
    public let version: String?
    public let build: String?

    public init(name: String?, version: String?, build: String?) {
        self.name = name
        self.version = version
        self.build = build
    }

    /// Read from a bundle's own keys. Absent or empty values stay absent.
    public init(bundle: Bundle) {
        func string(_ key: String) -> String? {
            let value = bundle.object(forInfoDictionaryKey: key) as? String
            return value?.isEmpty == false ? value : nil
        }
        self.init(
            name: string("CFBundleName") ?? string("CFBundleDisplayName"),
            version: string("CFBundleShortVersionString"),
            build: string("CFBundleVersion")
        )
    }

    /// The fixture identity the measurement harness renders under.
    ///
    /// `MeasureDump` is an unsigned SwiftPM executable with no `Info.plist`, so reading the real
    /// bundle there would draw the unknown line on every run and the footer would never be
    /// measured. Declared as a fixture for the same reason `FixtureControlAPIClient` serves fixture
    /// servers to it: what the harness measures is the shape of the surface, and a fixture is how
    /// this repo already gives it one.
    public static let measured = BuildIdentity(name: "MCP Router", version: "0.0.0", build: "0")

    /// The line the Advanced pane draws, or `nil` when this process carries no version to state.
    ///
    /// The mock's footer also claims `Developer ID signed and notarised`. Nothing in this process
    /// observes its own signature, and every build in this repository is unsigned, so that clause is
    /// not carried — it would be two invented facts sitting beside two observed ones.
    public var summary: String? {
        guard let version else { return nil }
        let product = name ?? "MCP Router"
        guard let build else { return "\(product) \(version)" }
        return "\(product) \(version) (build \(build))"
    }
}
