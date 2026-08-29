import Foundation

public extension VersionLedger {
    /// The version a skill was at when it ran, following the plugin that supplies it when the skill
    /// itself has no boundary of its own.
    ///
    /// Two lookups, in order, and the second is where this machine's shape bites:
    ///
    /// 1. A boundary recorded against the skill's literal name — what a router observing its own
    ///    store appends.
    /// 2. Failing that, the plugin named by the skill's prefix. `ship-feature:ship-feature` is
    ///    supplied by the plugin `ship-feature`, whose version and whose `lastUpdated` are both in
    ///    `installed_plugins.json`.
    ///
    /// **Step 2 refuses when the prefix resolves to more than one plugin, and that is not a corner
    /// case.** Claude's identity for a plugin is `<plugin>@<marketplace>`, and R30 measured **13
    /// plugin names installed from two marketplaces at once** on this machine — `code-review`,
    /// `design-craft`, `ship-feature` and `ux-craft` among them. A lookup that took the first match
    /// would credit runs to whichever marketplace's copy sorted first, and would be wrong roughly
    /// half the time on exactly the plugins this repository's own pipeline uses most.
    func version(ofSkill name: String, at runTimestamp: String) -> VersionAtRun {
        let direct = version(of: .skill, name, at: runTimestamp)
        if case .unestablished = direct {} else { return direct }

        guard let prefix = CapabilityReference.pluginPrefix(of: name) else { return direct }
        let candidates = pluginIdentities(shortName: prefix)
        guard !candidates.isEmpty else { return direct }
        guard candidates.count == 1 else {
            return .unestablished(
                reason: "\(prefix) is installed from \(candidates.count) marketplaces "
                    + "and the run does not say which supplied it"
            )
        }
        return version(of: .plugin, candidates[0], at: runTimestamp)
    }

    /// Every `<plugin>@<marketplace>` identity in the ledger whose plugin half is `shortName`.
    ///
    /// Sorted and de-duplicated, so the count above is a count of distinct plugins rather than of
    /// boundaries — a plugin with four recorded version changes must not read as four marketplaces.
    func pluginIdentities(shortName: String) -> [String] {
        var seen: [String] = []
        for observation in observations where observation.kind == .plugin {
            let identity = observation.name
            let plugin = identity.split(separator: "@", maxSplits: 1).first.map(String.init)
            guard plugin == shortName, !seen.contains(identity) else { continue }
            seen.append(identity)
        }
        return seen.sorted()
    }
}

/// Seeding the ledger from what Claude already wrote down.
///
/// `plugins/installed_plugins.json` carries `version`, `installedAt` and **`lastUpdated`** on every
/// record — measured 2026-08-29, present on all 127 of them. `lastUpdated` is the only statement
/// about the past that exists anywhere on this machine, and turning each one into a boundary is what
/// gives the ledger anything to say before the router's own first reading.
///
/// It is one boundary per record and there will never be a second from this source: the file keeps a
/// current state, not a history. Everything before `lastUpdated` stays dark, which is
/// ``VersionAtRun/unestablished`` rather than a guess.
public enum InstalledPluginsLedgerSeed {
    /// The source string a seeded boundary carries, so a consumer can tell a seeded boundary from
    /// one the router witnessed. They are not the same quality of evidence: `lastUpdated` names the
    /// moment the version actually moved, where a router's own reading names the moment it looked.
    public static let source = "installed_plugins.json:lastUpdated"

    /// Read the register into boundaries.
    ///
    /// - Returns: the observations, and how many records were skipped for want of a name, a version
    ///   or a `lastUpdated`. The second is returned rather than dropped: 127 records producing 100
    ///   boundaries is a different corpus from 100 records producing 100.
    public static func observations(
        in value: JSONValue
    ) -> (observations: [VersionObservation], skipped: Int) {
        guard let plugins = value.member("plugins")?.asObjectMembers else { return ([], 0) }
        var out: [VersionObservation] = []
        var skipped = 0
        for entry in plugins {
            // Every record measured held exactly one element, and the member is an array, so the
            // shape is honoured rather than the observation.
            let elements = entry.value.asArray ?? [entry.value]
            for element in elements {
                guard let version = element.member("version")?.asString?.string, !version.isEmpty,
                      let updated = element.member("lastUpdated")?.asString?.string,
                      VersionLedger.isOrderable(updated)
                else {
                    skipped += 1
                    continue
                }
                out.append(VersionObservation(
                    ts: updated, kind: .plugin, name: entry.key.string,
                    version: version, source: source
                ))
            }
        }
        return (out, skipped)
    }
}
