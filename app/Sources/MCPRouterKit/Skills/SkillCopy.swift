import Foundation

/// The Skills board's copy: the disabled reasons, the marketplace lines, and the empty state.
///
/// A second file rather than a longer one, because the linter caps a type body at 250 lines and
/// splitting on a seam is better than raising the cap. The seam is real: everything here is a
/// *sentence the user reads*, and everything in `SkillPresentation.swift` is a *decision about what
/// to show*. They change for different reasons.
public extension SkillPresentation {
    // MARK: - Disabled reasons

    /// Why every write control on this board is dimmed.
    ///
    /// M4 ships the board read-only, and this is the sentence that says so. The reason is not
    /// timidity: these writes land in files the client applications hold open — a read-modify-write
    /// against a shape this app did not recognise would rewrite the user's whole plugin list and
    /// look exactly like "nothing is installed". `DESIGN.md` §3.4 asks a control that does not
    /// apply to dim in place with a discoverable reason rather than disappear, so the offers stay
    /// visible and say what they are waiting for.
    static let writesNotYetAvailable = """
    Changing what is installed arrives with the item that can do it safely — these files are open in \
    your other apps while this one is running.
    """

    static func autoUpdateReason(for marketplace: Marketplace) -> String {
        if marketplace.source.isLocalDirectory {
            return "A marketplace on this machine updates when you change it — there is nothing to fetch."
        }
        return writesNotYetAvailable
    }

    static func removeReason(for marketplace: Marketplace) -> String {
        if marketplace.suppliedSkillCount > 0 {
            let n = marketplace.suppliedSkillCount
            let noun = n == 1 ? "skill comes" : "skills come"
            return "\(n) installed \(noun) from this marketplace. Remove them first."
        }
        return writesNotYetAvailable
    }

    /// What a marketplace row says it supplies.
    static func supplyLine(for marketplace: Marketplace) -> String {
        guard marketplace.suppliedSkillCount > 0 else { return "Supplies nothing" }
        let skills = marketplace.suppliedSkillCount
        let plugins = marketplace.installedPluginCount
        // A skill count with no plugin count behind it would read "22 skills from 0 plugins",
        // which is a sentence about the router's bookkeeping rather than about the marketplace.
        guard plugins > 0 else {
            return "\(skills) \(skills == 1 ? "skill" : "skills")"
        }
        let skillNoun = skills == 1 ? "skill" : "skills"
        let pluginNoun = plugins == 1 ? "plugin" : "plugins"
        return "\(skills) \(skillNoun) from \(plugins) \(pluginNoun)"
    }

    static func autoUpdateLine(for marketplace: Marketplace) -> String {
        if marketplace.source.isLocalDirectory { return "Local directory" }
        return marketplace.autoUpdate ? "Auto-update on" : "Auto-update off"
    }

    // MARK: - Empty

    static let emptyTitle = "No skills installed yet"
    static let emptyDetail = """
    A skill is a markdown file that teaches an agent how you want a job done. Follow a marketplace \
    and the skills it supplies appear here, across every client that supports them.
    """
}
