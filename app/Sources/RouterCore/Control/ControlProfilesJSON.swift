import Foundation

/// The JSON the `/profiles` routes answer with.
///
/// Split from the dispatch in `ControlProfiles.swift` so neither file carries both, and built out
/// of ``JSONValue`` members in a fixed order rather than through an encoder — the constraint
/// `scripts/lint/no-wire-codable.sh` enforces over this half of the router.
///
/// **Every member is always present, and an unobserved figure is `null` rather than `0`.** A count
/// the router could not take reads `null` beside the sentence saying why (`DESIGN.md` §6), so a
/// decoder can treat the shape as fixed and the values as optional instead of inferring an empty
/// store from a missing key.
extension ControlHandler {
    static func profileValue(_ record: ProfileRecord) -> JSONValue {
        ProfileDocument.value(record)
    }

    static func profileRowValue(_ row: ProfileListingRow) -> JSONValue {
        .object([
            JSONMember(key: JSString("name"), value: .string(JSString(row.name))),
            JSONMember(key: JSString("profile"), value: row.record.map(profileValue) ?? .null),
            // Present and null on a clean row, so a reader distinguishes "read fine" from a key it
            // failed to find. A profile with a problem is still listed and still counted — dropping
            // it would report a store with a broken profile as a store with one fewer.
            JSONMember(
                key: JSString("problem"),
                value: row.problem.map { JSONValue.string(JSString($0)) } ?? .null
            )
        ])
    }

    static func profileListingValue(_ listing: ProfileListing) -> JSONValue {
        .object([
            JSONMember(key: JSString("root"), value: .string(JSString(listing.root))),
            JSONMember(
                key: JSString("count"),
                value: listing.unreadable == nil ? .number(Double(listing.rows.count)) : .null
            ),
            JSONMember(
                key: JSString("unreadable"),
                value: listing.unreadable.map { JSONValue.string(JSString($0)) } ?? .null
            ),
            JSONMember(key: JSString("profiles"), value: .array(listing.rows.map(profileRowValue)))
        ])
    }

    /// The projection body.
    ///
    /// `applies` is a **fixed false**, and it is a member rather than a sentence in a comment for
    /// the reason `ReconciliationPlan.render()` prints its own disclaimer: a caller reading this
    /// body has to be able to tell that nothing here was or will be applied, without having read
    /// `spec-F8.md`. It is the one member in this file that is not a reading.
    static func projectionValue(_ projection: ProfileProjection) -> JSONValue {
        var counts: [JSONMember] = []
        for label in ["durable", "tell-elsewhere", "refused"] {
            counts.append(JSONMember(
                key: JSString(label),
                value: .number(Double(projection.steps(reaching: label).count))
            ))
        }
        return .object([
            JSONMember(key: JSString("profile"), value: .string(JSString(projection.profile.name))),
            JSONMember(key: JSString("applies"), value: .bool(false)),
            JSONMember(key: JSString("stepCount"), value: .number(Double(projection.steps.count))),
            JSONMember(key: JSString("reach"), value: .object(counts)),
            JSONMember(key: JSString("steps"), value: .array(projection.steps.map(stepValue))),
            // Named rather than silently absent. A harness with nowhere to put a skill is not a
            // harness that is satisfied, and a body that omitted it could not tell the two apart.
            JSONMember(
                key: JSString("withoutSkillRoot"),
                value: .array(projection.withoutSkillRoot.map { .string(JSString($0.rawValue)) })
            ),
            JSONMember(
                key: JSString("unreadableRoots"),
                value: .array(projection.unreadableRoots.map { .string(JSString($0)) })
            ),
            JSONMember(key: JSString("render"), value: .string(JSString(projection.render())))
        ])
    }

    static func stepValue(_ step: ProfileStep) -> JSONValue {
        .object([
            JSONMember(
                key: JSString("client"),
                value: step.client.map { JSONValue.string(JSString($0.rawValue)) } ?? .null
            ),
            JSONMember(
                key: JSString("subject"),
                value: .string(JSString(ProfileProjection.describe(step.subject)))
            ),
            JSONMember(key: JSString("action"), value: .string(JSString(step.action.label))),
            // The target of a repair, so a caller can see WHAT the link points at rather than only
            // that it is broken. Null on every other action, never an empty string.
            JSONMember(key: JSString("target"), value: targetValue(step.action)),
            JSONMember(key: JSString("reach"), value: .string(JSString(step.reach.label))),
            JSONMember(key: JSString("reachDetail"), value: .string(JSString(step.reach.detail)))
        ])
    }

    private static func targetValue(_ action: ProfileStep.Action) -> JSONValue {
        guard case let .repair(target) = action else { return .null }
        return .string(JSString(target))
    }
}
