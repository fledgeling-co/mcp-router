import Foundation

// The types behind M7's two panes.
//
// **The one idea everything here follows from.** A *check* is a pure function of a wire type the
// control API already serves, and a stored result is that function's output stamped with the
// fingerprint it was computed against. There is no eval runner in this product: nothing here calls
// a server's tools with fixtures and grades the replies, and nothing here executes a skill at all —
// a skill is markdown the *client* loads into an agent's context, so it never traverses the router
// and no execution of it is observable to the process that would have to grade it.
//
// That is why the unit is a **check** rather than an eval, why a verdict never appears without the
// statement it judges, and why `CheckCopy` carries the disclosure as a permanent subtitle rather
// than a footnote.

/// What one check concluded.
///
/// Four cases rather than a `Bool`, and the third and fourth are the ones that earn their keep.
/// `unknown` means the router has not observed enough to answer — which is a different sentence
/// from "no", and rendering it as a failure would blame a capability for the router's own silence.
/// `notApplicable` means the question does not arise for this subject at all: an upstream that
/// carries no credentials cannot have current ones.
public enum CheckVerdict: String, Codable, Hashable, Sendable, CaseIterable {
    case passed
    case failed
    /// Not observed. Never rendered as a pass, and never as a failure.
    case unknown
    /// The question does not arise for this subject.
    case notApplicable

    /// Whether this verdict is one a human should look at.
    public var wantsAttention: Bool { self == .failed }
}

/// The eleven checks, as a closed set.
///
/// A `CaseIterable` enum rather than an array of strings, for the reason `Destination` is one: a
/// twelfth check cannot be added without every exhaustive switch failing to compile until it is
/// given a statement and a reason. A hand-maintained list would let one ship without copy.
public enum CheckID: String, Codable, Hashable, Sendable, CaseIterable {
    // Server checks — every input is a field on `MCPServer`.
    case indexes
    case declaresTools
    case authorized
    case surfaceApproved
    case operative
    case callsSucceed

    // Skill checks — every input is a field on `Skill` or `SkillsResponse.slotClients`.
    case reachable
    case versioned
    case originUnchanged
    case updateWantsNoMore
    case described

    /// Which kind of subject this check applies to. A server check is never run against a skill.
    public var subjectKind: CheckSubjectKind {
        switch self {
        case .indexes, .declaresTools, .authorized, .surfaceApproved, .operative, .callsSucceed:
            .server
        case .reachable, .versioned, .originUnchanged, .updateWantsNoMore, .described:
            .skill
        }
    }
}

public enum CheckSubjectKind: String, Codable, Hashable, Sendable, CaseIterable {
    case server
    case skill

    /// The word the row's `kind` column shows. Sentence case, per `DESIGN.md` §3.2.
    public var label: String {
        switch self {
        case .server: "Server"
        case .skill: "Skill"
        }
    }
}

/// One check's outcome.
///
/// `reason` is present for everything that is not `.passed`, and it names the **observation** that
/// produced the verdict rather than restating the verdict as an adjective. "never exercised" is a
/// reason; "failed" is not.
public struct CheckResult: Codable, Hashable, Sendable, Identifiable {
    public let check: CheckID
    public let verdict: CheckVerdict
    public let reason: String?

    public var id: String { check.rawValue }

    public init(_ check: CheckID, _ verdict: CheckVerdict, reason: String? = nil) {
        self.check = check
        self.verdict = verdict
        self.reason = reason
    }

    /// The statement this result judges. Held here so a verdict can never be rendered alone —
    /// every call site that has the verdict has the sentence, in the same value.
    public var statement: String { CheckCopy.statement(for: check) }
}

/// Which subject a stored run belongs to.
///
/// Keyed by kind **and** id so a server and a skill of the same name cannot collide in the store.
/// A skill's id is its resolved path, which is what M4 identifies skills by.
public struct SubjectKey: Codable, Hashable, Sendable {
    public let kind: CheckSubjectKind
    public let id: String

    public init(kind: CheckSubjectKind, id: String) {
        self.kind = kind
        self.id = id
    }

    public static func server(_ name: String) -> SubjectKey { SubjectKey(kind: .server, id: name) }
    public static func skill(path: String) -> SubjectKey { SubjectKey(kind: .skill, id: path) }
}

/// A fingerprint a result can be stamped against.
///
/// **Failable on purpose, and this is the whole of the "no result without a version" rule.** The
/// same device `ScaffoldedDestination` uses: a subject with no live fingerprint has no `Stamp` to
/// hand the store, so the refusal is a type rather than a rule a caller has to remember. A
/// `.standalone` skill has no version field anywhere in `SkillSource` — M4 modelled it as a closed
/// enum whose standalone case carries only a path — and a server that has never been indexed has no
/// `hash`. Neither can be stamped, so neither is stored, because nothing could ever invalidate it.
public struct Stamp: Codable, Hashable, Sendable {
    public let value: String

    public init?(_ value: String?) {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.value = value
    }

    /// A server's fingerprint is the digest of its tool surface — more precisely the version of the
    /// thing being checked than a version string an upstream can leave unchanged while its tools
    /// move underneath it.
    public static func forServer(_ server: MCPServer) -> Stamp? { Stamp(server.hash) }

    /// A skill's version is its **plugin's** version, shared by every skill that plugin supplies.
    /// M4 established this and named the field accordingly.
    public static func forSkill(_ skill: Skill) -> Stamp? {
        Stamp(skill.source.pluginOrigin?.pluginVersion)
    }
}

/// One run of a subject's checks, as stored.
///
/// The stamp travels **with** the results rather than beside them, so two runs against different
/// tool surfaces are visibly different evidence and can never be merged into one history row.
public struct StoredRun: Codable, Hashable, Sendable, Identifiable {
    public let stamp: Stamp
    public let ranAt: Date
    public let results: [CheckResult]

    public var id: String { "\(stamp.value)|\(ranAt.timeIntervalSince1970)" }

    public init(stamp: Stamp, ranAt: Date, results: [CheckResult]) {
        self.stamp = stamp
        self.ranAt = ranAt
        self.results = results
    }
}
