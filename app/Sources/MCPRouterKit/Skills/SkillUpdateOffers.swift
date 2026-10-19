import Foundation

/// The update section's offers, merged from the two reads the Skills board makes.
///
/// Kept beside `SkillPresentation` rather than inside it, so the decision reads on its own and the enum
/// stays within the file and body limits.
public extension SkillPresentation {
    /// The offers the Skills board's update section draws: each plugin Claude's register holds a newer
    /// version of, then each stored entry the update check offers that the register does not already offer.
    ///
    /// The register is the source for installed plugins, so its held version and changelog come first and
    /// win where both sources offer the same plugin. The router's store is a second source, kept so an
    /// offer the store holds and the register does not is still shown. A plugin is listed once however many
    /// of its skills are held.
    static func updateOffers(skills: [Skill], stored: [ExtensionUpdateEntry]) -> [ExtensionUpdateEntry] {
        var seen = Set<String>()
        let registered: [ExtensionUpdateEntry] = skills.compactMap { skill in
            guard let origin = skill.source.pluginOrigin, let held = skill.held else { return nil }
            guard seen.insert(origin.storeName).inserted else { return nil }
            return ExtensionUpdateEntry(
                kind: .plugins,
                name: origin.storeName,
                state: "update-available",
                installed: origin.pluginVersion,
                available: held.pluginVersion,
                hasUpdate: true,
                reason: offered(held.pluginVersion, installed: origin.pluginVersion),
                changelog: held.changelog
            )
        }
        let registeredNames = Set(registered.map(\.name))
        let storedOffers = stored.filter { entry in
            entry.hasUpdate && !(entry.kind == .plugins && registeredNames.contains(entry.name))
        }
        return registered + storedOffers
    }
}
