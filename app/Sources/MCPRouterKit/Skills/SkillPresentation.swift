import Foundation

/// Every decision the Skills board makes, with no UI framework in sight.
///
/// The split follows the Servers board's, and for its stated reason: that board's two prototype
/// failures were *wrong answers from a branch* rather than styling defects, and a branch only a
/// running app can exercise is a branch that ships wrong. Everything here is reachable from a test
/// without a host, so the rules below are checked rather than hoped for.
///
/// **The rule this file exists to enforce.** `DESIGN.md` §6 forbids displaying anything the router
/// does not observe. Two of the decisions here are that rule in code:
///
/// - a skill with no plugin behind it renders `unversioned` **in the body face**, because it is a
///   statement about the skill rather than a reading off it, and §2 reserves monospace for
///   instrument data;
/// - a client whose directory could not be read renders an *unknown* slot, never an empty one,
///   because an empty slot asserts the skill is absent somewhere nobody managed to look.
public enum SkillPresentation {
    /// The Skills header action.
    ///
    /// `Add marketplace…`, which is what `prototype.html:786` puts in that slot and what
    /// `MenuCommand.addMarketplace` has always said. The board shipped `Manage marketplaces…`, so
    /// the menu item and the button that open the same sheet named it two different things —
    /// DEF-012. Stated once here so they cannot drift again.
    public static let marketplacesAction = "Add marketplace…"

    // MARK: - Header

    /// The subtitle under "Skills".
    ///
    /// Returns an empty string while loading. A count that is not yet known is not a count, and
    /// "Loading…" in the place a number belongs is a worse answer than nothing there.
    public static func subtitle(for response: SkillsResponse) -> String {
        let skills = response.skills.count
        let marketplaces = Set(
            response.skills.compactMap { $0.source.pluginOrigin?.marketplace }
        ).count
        // "from" rather than a middot, matching the spec's authored wording. This counts the
        // marketplaces **these rows came from**; the marketplaces sheet counts everything followed
        // and says "followed", so the two numbers are never read as the same claim.
        let skillNoun = skills == 1 ? "skill" : "skills"
        let marketNoun = marketplaces == 1 ? "marketplace" : "marketplaces"
        var parts = ["\(skills) \(skillNoun) from \(marketplaces) \(marketNoun)"]
        let held = response.skills.filter { $0.held?.wantsMore ?? false }.count
        // Omitted entirely at zero rather than rendered "0 held", which reads as a warning that
        // resolved rather than a condition that never applied.
        if held > 0 { parts.append("\(held) held for review") }
        return parts.joined(separator: " · ")
    }

    /// Stated once on the populated board, as a property of the product rather than of any row.
    ///
    /// This sentence is why there is no runs column and no eval column. Saying it once is a claim
    /// that is true; an empty cell on every row would be a claim about each skill that the router
    /// cannot make, because it cannot tell "never run" from "run constantly, invisibly to me".
    ///
    /// **It used to end "evaluations arrive with Evals", and both halves of that were wrong.**
    /// `Evals` is a pane name that no longer exists — M9 renamed the sidebar row, the window title,
    /// the View-menu item and the board's own heading to `Checks`, and a forward reference left
    /// pointing at the old word sends a reader to a row that is not there. `spec-M7.md:45` had
    /// already recorded this sentence as a finding and left it.
    ///
    /// The worse half is the promise. There is **no eval runner in this product in any form**, so
    /// "evaluations arrive" named a future the product has no route to, and it contradicted the very
    /// pane it pointed at: `CheckCopy.evalsSubtitle` tells the reader, permanently, that "No
    /// model-graded evaluation exists in this product." One surface promised what the other denied.
    /// The replacement points at Checks for what the router *did* observe and repeats the denial
    /// rather than contradicting it.
    public static let observationFooter = """
    Run counts and evaluation results are not shown. A skill is loaded into an agent's context by \
    the client and never reaches the router, so the router does not see it run. Checks reports what \
    the router observed for itself, and no model-graded evaluation exists in this product.
    """

    // MARK: - Filters

    public enum Filter: String, CaseIterable, Sendable, Identifiable {
        case all
        case held
        case local
        case needsAttention

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .all: "All"
            case .held: "Held"
            case .local: "Local"
            case .needsAttention: "Needs attention"
            }
        }

        func matches(_ skill: Skill) -> Bool {
            switch self {
            case .all: true
            case .held: skill.held?.wantsMore ?? false
            case .local: skill.source.isStandalone
            case .needsAttention: skill.needsAttention
            }
        }
    }

    public static func rows(_ skills: [Skill], filter: Filter, search: String) -> [Skill] {
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return skills.filter { skill in
            guard filter.matches(skill) else { return false }
            guard !trimmed.isEmpty else { return true }
            if skill.name.lowercased().contains(trimmed) { return true }
            if let origin = skill.source.pluginOrigin {
                return origin.plugin.lowercased().contains(trimmed)
                    || origin.marketplace.lowercased().contains(trimmed)
            }
            return false
        }
    }

    /// The count beside a filter's name, or `nil` when it is zero and should carry no badge.
    ///
    /// Counts the **searched** set, so the number on a segment is the number of rows selecting it
    /// would show. Counting the unsearched set put `Held 1` above a list saying nothing was held.
    public static func count(_ skills: [Skill], filter: Filter, search: String = "") -> Int? {
        let n = rows(skills, filter: filter, search: search).count
        return n == 0 ? nil : n
    }

    /// What an empty result inside a filter says.
    ///
    /// Never the first-run empty state, which would claim the user has no skills when they have
    /// dozens and have merely narrowed to a filter nothing matches.
    /// A named type rather than a tuple: three anonymous strings at a call site is three chances
    /// to render the detail where the title belongs.
    public struct EmptyFilterMessage: Equatable, Sendable {
        public var title: String
        public var detail: String
        public var action: String

        /// Whether the button clears the search rather than widening the filter.
        ///
        /// Carried on the message rather than re-derived at the call site, because the call site
        /// cannot re-derive it correctly: the emptiness decision trims the search, so a search of
        /// `"   "` is *not* a search here, while `search.isEmpty` at the view says it is. Reading
        /// that flag the view offered "Show all skills" and then cleared the whitespace instead,
        /// leaving the filter narrow and the list still empty — a button that appeared to do
        /// nothing. One judgement, made once, decides both the label and what the label does.
        public var clearsSearch: Bool
    }

    /// What an empty result says, given both the filter AND the search.
    ///
    /// Taking the search too is the whole point. An earlier version keyed on the filter alone, so
    /// the most common way this board empties — the `All` filter with a search matching nothing —
    /// fell through to `nil` and the board drew its column headers over blank space with no message
    /// at all. Worse, under a narrower filter it printed "nothing is waiting" while the segment
    /// above still read `Held 1`, because the badge counted the unsearched set: two claims on one
    /// screen, one of them false.
    public static func emptyInFilter(_ filter: Filter, search: String = "") -> EmptyFilterMessage? {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return EmptyFilterMessage(
                title: "Nothing matches \u{201C}\(query)\u{201D}",
                detail: filter == .all
                    ? "No skill's name, plugin or marketplace contains that."
                    : "No skill under \(filter.title.lowercased()) matches that. Another filter may.",
                action: "Clear search",
                clearsSearch: true
            )
        }
        switch filter {
        case .all:
            return nil
        case .held:
            return EmptyFilterMessage(
                title: "No skills are held for review",
                detail: """
                A new version is held when it asks for more than the one you have. Nothing is \
                waiting.
                """,
                action: "Show all skills",
                clearsSearch: false
            )
        case .local:
            return EmptyFilterMessage(
                title: "No skills were added by hand",
                detail: """
                Every skill here came from a marketplace. A skill you place in a client's skills \
                folder yourself would appear under this filter.
                """,
                action: "Show all skills",
                clearsSearch: false
            )
        case .needsAttention:
            return EmptyFilterMessage(
                title: "Nothing needs a decision",
                detail: """
                Nothing is held for review and no marketplace has changed hands since this Mac \
                first saw it.
                """,
                action: "Show all skills",
                clearsSearch: false
            )
        }
    }

    // MARK: - The version cell

    /// How a version reads, and which face it is set in.
    ///
    /// `isInstrument` is part of the answer rather than a styling choice made at the call site,
    /// because it is the difference between a reading and a statement. `2.2.0` is a value the
    /// router read off a file; `unversioned` is the app saying there was no value to read.
    public struct VersionCell: Equatable, Sendable {
        public var text: String
        public var isInstrument: Bool
        public var isHeld: Bool
    }

    public static func version(for skill: Skill) -> VersionCell {
        guard let origin = skill.source.pluginOrigin else {
            // A hand-placed skill has no version anywhere on disk: SKILL.md frontmatter carries
            // `name` and `description` and nothing else. Printing "1.0.0" here would be invented.
            return VersionCell(text: "unversioned", isInstrument: false, isHeld: false)
        }
        if let held = skill.held, held.wantsMore {
            return VersionCell(
                text: "\(origin.pluginVersion) → \(held.pluginVersion)",
                isInstrument: true,
                isHeld: true
            )
        }
        return VersionCell(text: origin.pluginVersion, isInstrument: true, isHeld: false)
    }

    /// The line under a skill's name.
    ///
    /// Names the **plugin** as well as the marketplace when the plugin supplies more than one skill,
    /// because the version on this row belongs to that plugin and is shared with its siblings. A
    /// row that showed only the marketplace would leave thirty rows apparently claiming thirty
    /// independent versions of the same number.
    public static func sourceLine(for skill: Skill) -> String {
        guard let origin = skill.source.pluginOrigin else {
            return "local — not from a marketplace"
        }
        if origin.siblingSkillCount > 1 {
            return "\(origin.plugin) · \(origin.marketplace)"
        }
        return origin.marketplace
    }

    /// The provenance warning that replaces the source line when a marketplace has moved.
    public static func provenanceLine(for skill: Skill) -> String? {
        guard let provenance = skill.provenance else { return nil }
        return "Owner changed — was \(provenance.firstSeenSource)"
    }

    // MARK: - Slots

    public enum SlotState: Equatable, Sendable {
        case on
        case off
        /// That client's directory could not be read, so whether the skill is there is unknown.
        case unknown
    }

    public static func slot(_ skill: Skill, client: SkillClient) -> SlotState {
        switch skill.presence[client.id] {
        case .present: .on
        case .unreadable: .unknown
        case .absent, nil: .off
        }
    }

    /// The short label on a slot. Two letters, from the client the router named — never a
    /// hardcoded list, so a client the router stops reporting stops having a slot.
    public static func slotLabel(for client: SkillClient) -> String {
        switch client.id {
        case "claudeCode": "CC"
        case "codex": "CX"
        case "cursor": "CR"
        case "opencode": "OC"
        default: String(client.displayName.prefix(2)).uppercased()
        }
    }

    // MARK: - The inspector's client sentence

    /// Which clients hold this skill, which supported ones do not, and which have no mechanism.
    ///
    /// All six are accounted for. The third sentence is why the table has four slots and not six:
    /// without it, two clients are missing from the board with no explanation anywhere.
    public static func clientSentences(
        for skill: Skill,
        in response: SkillsResponse
    ) -> [String] {
        var lines: [String] = []
        let supported = response.slotClients
        let present = supported.filter { skill.presence[$0.id] == .present }
        let unknown = supported.filter { skill.presence[$0.id] == .unreadable }
        let absent = supported.filter { skill.presence[$0.id] == .absent }

        if present.isEmpty {
            lines.append("Not in any client that supports skills")
        } else {
            lines.append(present.map(\.displayName).joined(separator: " · "))
        }
        if !absent.isEmpty {
            lines.append("Not in \(list(absent.map(\.displayName)))")
        }
        if !unknown.isEmpty {
            lines.append("\(list(unknown.map(\.displayName))) could not be read, so this is unknown")
        }
        let unsupported = response.unsupportedClients.map(\.displayName)
        if !unsupported.isEmpty {
            lines
                .append("\(list(unsupported)) \(unsupported.count == 1 ? "has" : "have") no skills mechanism")
        }
        return lines
    }

    public static func list(_ items: [String]) -> String {
        switch items.count {
        case 0: ""
        case 1: items[0]
        case 2: "\(items[0]) and \(items[1])"
        default: "\(items.dropLast().joined(separator: ", ")) and \(items[items.count - 1])"
        }
    }

    // MARK: - Partial

    /// What the Partial banner says when a client's directory could not be read.
    ///
    /// Names the client, the consequence for what is on screen, the path, and the reason —
    /// `DESIGN.md` §5's "say what arrived and what did not, with the reason", in that order.
    public static func partialNote(for response: SkillsResponse) -> String? {
        let broken = response.clients.filter { $0.status == .unreadable }
        guard !broken.isEmpty else { return nil }
        let names = list(broken.map(\.displayName))
        let detail = broken
            .map { "\($0.root ?? $0.displayName) — \($0.reason ?? "could not be read")" }
            .joined(separator: "; ")
        return """
        \(names) could not be read, so anything installed only there is missing from this list and \
        the slot column understates for every row. \(detail).
        """
    }

    // MARK: - The held-version review

    public static func heldTitle(_ skill: Skill) -> String {
        guard let held = skill.held, let origin = skill.source.pluginOrigin else { return "" }
        return "\(origin.plugin) \(held.pluginVersion) wants more than \(origin.pluginVersion)"
    }

    public static func heldBody(_ skill: Skill) -> String {
        guard let held = skill.held else { return "" }
        let affected = held.affectedSkillCount
        let scope = affected > 1
            ? " Promoting it moves all \(affected) skills this plugin supplies."
            : ""
        return """
        It was fetched and is being kept aside rather than installed — every client is still \
        running \(skill.source.pluginOrigin?.pluginVersion ?? "the installed version").\(scope)
        """
    }

    /// One quiet sentence naming how the capability list was derived, so it is not mistaken for a
    /// manifest the plugin author wrote.
    public static let capabilityDerivation = """
    As reported by the router, from the skill's own text rather than from anything its author \
    declared. No skill format carries a capability manifest, so this is a reading and can be \
    incomplete.
    """
}
