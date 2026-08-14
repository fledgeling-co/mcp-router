import Foundation

/// The five checks MCP Router can genuinely perform against a skill.
///
/// **A skill is never executed by the router, and no future router item changes that.** A skill is
/// markdown the *client* loads into an agent's context; it never traverses the router, so no
/// execution of it is observable to the process that would have to grade it. Everything here is
/// therefore structural — reachability, versioning, provenance — and nothing reports how a skill
/// behaved when an agent used it, because nothing in this product can know.
public enum SkillChecks {
    /// The five, in the order the inspector renders them.
    public static func all(_ skill: Skill, clients: [SkillClient]) -> [CheckResult] {
        [
            reachable(skill, clients: clients),
            versioned(skill),
            originUnchanged(skill),
            updateWantsNoMore(skill),
            described(skill),
        ]
    }

    /// At least one client can load it.
    ///
    /// **Two types carry an `unreadable` case and they are not the same thing.**
    /// `SkillPresence.unreadable` is per-skill-per-client and lives in `Skill.presence`;
    /// `SkillClientStatus.unreadable` is per-client and lives in `SkillClient.status`. Either is
    /// enough to suspend the judgement, and both are read — the spec gate caught the first draft
    /// naming only one of them.
    ///
    /// **An absent `presence` key is not evidence of absence.** `presence` is a dictionary, not an
    /// exhaustive map, so a client whose directory could not be read may have no key at all rather
    /// than an `.unreadable` one. Treating a missing key as "not installed here" would let a skill be
    /// declared loadable by nobody on the strength of a lookup that never happened.
    public static func reachable(_ skill: Skill, clients: [SkillClient]) -> CheckResult {
        let capable = clients.filter(\.supportsSkills)

        if capable.contains(where: { skill.presence[$0.id] == .present }) {
            return CheckResult(.reachable, .passed)
        }

        let unreadable = capable.filter { client in
            client.status == .unreadable || skill.presence[client.id] == .unreadable
        }
        guard unreadable.isEmpty else {
            return CheckResult(
                .reachable,
                .unknown,
                reason: CheckCopy.reachabilityUnknown(clients: unreadable.map(\.displayName))
            )
        }

        return CheckResult(
            .reachable,
            .failed,
            reason: CheckCopy.notLoadableAnywhere(clientCount: capable.count)
        )
    }

    /// It carries a version a result can be stamped against.
    ///
    /// A `.standalone` skill has no version field anywhere in `SkillSource` — M4 modelled it as a
    /// closed enum whose standalone case carries only a path — so this is not a tidiness nag. It is
    /// the pane explaining why that subject's history is empty.
    public static func versioned(_ skill: Skill) -> CheckResult {
        guard skill.source.pluginOrigin != nil else {
            return CheckResult(.versioned, .failed, reason: CheckCopy.standaloneUnversioned)
        }
        return CheckResult(.versioned, .passed)
    }

    /// Its marketplace still resolves where the router first saw it.
    ///
    /// `.notApplicable` for a standalone skill: it has no marketplace, so an unmoved origin is not
    /// something that can be true of it. The first draft reported a confirmation here, which asserted
    /// a fact about an entity that does not exist.
    public static func originUnchanged(_ skill: Skill) -> CheckResult {
        guard skill.source.pluginOrigin != nil else {
            return CheckResult(.originUnchanged, .notApplicable, reason: CheckCopy.standaloneNoOrigin)
        }
        guard let provenance = skill.provenance else {
            return CheckResult(.originUnchanged, .passed)
        }
        return CheckResult(
            .originUnchanged,
            .failed,
            reason: CheckCopy.originMoved(
                firstSeen: provenance.firstSeenSource,
                current: provenance.currentSource,
                at: provenance.firstSeenAt
            )
        )
    }

    /// Any newer version held asks for nothing extra.
    ///
    /// `.notApplicable` when no version is held. Most skills have none, and the first draft reported
    /// a confirmation for every one of them — a pass for a question that was never asked, which is
    /// exactly the defect `callsSucceed` exists to refuse.
    public static func updateWantsNoMore(_ skill: Skill) -> CheckResult {
        guard let held = skill.held else {
            return CheckResult(.updateWantsNoMore, .notApplicable, reason: CheckCopy.noVersionHeld)
        }
        guard held.wantsMore else {
            return CheckResult(.updateWantsNoMore, .passed)
        }
        return CheckResult(
            .updateWantsNoMore,
            .failed,
            reason: CheckCopy.heldVersionWantsMore(
                version: held.pluginVersion,
                capabilities: held.addedCapabilities
            )
        )
    }

    /// Its `SKILL.md` declares a description an agent can route on.
    ///
    /// Binary, and deliberately so. The first draft claimed a "not observed" state for a skill whose
    /// directory could not be read — **there is no such field**. `Skill` carries no per-skill
    /// readability, and a skill whose own directory could not be read does not appear in
    /// `SkillsResponse.skills` at all, so the state was unreachable and the column described nothing.
    public static func described(_ skill: Skill) -> CheckResult {
        guard let description = skill.description,
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return CheckResult(.described, .failed, reason: CheckCopy.noDescription)
        }
        return CheckResult(.described, .passed)
    }

    /// The field and value each check was computed from, for the inspector. See `ServerChecks.input`.
    public static func input(_ check: CheckID, _ skill: Skill, clients: [SkillClient]) -> String {
        switch check {
        case .reachable:
            let capable = clients.filter(\.supportsSkills)
            let rendered = capable
                .map { "\($0.displayName)=\(skill.presence[$0.id]?.rawValue ?? "—")" }
                .joined(separator: " · ")
            return rendered.isEmpty ? "no skills-capable clients" : rendered
        case .versioned:
            return "source = \(skill.source.pluginOrigin.map { "plugin \($0.pluginVersion)" } ?? "standalone")"
        case .originUnchanged:
            return "provenance = \(skill.provenance.map { "\($0.firstSeenSource) → \($0.currentSource)" } ?? "nil")"
        case .updateWantsNoMore:
            return "held = \(skill.held.map { "\($0.pluginVersion), adds \($0.addedCapabilities.count)" } ?? "nil")"
        case .described:
            return "description = \(skill.description.map { "\($0.count) characters" } ?? "nil")"
        case .indexes, .declaresTools, .authorized, .surfaceApproved, .operative, .callsSucceed:
            return "not a skill check"
        }
    }
}
