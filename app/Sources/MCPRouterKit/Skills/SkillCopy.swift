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

    /// Inspector item 7 has no marketplace record to read from.
    ///
    /// Said out loud rather than drawn as a switch in the off position. A marketplace list that
    /// failed to load is a different fact from auto-update being off, and rendering the second when
    /// only the first is known would be the board asserting a setting nobody read.
    static let autoUpdateUnread = """
    Not shown — the marketplace list didn't load, and the setting lives on the marketplace.
    """

    /// What inspector item 7 shows for one skill — the decision, not the drawing.
    ///
    /// Three outcomes, and the distinction between the last two is the whole reason this is a type
    /// rather than an optional: a skill whose marketplace record did not load is **not** a skill
    /// whose auto-update is off. Collapsing them would have the panel assert a setting nobody read,
    /// which is the one thing this board is not allowed to do.
    enum AutoUpdateItem: Equatable {
        /// A hand-placed skill. It has no marketplace, so there is no setting to state and the
        /// section is omitted rather than rendered empty.
        case notApplicable
        /// There is a marketplace, but its record is not in hand.
        case unread(String)
        /// The setting, as read off the record, with the reason its toggle cannot be moved.
        case setting(line: String, reason: String, isOn: Bool)
    }

    static func autoUpdateItem(for skill: Skill, in marketplaces: [Marketplace]) -> AutoUpdateItem {
        guard let origin = skill.source.pluginOrigin else { return .notApplicable }
        guard let marketplace = marketplaces.first(where: { $0.name == origin.marketplace }) else {
            return .unread(autoUpdateUnread)
        }
        return .setting(
            line: autoUpdateLine(for: marketplace),
            reason: autoUpdateReason(for: marketplace),
            isOn: marketplace.autoUpdate
        )
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
