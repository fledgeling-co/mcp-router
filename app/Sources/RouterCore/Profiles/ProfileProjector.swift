import Foundation

/// Derives a ``ProfileProjection`` from a profile, the router's own store, and the skill roots.
///
/// Split from the projection type so neither file carries both the model and the derivation, and
/// so this one can be read against `spec-F8.md` §3's table row by row.
public enum ProfileProjector {
    /// The sentence every skill step carries. Written once, because it is the finding of the item
    /// rather than a note on a step: `spec-F8.md` §1.3.
    static let skillReach = ProfileReach.durable(
        note: "the link would persist; no protocol makes a live session re-read a skill, and the "
            + "socket half enqueues a slash command as text (spec-R29 §1.1)"
    )

    /// The router's served tool set is the one thing a profile touches that a protocol can announce
    /// — and the announcement lives in the other binary.
    static let serverReach = ProfileReach.tellElsewhere(
        mechanism: "notifications/tools/list_changed reaches an attached session in ~87ms "
            + "(spec-R29 §1.2); it is implemented in src/livereload.ts and this router has no "
            + "counterpart"
    )

    /// Kept for the step nothing here emits yet, and emitted the moment a projection has to touch a
    /// harness's MCP configuration — which is what `spec-F8.md` §5's F8-C1 would need.
    static let harnessConfigReach = ProfileReach.refused(
        reason: "this router does not write another program's MCP configuration (spec-R7 §7, "
            + "scripts/lint/no-harness-config-writes.sh)"
    )

    public static func project(
        profile: ProfileRecord,
        store: any ExtensionStoring,
        roots: [SkillRootInventory],
        upstreamNames: [String],
        clientsWithoutRoot: [MCPClient]
    ) -> ProfileProjection {
        var steps: [ProfileStep] = []
        let held = Set(store.list(.skills).records.map(\.name))
        let readable = roots.filter { $0.unreadable == nil && $0.exists }

        // Skills. One step per (skill, root) pair, so a name satisfied in one harness and missing
        // in another produces two rows rather than one summary that hides the asymmetry —
        // `spec-F8.md` §1.1 measured the intersection of two roots at ONE name, so a per-profile
        // summary would be the least informative shape available.
        for name in profile.skills {
            guard held.contains(name) else {
                steps.append(ProfileStep(
                    client: nil, subject: .storeEntry(kind: .skills, name: name),
                    action: .missingFromStore, reach: skillReach
                ))
                continue
            }
            for root in readable {
                steps.append(ProfileStep(
                    client: root.client,
                    subject: .skill(name: name, root: root.path),
                    action: action(for: name, in: root),
                    reach: skillReach
                ))
            }
        }

        // Plugins and marketplaces. The router holds them and no harness root on this machine is a
        // directory of them, so there is nowhere to project onto and the step says so rather than
        // inventing a destination.
        for kind in [ExtensionKind.plugins, .marketplaces] {
            let names = Set(store.list(kind).records.map(\.name))
            for name in profile.names(for: kind) {
                steps.append(ProfileStep(
                    client: nil, subject: .storeEntry(kind: kind, name: name),
                    action: names.contains(name) ? .satisfied : .missingFromStore,
                    reach: skillReach
                ))
            }
        }

        // Servers. Against the live upstream map, which is the same source `GET /servers` reads.
        let served = Set(upstreamNames)
        for name in profile.servers {
            steps.append(ProfileStep(
                client: nil, subject: .server(name: name),
                action: served.contains(name) ? .satisfied : .add,
                reach: serverReach
            ))
        }

        return ProfileProjection(
            profile: profile,
            steps: steps,
            withoutSkillRoot: clientsWithoutRoot,
            unreadableRoots: roots.compactMap { $0.unreadable == nil ? nil : $0.path }
        )
    }

    /// `repair` before `add`, and the order is the finding.
    ///
    /// A dangling link **occupies its name**, so a projection that treated it as absent would offer
    /// to create something that is already there. 27 of Cursor's 87 entries were in exactly this
    /// state when F8 was specified.
    static func action(for name: String, in root: SkillRootInventory) -> ProfileStep.Action {
        guard let entry = root.entry(named: name) else { return .add }
        switch entry.kind {
        case let .dangling(target): return .repair(target: target)
        case .directory, .linked: return .satisfied
        // A stray file wearing a skill's name is not a skill and is not an empty slot either.
        // Repairing it names what is in the way, which is what a person needs to see.
        case .other: return .repair(target: (root.path as NSString).appendingPathComponent(name))
        }
    }
}
